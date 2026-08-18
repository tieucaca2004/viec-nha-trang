import { ConfigService } from '@nestjs/config';
import { SmsProvider } from '../common/interfaces/sms-provider.interface';
import { ConsoleSmsProvider } from '../common/services/console-sms.provider';
import { EsmsProvider } from '../common/services/esms.provider';

/// Chọn SmsProvider theo biến môi trường SMS_PROVIDER - tách thành hàm riêng (không viết trực
/// tiếp trong useFactory của AuthModule) để test được logic chọn provider mà không cần khởi tạo
/// cả Nest DI container. Theo đúng pattern PUSH_PROVIDER đã có trong notifications.module.ts.
///
/// - "console" (mặc định nếu để trống, khớp .env.example): ConsoleSmsProvider - chỉ log, dùng
///   development.
/// - "esms": EsmsProvider - gửi SMS thật qua eSMS.vn, dùng staging/production.
/// - Giá trị khác: fail fast ngay lúc khởi động app (không phải lúc gửi OTP đầu tiên) - tránh
///   deploy nhầm cấu hình mà không phát hiện được cho tới khi có user thật request OTP.
export function selectSmsProvider(
  config: ConfigService,
  consoleProvider: ConsoleSmsProvider,
  esmsProvider: EsmsProvider,
): SmsProvider {
  const value = config.get<string>('SMS_PROVIDER') ?? 'console';
  switch (value) {
    case 'console':
      return consoleProvider;
    case 'esms':
      return esmsProvider;
    default:
      throw new Error(
        `SMS_PROVIDER="${value}" không hợp lệ - chỉ chấp nhận "console" hoặc "esms". Kiểm tra lại file .env/.env.staging.`,
      );
  }
}
