import { ConfigService } from '@nestjs/config';
import { Logger, ServiceUnavailableException } from '@nestjs/common';
import { SmtpEmailProvider, readSmtpConfig } from './smtp-email.provider';

// Mock nodemailer.createTransport - KHÔNG cần SMTP thật để chạy test (đặc tả §8 batch email
// provider thật: "Nếu test SMTP cần mock transport thì mock transport, KHÔNG cần credential thật").
const sendMailMock = jest.fn();
jest.mock('nodemailer', () => ({
  createTransport: jest.fn(() => ({ sendMail: sendMailMock })),
}));

describe('SmtpEmailProvider (đặc tả: gửi email xác minh thật qua SMTP, không leak secret)', () => {
  const FULL_SMTP_ENV: Record<string, string> = {
    SMTP_HOST: 'smtp.example.com',
    SMTP_PORT: '587',
    SMTP_USER: 'user@example.com',
    SMTP_PASS: 'super-secret-password',
    SMTP_FROM: 'no-reply@viecnhatrang.local',
  };

  function configWith(overrides: Record<string, string | undefined> = {}): ConfigService {
    const env = { ...FULL_SMTP_ENV, ...overrides };
    return { get: (key: string) => env[key] } as unknown as ConfigService;
  }

  beforeEach(() => {
    sendMailMock.mockReset();
  });

  describe('readSmtpConfig', () => {
    it('đủ 5 biến bắt buộc -> đọc đúng, SMTP_SECURE mặc định false khi không đặt', () => {
      const result = readSmtpConfig(configWith());
      expect(result).toEqual({
        host: 'smtp.example.com',
        port: 587,
        secure: false,
        user: 'user@example.com',
        pass: 'super-secret-password',
        from: 'no-reply@viecnhatrang.local',
      });
    });

    it.each(['SMTP_HOST', 'SMTP_PORT', 'SMTP_USER', 'SMTP_PASS', 'SMTP_FROM'])(
      'thiếu %s -> throw lỗi rõ ràng nêu đúng tên biến',
      (missingKey) => {
        expect(() => readSmtpConfig(configWith({ [missingKey]: undefined }))).toThrow(new RegExp(missingKey));
      },
    );

    it('SMTP_PORT không phải số nguyên dương -> throw', () => {
      expect(() => readSmtpConfig(configWith({ SMTP_PORT: '0' }))).toThrow(/SMTP_PORT/);
      expect(() => readSmtpConfig(configWith({ SMTP_PORT: 'abc' }))).toThrow(/SMTP_PORT/);
    });
  });

  describe('sendVerificationEmail', () => {
    it('gửi thành công - gọi sendMail với nội dung tiếng Việt có thương hiệu và mã xác minh', async () => {
      sendMailMock.mockResolvedValue({ messageId: 'ok' });
      const provider = new SmtpEmailProvider(configWith());

      await provider.sendVerificationEmail('seeker@example.com', '123456');

      expect(sendMailMock).toHaveBeenCalledTimes(1);
      const call = sendMailMock.mock.calls[0][0];
      expect(call.to).toBe('seeker@example.com');
      expect(call.from).toBe('no-reply@viecnhatrang.local');
      expect(call.text).toContain('VIỆC NHA TRANG');
      expect(call.text).toContain('123456');
      expect(call.text.toLowerCase()).toContain('hiệu lực');
      // Không đưa credential/token nội bộ vào nội dung email.
      expect(call.text).not.toContain(FULL_SMTP_ENV.SMTP_PASS);
    });

    it('lỗi kết nối SMTP (ECONNREFUSED) -> map về ServiceUnavailableException, không lộ chi tiết SMTP', async () => {
      sendMailMock.mockRejectedValue(Object.assign(new Error('connect ECONNREFUSED 127.0.0.1:587'), { code: 'ECONNREFUSED' }));
      const provider = new SmtpEmailProvider(configWith());

      await expect(provider.sendVerificationEmail('seeker@example.com', '123456')).rejects.toBeInstanceOf(
        ServiceUnavailableException,
      );
    });

    it('lỗi xác thực SMTP (EAUTH - sai user/pass) -> map về ServiceUnavailableException', async () => {
      sendMailMock.mockRejectedValue(Object.assign(new Error('Invalid login: 535 authentication failed'), { code: 'EAUTH' }));
      const provider = new SmtpEmailProvider(configWith());

      await expect(provider.sendVerificationEmail('seeker@example.com', '123456')).rejects.toBeInstanceOf(
        ServiceUnavailableException,
      );
    });

    it('timeout kết nối SMTP -> map về ServiceUnavailableException', async () => {
      sendMailMock.mockRejectedValue(Object.assign(new Error('Connection timeout'), { code: 'ETIMEDOUT' }));
      const provider = new SmtpEmailProvider(configWith());

      await expect(provider.sendVerificationEmail('seeker@example.com', '123456')).rejects.toBeInstanceOf(
        ServiceUnavailableException,
      );
    });

    it('response không hợp lệ/lỗi không xác định từ SMTP server -> map về ServiceUnavailableException', async () => {
      sendMailMock.mockRejectedValue(new Error('Unexpected socket close'));
      const provider = new SmtpEmailProvider(configWith());

      await expect(provider.sendVerificationEmail('seeker@example.com', '123456')).rejects.toBeInstanceOf(
        ServiceUnavailableException,
      );
    });

    it('KHÔNG throw raw lỗi SMTP ra ngoài (message luôn là câu tiếng Việt an toàn, không lộ host/port/lý do kỹ thuật)', async () => {
      sendMailMock.mockRejectedValue(new Error('some internal smtp detail leaking host/port'));
      const provider = new SmtpEmailProvider(configWith());

      await expect(provider.sendVerificationEmail('seeker@example.com', '123456')).rejects.toMatchObject({
        message: 'Không thể gửi email xác minh lúc này, vui lòng thử lại.',
      });
    });

    it('thiếu cấu hình SMTP khi gọi trực tiếp provider (bỏ qua factory) vẫn throw rõ ràng, không log SMTP_PASS', async () => {
      const provider = new SmtpEmailProvider(configWith({ SMTP_HOST: undefined }));
      await expect(provider.sendVerificationEmail('seeker@example.com', '123456')).rejects.toThrow(/SMTP_HOST/);
      expect(sendMailMock).not.toHaveBeenCalled();
    });

    it('log lỗi gửi email KHÔNG chứa SMTP_PASS hay mã xác minh (đặc tả §3/§6: không log secret/code)', async () => {
      const loggerSpy = jest.spyOn(Logger.prototype, 'error').mockImplementation(() => undefined);
      sendMailMock.mockRejectedValue(new Error('SMTP server rejected the message'));
      const provider = new SmtpEmailProvider(configWith());

      await expect(provider.sendVerificationEmail('seeker@example.com', '999999')).rejects.toBeInstanceOf(
        ServiceUnavailableException,
      );

      expect(loggerSpy).toHaveBeenCalled();
      const loggedMessages = loggerSpy.mock.calls.map((call) => String(call[0])).join('\n');
      expect(loggedMessages).not.toContain(FULL_SMTP_ENV.SMTP_PASS);
      expect(loggedMessages).not.toContain('999999');
      loggerSpy.mockRestore();
    });
  });
});
