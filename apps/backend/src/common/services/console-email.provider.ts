import { Injectable, Logger } from '@nestjs/common';
import { EmailProvider } from '../interfaces/email-provider.interface';

// Provider mặc định cho development/staging: log mã xác minh ra console thay vì gửi email thật -
// cùng pattern với ConsoleSmsProvider (console-sms.provider.ts). Production phải cấu hình
// EMAIL_PROVIDER trỏ tới provider thật (không dùng provider này) - xem email-provider.factory.ts.
@Injectable()
export class ConsoleEmailProvider implements EmailProvider {
  private readonly logger = new Logger(ConsoleEmailProvider.name);
  private readonly lastCodeByEmail = new Map<string, string>();

  async sendVerificationEmail(email: string, code: string): Promise<void> {
    this.logger.warn(`[DEV EMAIL VERIFY] email=${email} code=${code}`);
    this.lastCodeByEmail.set(email, code);
  }

  getLastCode(email: string): string | undefined {
    return this.lastCodeByEmail.get(email);
  }
}
