import { ConfigService } from '@nestjs/config';
import { selectEmailProvider } from './email-provider.factory';
import { ConsoleEmailProvider } from '../common/services/console-email.provider';
import { SmtpEmailProvider } from '../common/services/smtp-email.provider';

// Đặc tả (batch email provider thật): chọn EmailProvider bằng EMAIL_PROVIDER, cùng nguyên tắc
// "fail fast ngay lúc khởi động app" với selectSmsProvider - kể cả khi thiếu cấu hình SMTP_*,
// không chỉ khi EMAIL_PROVIDER là giá trị rác.
describe('selectEmailProvider (đặc tả: chọn EmailProvider bằng EMAIL_PROVIDER, fail fast lúc khởi động)', () => {
  const consoleProvider = new ConsoleEmailProvider();
  const smtpProvider = {} as SmtpEmailProvider;

  const FULL_SMTP_ENV: Record<string, string> = {
    SMTP_HOST: 'smtp.example.com',
    SMTP_PORT: '587',
    SMTP_USER: 'user@example.com',
    SMTP_PASS: 'super-secret-password',
    SMTP_FROM: 'no-reply@viecnhatrang.local',
  };

  function configWith(env: Record<string, string | undefined>): ConfigService {
    return { get: (key: string) => env[key] } as unknown as ConfigService;
  }

  it('EMAIL_PROVIDER=console -> trả về ConsoleEmailProvider', () => {
    expect(selectEmailProvider(configWith({ EMAIL_PROVIDER: 'console' }), consoleProvider, smtpProvider)).toBe(
      consoleProvider,
    );
  });

  it('EMAIL_PROVIDER không đặt (undefined) -> mặc định ConsoleEmailProvider', () => {
    expect(selectEmailProvider(configWith({}), consoleProvider, smtpProvider)).toBe(consoleProvider);
  });

  it('EMAIL_PROVIDER=smtp với đủ cấu hình -> trả về SmtpEmailProvider', () => {
    expect(
      selectEmailProvider(configWith({ EMAIL_PROVIDER: 'smtp', ...FULL_SMTP_ENV }), consoleProvider, smtpProvider),
    ).toBe(smtpProvider);
  });

  it('EMAIL_PROVIDER=giá trị không hợp lệ -> fail fast với lỗi rõ ràng', () => {
    expect(() => selectEmailProvider(configWith({ EMAIL_PROVIDER: 'sendgrid' }), consoleProvider, smtpProvider)).toThrow(
      /EMAIL_PROVIDER="sendgrid" không hợp lệ/,
    );
  });

  it.each(['SMTP_HOST', 'SMTP_PORT', 'SMTP_USER', 'SMTP_PASS', 'SMTP_FROM'])(
    'EMAIL_PROVIDER=smtp nhưng thiếu %s -> fail fast NGAY LÚC CHỌN PROVIDER (không đợi tới lúc gửi email)',
    (missingKey) => {
      const env = { EMAIL_PROVIDER: 'smtp', ...FULL_SMTP_ENV, [missingKey]: undefined };
      expect(() => selectEmailProvider(configWith(env), consoleProvider, smtpProvider)).toThrow(
        new RegExp(missingKey.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
      );
    },
  );

  it('EMAIL_PROVIDER=smtp với SMTP_PORT không phải số hợp lệ -> fail fast', () => {
    const env = { EMAIL_PROVIDER: 'smtp', ...FULL_SMTP_ENV, SMTP_PORT: 'not-a-number' };
    expect(() => selectEmailProvider(configWith(env), consoleProvider, smtpProvider)).toThrow(/SMTP_PORT/);
  });

  it('lỗi cấu hình thiếu SMTP KHÔNG chứa giá trị thật của SMTP_PASS (không leak secret trong message lỗi)', () => {
    const env = { EMAIL_PROVIDER: 'smtp', ...FULL_SMTP_ENV, SMTP_HOST: undefined };
    try {
      selectEmailProvider(configWith(env), consoleProvider, smtpProvider);
      fail('phải throw');
    } catch (error) {
      expect(String(error)).not.toContain(FULL_SMTP_ENV.SMTP_PASS);
    }
  });
});
