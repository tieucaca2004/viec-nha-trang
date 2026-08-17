import { Injectable, Logger } from '@nestjs/common';
import { SmsProvider } from '../interfaces/sms-provider.interface';

// Provider mặc định cho development/staging: log OTP ra console thay vì gửi SMS thật.
// Production phải cấu hình SMS_PROVIDER trỏ tới một provider thật (không dùng provider này).
@Injectable()
export class ConsoleSmsProvider implements SmsProvider {
  private readonly logger = new Logger(ConsoleSmsProvider.name);

  async sendOtp(phone: string, code: string): Promise<void> {
    this.logger.warn(`[DEV OTP] phone=${phone} code=${code}`);
  }
}
