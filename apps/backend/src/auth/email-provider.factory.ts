import { ConfigService } from '@nestjs/config';
import { EmailProvider } from '../common/interfaces/email-provider.interface';
import { ConsoleEmailProvider } from '../common/services/console-email.provider';
import { SmtpEmailProvider } from '../common/services/smtp-email.provider';

/// Chọn EmailProvider theo biến môi trường EMAIL_PROVIDER - cùng pattern với
/// sms-provider.factory.ts (selectSmsProvider) và PUSH_PROVIDER trong notifications.module.ts.
///
/// - "console" (mặc định nếu để trống): ConsoleEmailProvider - chỉ log, dùng development.
/// - "smtp": SmtpEmailProvider - gửi email thật qua SMTP tự cấu hình (không khoá cứng vào 1 nhà
///   cung cấp trả phí cụ thể - vận hành tự chọn SMTP relay phù hợp).
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
      return smtpProvider;
    default:
      throw new Error(
        `EMAIL_PROVIDER="${value}" không hợp lệ - chỉ chấp nhận "console" hoặc "smtp". Kiểm tra lại file .env/.env.staging.`,
      );
  }
}
