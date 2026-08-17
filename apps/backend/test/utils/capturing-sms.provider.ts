import { Injectable } from '@nestjs/common';
import { SmsProvider } from '../../src/common/interfaces/sms-provider.interface';

/** Test double: giữ lại mã OTP gần nhất theo số điện thoại thay vì gửi SMS thật. */
@Injectable()
export class CapturingSmsProvider implements SmsProvider {
  private readonly codesByPhone = new Map<string, string>();

  async sendOtp(phone: string, code: string): Promise<void> {
    this.codesByPhone.set(phone, code);
  }

  getLastCode(phone: string): string {
    const code = this.codesByPhone.get(phone);
    if (!code) throw new Error(`No OTP captured for phone ${phone}`);
    return code;
  }
}
