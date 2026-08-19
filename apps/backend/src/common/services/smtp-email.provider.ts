import { Injectable, Logger, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createTransport, Transporter } from 'nodemailer';
import { EmailProvider } from '../interfaces/email-provider.interface';

export interface SmtpConfig {
  host: string;
  port: number;
  secure: boolean;
  user: string;
  pass: string;
  from: string;
}

/// Đọc + validate đủ 5 biến bắt buộc (SMTP_HOST/PORT/USER/PASS/FROM) khi EMAIL_PROVIDER=smtp -
/// dùng chung bởi email-provider.factory.ts (fail fast NGAY LÚC KHỞI ĐỘNG APP, cùng nguyên tắc
/// với selectSmsProvider) và SmtpEmailProvider (validate lại phòng khi provider được khởi tạo
/// trực tiếp ngoài factory, ví dụ trong test). Liệt kê ĐẦY ĐỦ các biến còn thiếu trong 1 thông
/// báo lỗi duy nhất, không dừng ở biến đầu tiên tìm thấy - dễ sửa .env một lần thay vì thử lại
/// nhiều lượt.
export function readSmtpConfig(config: ConfigService): SmtpConfig {
  const host = config.get<string>('SMTP_HOST');
  const portRaw = config.get<string>('SMTP_PORT');
  const user = config.get<string>('SMTP_USER');
  const pass = config.get<string>('SMTP_PASS');
  const from = config.get<string>('SMTP_FROM');

  const missing: string[] = [];
  if (!host) missing.push('SMTP_HOST');
  if (!portRaw) missing.push('SMTP_PORT');
  if (!user) missing.push('SMTP_USER');
  if (!pass) missing.push('SMTP_PASS');
  if (!from) missing.push('SMTP_FROM');

  const port = Number(portRaw);
  if (portRaw && (!Number.isInteger(port) || port <= 0)) {
    missing.push('SMTP_PORT (giá trị hiện tại không phải số nguyên dương hợp lệ)');
  }

  if (missing.length > 0) {
    throw new Error(
      `EMAIL_PROVIDER=smtp nhưng thiếu/sai cấu hình: ${missing.join(', ')}. Điền đủ các biến này trong .env/.env.staging trước khi khởi động app (xem .env.example).`,
    );
  }

  return {
    host: host!,
    port,
    secure: config.get<string>('SMTP_SECURE') === 'true',
    user: user!,
    pass: pass!,
    from: from!,
  };
}

/// Gửi email xác minh thật qua SMTP chuẩn (không khoá cứng vào 1 nhà cung cấp trả phí cụ thể -
/// vận hành tự chọn SMTP relay, có thể là SMTP miễn phí tự host, Gmail App Password cho dev/thử
/// nghiệm, hoặc dịch vụ trả phí nếu tự quyết định cấu hình - project không tự ý chọn hộ).
/// Cấu hình qua SMTP_HOST/SMTP_PORT/SMTP_SECURE/SMTP_USER/SMTP_PASS/SMTP_FROM (xem .env.example).
/// Thiếu bất kỳ biến bắt buộc nào (trừ SMTP_SECURE, có default false) sẽ throw ngay - xem
/// readSmtpConfig() ở trên, được gọi cả ở email-provider.factory.ts (fail fast lúc khởi động).
///
/// KHÔNG bao giờ log SMTP_PASS hay mã xác minh - chỉ log email người nhận và LOẠI lỗi gửi (nếu
/// có), giống nguyên tắc của EsmsProvider (không log ApiKey/SecretKey/OTP). Không throw raw lỗi
/// SMTP (có thể lộ chi tiết cấu hình nội bộ) ra API - luôn map về 1 thông báo chung, an toàn.
@Injectable()
export class SmtpEmailProvider implements EmailProvider {
  private readonly logger = new Logger(SmtpEmailProvider.name);
  private transporter: Transporter | null = null;

  constructor(private readonly config: ConfigService) {}

  private getTransporter(): Transporter {
    if (this.transporter) return this.transporter;
    const { host, port, secure, user, pass } = readSmtpConfig(this.config);
    this.transporter = createTransport({ host, port, secure, auth: { user, pass } });
    return this.transporter;
  }

  async sendVerificationEmail(email: string, code: string): Promise<void> {
    const { from } = readSmtpConfig(this.config);
    try {
      await this.getTransporter().sendMail({
        from,
        to: email,
        subject: 'VIỆC NHA TRANG - Mã xác minh email',
        text: [
          'VIỆC NHA TRANG',
          '',
          `Mã xác minh email của bạn: ${code}`,
          '',
          'Mã có hiệu lực trong thời gian ngắn. Không chia sẻ mã này cho bất kỳ ai, kể cả nhân viên VIỆC NHA TRANG.',
          'Nếu bạn không yêu cầu mã này, vui lòng bỏ qua email.',
        ].join('\n'),
        html: [
          '<div style="font-family:sans-serif;font-size:15px;color:#111;">',
          '<p style="font-weight:bold;font-size:18px;margin-bottom:16px;">VIỆC NHA TRANG</p>',
          '<p>Mã xác minh email của bạn:</p>',
          `<p style="font-size:28px;font-weight:bold;letter-spacing:4px;margin:12px 0;">${code}</p>`,
          '<p style="color:#555;">Mã có hiệu lực trong thời gian ngắn. Không chia sẻ mã này cho bất kỳ ai, kể cả nhân viên VIỆC NHA TRANG.</p>',
          '<p style="color:#555;">Nếu bạn không yêu cầu mã này, vui lòng bỏ qua email.</p>',
          '</div>',
        ].join(''),
      });
    } catch (error) {
      // Chỉ log LOẠI lỗi (message của nodemailer, ví dụ "Invalid login"/"ECONNREFUSED"/timeout) -
      // không log SMTP_PASS/host thật đầy đủ hay mã xác minh.
      const reason = error instanceof Error ? error.message : String(error);
      this.logger.error(`SMTP: gửi email xác minh tới ${email} thất bại - ${reason}`);
      throw new ServiceUnavailableException('Không thể gửi email xác minh lúc này, vui lòng thử lại.');
    }
  }
}
