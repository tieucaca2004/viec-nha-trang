import { Injectable, Logger } from '@nestjs/common';
import { SmsProvider } from '../interfaces/sms-provider.interface';

// Provider mặc định cho development/staging: log OTP ra console thay vì gửi SMS thật.
// Production phải cấu hình SMS_PROVIDER trỏ tới một provider thật (không dùng provider này).
// Giữ mã gần nhất trong bộ nhớ để phục vụ load test tự động (xem AuthController.debugOtp và
// docs/LOAD_TESTING.md) - route đọc giá trị này chỉ bật khi NODE_ENV !== 'production'.
@Injectable()
export class ConsoleSmsProvider implements SmsProvider {
  private readonly logger = new Logger(ConsoleSmsProvider.name);
  private readonly lastCodeByPhone = new Map<string, string>();

  async sendOtp(phone: string, code: string): Promise<void> {
    this.logger.warn(`[DEV OTP] phone=${phone} code=${code}`);
    this.lastCodeByPhone.set(phone, code);
  }

  getLastCode(phone: string): string | undefined {
    return this.lastCodeByPhone.get(phone);
  }
}
