import { BadRequestException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { AuthService } from './auth.service';

// Test đơn vị riêng cho logic resend cooldown của đăng ký email (đặc tả §1) - phần này KHÔNG
// verify được qua e2e vì .env.test đặt EMAIL_VERIFICATION_RESEND_COOLDOWN_SECONDS=0 (để các
// e2e test khác không bị chặn cooldown khi gọi request nhiều lần liên tiếp).
describe('AuthService.requestEmailVerification - resend cooldown', () => {
  function buildService(cooldownSeconds: number, lastCodeCreatedAt: Date | null) {
    const config = {
      get: (key: string) => {
        if (key === 'EMAIL_VERIFICATION_RESEND_COOLDOWN_SECONDS') return String(cooldownSeconds);
        if (key === 'EMAIL_VERIFICATION_TTL_SECONDS') return '600';
        return undefined;
      },
    } as unknown as ConfigService;

    const prisma = {
      user: { findUnique: jest.fn().mockResolvedValue(null) },
      emailVerificationCode: {
        findFirst: jest.fn().mockResolvedValue(
          lastCodeCreatedAt ? { createdAt: lastCodeCreatedAt, consumedAt: null } : null,
        ),
        create: jest.fn().mockResolvedValue({}),
      },
    };

    const emailProvider = { sendVerificationEmail: jest.fn().mockResolvedValue(undefined) };
    const smsProvider = { sendOtp: jest.fn() };

    const service = new AuthService(
      prisma as any,
      {} as JwtService,
      config,
      smsProvider as any,
      emailProvider as any,
    );

    return { service, prisma, emailProvider };
  }

  it('từ chối gửi lại mã khi mã trước đó còn trong khoảng cooldown', async () => {
    const { service, emailProvider } = buildService(60, new Date(Date.now() - 10_000)); // gửi 10s trước, cooldown 60s

    await expect(service.requestEmailVerification('cooldown@example.test')).rejects.toThrow(BadRequestException);
    expect(emailProvider.sendVerificationEmail).not.toHaveBeenCalled();
  });

  it('cho phép gửi lại mã khi đã hết cooldown', async () => {
    const { service, emailProvider } = buildService(60, new Date(Date.now() - 61_000)); // gửi 61s trước, cooldown 60s

    await expect(service.requestEmailVerification('after-cooldown@example.test')).resolves.toEqual({
      expiresInSeconds: 600,
    });
    expect(emailProvider.sendVerificationEmail).toHaveBeenCalledTimes(1);
  });

  it('cho phép gửi ngay lần đầu (chưa có mã nào trước đó)', async () => {
    const { service, emailProvider } = buildService(60, null);

    await expect(service.requestEmailVerification('first-time@example.test')).resolves.toEqual({
      expiresInSeconds: 600,
    });
    expect(emailProvider.sendVerificationEmail).toHaveBeenCalledTimes(1);
  });

  // Regression: trước đây bản ghi mã được tạo TRƯỚC khi gửi, và nếu gửi email thất bại thì bản ghi
  // đó vẫn còn (consumedAt=null). Lần gửi lại kế tiếp - kể cả ở màn Đăng nhập (dùng chung đúng
  // logic này) - bị cooldown giả "Vui lòng đợi N giây" chặn, khiến CẢ đăng ký lẫn đăng nhập cùng
  // "hỏng". Đảm bảo: gửi lỗi -> xoá đúng bản ghi vừa tạo + ném lại lỗi gốc.
  it('gửi email thất bại -> xoá bản ghi mã vừa tạo (tránh cooldown giả) và ném lại lỗi gốc', async () => {
    const config = {
      get: (key: string) => {
        if (key === 'EMAIL_VERIFICATION_RESEND_COOLDOWN_SECONDS') return '60';
        if (key === 'EMAIL_VERIFICATION_TTL_SECONDS') return '600';
        return undefined;
      },
    } as unknown as ConfigService;

    const prisma = {
      user: { findUnique: jest.fn().mockResolvedValue(null) },
      emailVerificationCode: {
        findFirst: jest.fn().mockResolvedValue(null),
        create: jest.fn().mockResolvedValue({ id: 'code-1' }),
        delete: jest.fn().mockResolvedValue({}),
      },
    };

    const sendError = new Error('smtp down');
    const emailProvider = { sendVerificationEmail: jest.fn().mockRejectedValue(sendError) };
    const smsProvider = { sendOtp: jest.fn() };

    const service = new AuthService(
      prisma as any,
      {} as JwtService,
      config,
      smsProvider as any,
      emailProvider as any,
    );

    await expect(service.requestEmailVerification('fail@example.test')).rejects.toThrow('smtp down');

    // Xoá đúng bản ghi VỪA TẠO -> không còn mã mồ côi nào để cooldown chặn lần gửi sau.
    expect(prisma.emailVerificationCode.delete).toHaveBeenCalledWith({ where: { id: 'code-1' } });
    expect(prisma.emailVerificationCode.delete).toHaveBeenCalledTimes(1);
  });
});
