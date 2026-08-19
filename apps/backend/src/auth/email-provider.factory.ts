import { ConfigService } from '@nestjs/config';
import { EmailProvider } from '../common/interfaces/email-provider.interface';
import { ConsoleEmailProvider } from '../common/services/console-email.provider';
import { SmtpEmailProvider, readSmtpConfig } from '../common/services/smtp-email.provider';

/// Chọn EmailProvider theo biến môi trường EMAIL_PROVIDER - cùng pattern với
/// sms-provider.factory.ts (selectSmsProvider) và PUSH_PROVIDER trong notifications.module.ts.
///
/// - "console" (mặc định nếu để trống): ConsoleEmailProvider - chỉ log, dùng development.
/// - "smtp": SmtpEmailProvider - gửi email thật qua SMTP tự cấu hình (không khoá cứng vào 1 nhà
///   cung cấp trả phí cụ thể - vận hành tự chọn SMTP relay phù hợp). Thiếu bất kỳ biến bắt buộc
///   nào (SMTP_HOST/PORT/USER/PASS/FROM) sẽ fail fast NGAY LÚC KHỞI ĐỘNG APP (readSmtpConfig),
///   không đợi tới lần gửi email đầu tiên mới phát hiện.
/// - Giá trị khác: fail fast ngay lúc khởi động app.
export function selectEmailProvider(
  config: ConfigService,
  consoleProvider: ConsoleEmailProvider,
  smtpProvider: SmtpEmailProvider,
): EmailProvider {
  const value = config.get<string>('EMAIL_PROVIDER') ?? 'console';
  switch (value) {
    case 'console':
      return consoleProvider;
    case 'smtp':
      readSmtpConfig(config); // throws ngay nếu thiếu/sai cấu hình - fail fast lúc khởi động.
      return smtpProvider;
    default:
      throw new Error(
        `EMAIL_PROVIDER="${value}" không hợp lệ - chỉ chấp nhận "console" hoặc "smtp". Kiểm tra lại file .env/.env.staging.`,
      );
  }
}
