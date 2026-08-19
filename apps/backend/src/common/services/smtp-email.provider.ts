import { Injectable, Logger, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createTransport, Transporter } from 'nodemailer';
import { EmailProvider } from '../interfaces/email-provider.interface';

/// Gửi email xác minh thật qua SMTP chuẩn (không khoá cứng vào 1 nhà cung cấp trả phí cụ thể -
/// vận hành tự chọn SMTP relay, có thể là SMTP miễn phí tự host, Gmail App Password cho dev/thử
/// nghiệm, hoặc dịch vụ trả phí nếu tự quyết định cấu hình - project không tự ý chọn hộ).
/// Cấu hình qua SMTP_HOST/SMTP_PORT/SMTP_SECURE/SMTP_USER/SMTP_PASS/SMTP_FROM (xem .env.example).
///
/// KHÔNG bao giờ log SMTP_PASS hay mã xác minh - chỉ log email người nhận và lỗi gửi (nếu có),
/// giống nguyên tắc của EsmsProvider (không log ApiKey/SecretKey/OTP).
@Injectable()
export class SmtpEmailProvider implements EmailProvider {
  private readonly logger = new Logger(SmtpEmailProvider.name);
  private transporter: Transporter | null = null;

  constructor(private readonly config: ConfigService) {}

  private getTransporter(): Transporter {
    if (this.transporter) return this.transporter;
    const host = this.config.get<string>('SMTP_HOST');
    const port = Number(this.config.get<string>('SMTP_PORT') ?? 587);
    const secure = this.config.get<string>('SMTP_SECURE') === 'true';
    const user = this.config.get<string>('SMTP_USER');
    const pass = this.config.get<string>('SMTP_PASS');

    if (!host || !user || !pass) {
      throw new Error(
        'EMAIL_PROVIDER=smtp nhưng thiếu SMTP_HOST/SMTP_USER/SMTP_PASS trong .env - điền đủ 3 biến này (và SMTP_PORT/SMTP_SECURE/SMTP_FROM nếu cần) trước khi khởi động app.',
      );
    }

    this.transporter = createTransport({ host, port, secure, auth: { user, pass } });
    return this.transporter;
  }

  async sendVerificationEmail(email: string, code: string): Promise<void> {
    const from = this.config.get<string>('SMTP_FROM') ?? 'no-reply@viecnhatrang.local';
    try {
      await this.getTransporter().sendMail({
        from,
        to: email,
        subject: 'Mã xác minh tài khoản VIỆC NHA TRANG',
        text: `Mã xác minh của bạn là: ${code}. Mã có hiệu lực trong thời gian ngắn, không chia sẻ mã này cho bất kỳ ai.`,
      });
    } catch (error) {
      this.logger.error(`SMTP: gửi email xác minh tới ${email} thất bại: ${error instanceof Error ? error.message : String(error)}`);
      throw new ServiceUnavailableException('Không thể gửi email xác minh lúc này, vui lòng thử lại.');
    }
  }
}
