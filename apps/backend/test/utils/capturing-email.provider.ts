import { Injectable } from '@nestjs/common';
import { EmailProvider } from '../../src/common/interfaces/email-provider.interface';

/** Test double: giữ lại mã xác minh gần nhất theo email thay vì gửi email thật. */
@Injectable()
export class CapturingEmailProvider implements EmailProvider {
  private readonly codesByEmail = new Map<string, string>();

  async sendVerificationEmail(email: string, code: string): Promise<void> {
    this.codesByEmail.set(email, code);
  }

  getLastCode(email: string): string {
    const code = this.codesByEmail.get(email);
    if (!code) throw new Error(`No verification code captured for email ${email}`);
    return code;
  }
}
