import { BadRequestException, ConflictException, Injectable, NotImplementedException, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { Inject } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { SmsProvider } from '../common/interfaces/sms-provider.interface';
import { EmailProvider } from '../common/interfaces/email-provider.interface';
import { SMS_PROVIDER, EMAIL_PROVIDER } from '../common/services/tokens';
import { generateOtpCode, hashValue, verifyHash } from '../common/services/hash.util';

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
    @Inject(SMS_PROVIDER) private readonly smsProvider: SmsProvider,
    @Inject(EMAIL_PROVIDER) private readonly emailProvider: EmailProvider,
  ) {}

  async requestOtp(phone: string): Promise<{ expiresInSeconds: number }> {
    const ttlSeconds = Number(this.config.get('OTP_TTL_SECONDS') ?? 300);
    const code = generateOtpCode();
    const codeHash = hashValue(code);
    const expiresAt = new Date(Date.now() + ttlSeconds * 1000);

    const user = await this.prisma.user.findUnique({ where: { phone } });

    await this.prisma.otpCode.create({
      data: { phone, codeHash, expiresAt, userId: user?.id },
    });

    await this.smsProvider.sendOtp(phone, code);

    return { expiresInSeconds: ttlSeconds };
  }

  // Tách logic tiêu thụ OtpCode dùng chung cho cả đăng nhập (verifyOtp) và xác minh số điện
  // thoại cho tài khoản đã đăng nhập (verifyPhoneLink, đặc tả §3) - cùng 1 nguyên lý "chứng minh
  // đang sở hữu số điện thoại này ngay bây giờ", chỉ khác việc dùng kết quả đó để làm gì.
  private async consumeOtpCode(phone: string, code: string): Promise<void> {
    const maxAttempts = Number(this.config.get('OTP_MAX_ATTEMPTS') ?? 5);

    const otp = await this.prisma.otpCode.findFirst({
      where: { phone, consumedAt: null, expiresAt: { gt: new Date() } },
      orderBy: { createdAt: 'desc' },
    });

    if (!otp || otp.attempts >= maxAttempts) {
      throw new BadRequestException('Mã OTP không hợp lệ hoặc đã hết hạn.');
    }

    const isValid = verifyHash(code, otp.codeHash);
    if (!isValid) {
      await this.prisma.otpCode.update({ where: { id: otp.id }, data: { attempts: { increment: 1 } } });
      throw new BadRequestException('Mã OTP không đúng.');
    }

    await this.prisma.otpCode.update({ where: { id: otp.id }, data: { consumedAt: new Date() } });
  }

  async verifyOtp(phone: string, code: string) {
    await this.consumeOtpCode(phone, code);

    let user = await this.prisma.user.findUnique({ where: { phone } });
    if (!user) {
      user = await this.prisma.user.create({
        data: { phone, isPhoneVerified: true, roles: ['JOB_SEEKER'], lastLoginAt: new Date() },
      });
    } else if (!user.isPhoneVerified) {
      user = await this.prisma.user.update({
        where: { id: user.id },
        data: { isPhoneVerified: true, lastLoginAt: new Date() },
      });
    } else {
      user = await this.prisma.user.update({ where: { id: user.id }, data: { lastLoginAt: new Date() } });
    }

    if (user.isBanned) {
      throw new UnauthorizedException('Tài khoản đã bị khóa.');
    }

    return this.issueTokens(user.id, user.roles);
  }

  // ---------- Đăng ký tài khoản bằng email (đặc tả §1) ----------
  // KHÔNG dùng SMS OTP cho bước tạo tài khoản nữa - email là kênh xác minh chính khi đăng ký.
  // SmsProvider/OtpCode vẫn giữ nguyên, chỉ dùng cho xác minh số điện thoại khi cần (§3) và cho
  // đăng nhập lại bằng phone OTP (verifyOtp ở trên - KHÔNG bị thay đổi hành vi).

  // Gửi mã OTP qua email - dùng chung logic nghiệp vụ cho CẢ đăng ký lẫn ĐĂNG NHẬP (cùng một thao
  // tác "chứng minh bạn sở hữu email này"), gọi từ 2 route KHÁC NHAU với 2 hạn mức throttle KHÁC
  // NHAU (POST /auth/register/email/request và POST /auth/login/email/request - xem
  // auth.controller.ts) để đăng ký và đăng nhập không còn ăn chung 1 bucket rate limit. verifyEmailAndRegister()
  // bên dưới xử lý sẵn cả 2 trường hợp (email chưa có tài khoản -> tạo mới; email đã có -> đăng nhập).
  //
  // Trước đây hàm này chặn email đã verified bằng lỗi 400 "Email này đã được đăng ký. Vui lòng đăng
  // nhập." vì endpoint chỉ phục vụ đăng ký. Khi app có màn Đăng nhập bằng email OTP (kiến trúc
  // OTP-first, không mật khẩu), chính guard đó làm ĐĂNG NHẬP BẤT KHẢ THI: người dùng có tài khoản
  // nhập email của mình thì bị 400, bấm lại nhiều lần thì chạm rate limit và nhận thông báo "thao
  // tác quá nhanh" - đúng lỗi đã tái hiện được trên Beta. Bỏ guard này còn làm phản hồi ĐỒNG NHẤT
  // cho email đã/chưa đăng ký, nên chống dò tài khoản (account enumeration) tốt hơn trước.
  //
  // Cooldown gửi lại (theo EMAIL, không theo IP/route) và rate limit theo route giữ NGUYÊN -
  // không nới lỏng bất kỳ giới hạn nào.
  async requestEmailVerification(email: string): Promise<{ expiresInSeconds: number }> {
    const existing = await this.prisma.user.findUnique({ where: { email } });

    const resendCooldownSeconds = Number(this.config.get('EMAIL_VERIFICATION_RESEND_COOLDOWN_SECONDS') ?? 60);
    const lastCode = await this.prisma.emailVerificationCode.findFirst({
      where: { email, consumedAt: null },
      orderBy: { createdAt: 'desc' },
    });
    if (lastCode && Date.now() - lastCode.createdAt.getTime() < resendCooldownSeconds * 1000) {
      const waitSeconds = resendCooldownSeconds - Math.floor((Date.now() - lastCode.createdAt.getTime()) / 1000);
      throw new BadRequestException(`Vui lòng đợi ${waitSeconds} giây trước khi gửi lại mã.`);
    }

    const ttlSeconds = Number(this.config.get('EMAIL_VERIFICATION_TTL_SECONDS') ?? 600);
    const code = generateOtpCode();
    const codeHash = hashValue(code); // scrypt salted hash - không lưu plaintext (đặc tả §1)
    const expiresAt = new Date(Date.now() + ttlSeconds * 1000);

    await this.prisma.emailVerificationCode.create({
      data: { email, codeHash, expiresAt, userId: existing?.id },
    });

    await this.emailProvider.sendVerificationEmail(email, code);

    return { expiresInSeconds: ttlSeconds };
  }

  async verifyEmailAndRegister(email: string, code: string) {
    const maxAttempts = Number(this.config.get('EMAIL_VERIFICATION_MAX_ATTEMPTS') ?? 5);

    const verification = await this.prisma.emailVerificationCode.findFirst({
      where: { email, consumedAt: null, expiresAt: { gt: new Date() } },
      orderBy: { createdAt: 'desc' },
    });

    if (!verification || verification.attempts >= maxAttempts) {
      throw new BadRequestException('Mã xác minh không hợp lệ hoặc đã hết hạn.');
    }

    const isValid = verifyHash(code, verification.codeHash);
    if (!isValid) {
      await this.prisma.emailVerificationCode.update({
        where: { id: verification.id },
        data: { attempts: { increment: 1 } },
      });
      throw new BadRequestException('Mã xác minh không đúng.');
    }

    await this.prisma.emailVerificationCode.update({
      where: { id: verification.id },
      data: { consumedAt: new Date() },
    });

    let user = await this.prisma.user.findUnique({ where: { email } });
    if (!user) {
      user = await this.prisma.user.create({
        data: {
          email,
          isEmailVerified: true,
          authProvider: 'EMAIL',
          roles: ['JOB_SEEKER'],
          lastLoginAt: new Date(),
        },
      });
    } else {
      user = await this.prisma.user.update({
        where: { id: user.id },
        data: { isEmailVerified: true, lastLoginAt: new Date() },
      });
    }

    if (user.isBanned) {
      throw new UnauthorizedException('Tài khoản đã bị khóa.');
    }

    return this.issueTokens(user.id, user.roles);
  }

  // ---------- Xác minh số điện thoại cho tài khoản đã đăng nhập (đặc tả §3) ----------
  // KHÔNG phải đăng nhập - dùng khi user đã có tài khoản (qua email) muốn gắn/verify số điện
  // thoại trước khi ứng tuyển/đăng tuyển. Tái dùng OtpCode + SmsProvider + consumeOtpCode ở trên
  // (không tạo bảng/hạ tầng SMS mới) theo đúng yêu cầu giữ nguyên SmsProvider/ConsoleSmsProvider/
  // EsmsProvider/SMS_PROVIDER.

  async requestPhoneLink(userId: string, phone: string): Promise<{ expiresInSeconds: number }> {
    const owner = await this.prisma.user.findUnique({ where: { phone } });
    if (owner && owner.id !== userId && owner.isPhoneVerified) {
      throw new ConflictException('Số điện thoại này đã được xác minh bởi một tài khoản khác.');
    }

    const ttlSeconds = Number(this.config.get('OTP_TTL_SECONDS') ?? 300);
    const code = generateOtpCode();
    const codeHash = hashValue(code);
    const expiresAt = new Date(Date.now() + ttlSeconds * 1000);

    await this.prisma.otpCode.create({ data: { phone, codeHash, expiresAt, userId } });
    await this.smsProvider.sendOtp(phone, code);

    return { expiresInSeconds: ttlSeconds };
  }

  async verifyPhoneLink(userId: string, phone: string, code: string): Promise<{ phone: string; isPhoneVerified: boolean }> {
    await this.consumeOtpCode(phone, code);

    try {
      const user = await this.prisma.user.update({
        where: { id: userId },
        data: { phone, isPhoneVerified: true },
      });
      return { phone: user.phone!, isPhoneVerified: user.isPhoneVerified };
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        throw new ConflictException('Số điện thoại này đã được xác minh bởi một tài khoản khác.');
      }
      throw error;
    }
  }

  async refresh(refreshToken: string) {
    let payload: { sub: string };
    try {
      payload = this.jwt.verify(refreshToken, { secret: this.config.get('JWT_REFRESH_SECRET') });
    } catch {
      throw new UnauthorizedException('Refresh token không hợp lệ.');
    }

    const tokenRows = await this.prisma.refreshToken.findMany({
      where: { userId: payload.sub, revokedAt: null, expiresAt: { gt: new Date() } },
    });
    const matching = tokenRows.find((row) => verifyHash(refreshToken, row.tokenHash));
    if (!matching) {
      throw new UnauthorizedException('Refresh token không hợp lệ hoặc đã bị thu hồi.');
    }

    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: payload.sub } });
    if (user.isBanned) throw new UnauthorizedException('Tài khoản đã bị khóa.');

    await this.prisma.refreshToken.update({ where: { id: matching.id }, data: { revokedAt: new Date() } });

    return this.issueTokens(user.id, user.roles);
  }

  // Sửa lỗi High #7 (FULL AUDIT): trước đây "đăng xuất" chỉ xoá token phía client, refresh token
  // vẫn còn hợp lệ trên server. Ở đây thu hồi (revokedAt) đúng hàng refresh token đang dùng -
  // idempotent thật: token không tồn tại/đã revoke/hết hạn/không parse được đều trả về thành
  // công (không throw), vì kết quả cuối cùng người gọi mong muốn ("token này không dùng được
  // nữa") đã đúng trong mọi trường hợp đó.
  async logout(refreshToken: string): Promise<{ success: true }> {
    let payload: { sub: string };
    try {
      payload = this.jwt.verify(refreshToken, { secret: this.config.get('JWT_REFRESH_SECRET') });
    } catch {
      return { success: true };
    }

    const tokenRows = await this.prisma.refreshToken.findMany({
      where: { userId: payload.sub, revokedAt: null },
    });
    const matching = tokenRows.find((row) => verifyHash(refreshToken, row.tokenHash));
    if (matching) {
      await this.prisma.refreshToken.update({ where: { id: matching.id }, data: { revokedAt: new Date() } });
    }

    return { success: true };
  }

  async loginWithGoogle(_idToken: string): Promise<never> {
    // Điểm mở rộng: xác thực idToken qua Google, tìm/tạo user theo email, issueTokens().
    throw new NotImplementedException('Đăng nhập Google sẽ được bật ở bản phát hành sau.');
  }

  async loginWithApple(_identityToken: string): Promise<never> {
    // Điểm mở rộng: xác thực identityToken qua Apple, tìm/tạo user theo email/sub, issueTokens().
    throw new NotImplementedException('Đăng nhập Apple sẽ được bật ở bản phát hành sau.');
  }

  private async issueTokens(userId: string, roles: string[]) {
    const accessToken = this.jwt.sign(
      { sub: userId, roles },
      { secret: this.config.get('JWT_ACCESS_SECRET'), expiresIn: this.config.get('JWT_ACCESS_EXPIRES_IN') },
    );
    // jti ngẫu nhiên: đảm bảo 2 phiên đăng nhập của cùng 1 user trong cùng 1 giây (2 thiết bị,
    // hoặc test chạy nhanh) không sinh ra 2 JWT giống hệt nhau byte-for-byte (payload+iat+exp
    // trùng => token trùng). Nếu không có jti, logout 1 phiên có thể vô tình làm mất hiệu lực
    // (hoặc bỏ sót thu hồi) phiên còn lại vì chúng thực chất là cùng 1 chuỗi token - phát hiện
    // khi viết test cho High fix #7.
    const refreshToken = this.jwt.sign(
      { sub: userId, jti: randomUUID() },
      { secret: this.config.get('JWT_REFRESH_SECRET'), expiresIn: this.config.get('JWT_REFRESH_EXPIRES_IN') },
    );

    const refreshExpiresInDays = this.parseDaysFromExpiresIn(this.config.get('JWT_REFRESH_EXPIRES_IN') ?? '30d');
    await this.prisma.refreshToken.create({
      data: {
        userId,
        tokenHash: hashValue(refreshToken),
        expiresAt: new Date(Date.now() + refreshExpiresInDays * 24 * 60 * 60 * 1000),
      },
    });

    return { accessToken, refreshToken };
  }

  private parseDaysFromExpiresIn(value: string): number {
    const match = /^(\d+)d$/.exec(value);
    return match ? Number(match[1]) : 30;
  }
}
