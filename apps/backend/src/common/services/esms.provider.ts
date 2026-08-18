import { Injectable, Logger, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { SmsProvider } from '../interfaces/sms-provider.interface';

/// Gửi OTP thật qua eSMS.vn (SendMultipleMessage_V4_get - hàm SMS OTP/CSKH, xem
/// https://developers.esms.vn/esms-api/ham-gui-tin/tin-nhan-sms-otp-cskh và
/// https://esms.vn/SMSApi/ApiDetail). SmsType=2 = loại tin OTP/CSKH gửi ngay từng tin một
/// (khuyến nghị cho OTP, khác với SmsType=1 dùng cho gửi hàng loạt/CSKH thường).
///
/// KHÔNG bao giờ log ApiKey/SecretKey/mã OTP - chỉ log số điện thoại (đã có ở log khác của
/// project) và mã lỗi/trạng thái trả về từ eSMS khi có sự cố, phục vụ debug production an toàn.
const ESMS_ENDPOINT = 'https://rest.esms.vn/MainService.svc/json/SendMultipleMessage_V4_get';
const ESMS_TIMEOUT_MS = 10_000;
const ESMS_SMS_TYPE = '2';

// Mã lỗi xác nhận từ tài liệu eSMS (https://developers.esms.vn/esms-api/bang-ma-loi) - chỉ liệt
// kê những mã có khả năng gặp thật khi vận hành, phần còn lại rơi vào nhánh "mã lỗi khác".
const ESMS_ERROR_MESSAGES: Record<string, string> = {
  '99': 'Lỗi không xác định từ eSMS, thử lại sau.',
  '101': 'Đăng nhập eSMS thất bại - ApiKey hoặc SecretKey không đúng.',
  '102': 'Tài khoản eSMS đã bị khóa.',
  '103': 'Số dư tài khoản eSMS không đủ để gửi tin.',
  '104': 'Brandname eSMS không đúng hoặc chưa được duyệt.',
};

@Injectable()
export class EsmsProvider implements SmsProvider {
  private readonly logger = new Logger(EsmsProvider.name);

  constructor(private readonly config: ConfigService) {}

  async sendOtp(phone: string, code: string): Promise<void> {
    const apiKey = this.config.get<string>('ESMS_API_KEY');
    const secretKey = this.config.get<string>('ESMS_SECRET_KEY');
    const brandname = this.config.get<string>('ESMS_BRANDNAME');

    const params = new URLSearchParams({
      Phone: phone,
      Content: `Ma xac thuc VIEC NHA TRANG cua ban la: ${code}`,
      ApiKey: apiKey ?? '',
      SecretKey: secretKey ?? '',
      SmsType: ESMS_SMS_TYPE,
      IsUnicode: '0',
    });
    if (brandname) {
      params.set('Brandname', brandname);
    }

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), ESMS_TIMEOUT_MS);

    let response: Response;
    try {
      response = await fetch(`${ESMS_ENDPOINT}?${params.toString()}`, {
        method: 'GET',
        signal: controller.signal,
      });
    } catch (error) {
      if (error instanceof Error && error.name === 'AbortError') {
        this.logger.error(`eSMS: hết thời gian chờ (${ESMS_TIMEOUT_MS}ms) khi gửi OTP tới ${phone}.`);
        throw new ServiceUnavailableException('Không thể gửi mã OTP lúc này, vui lòng thử lại.');
      }
      this.logger.error(`eSMS: lỗi mạng khi gửi OTP tới ${phone}: ${error instanceof Error ? error.message : String(error)}`);
      throw new ServiceUnavailableException('Không thể gửi mã OTP lúc này, vui lòng thử lại.');
    } finally {
      clearTimeout(timeout);
    }

    if (!response.ok) {
      this.logger.error(`eSMS: API trả HTTP ${response.status} khi gửi OTP tới ${phone}.`);
      throw new ServiceUnavailableException('Không thể gửi mã OTP lúc này, vui lòng thử lại.');
    }

    let body: unknown;
    try {
      body = await response.json();
    } catch {
      this.logger.error(`eSMS: response không phải JSON hợp lệ khi gửi OTP tới ${phone}.`);
      throw new ServiceUnavailableException('Không thể gửi mã OTP lúc này, vui lòng thử lại.');
    }

    // eSMS trả field tên "CodeResult" (SendMultipleMessage_V4_get) - một số phiên bản/tài liệu
    // khác của eSMS dùng "CodeResponse" cho cùng ý nghĩa, nên kiểm tra cả hai cho chắc chắn.
    const codeResult = this.extractCode(body);
    if (codeResult === undefined) {
      this.logger.error(`eSMS: response thiếu CodeResult/CodeResponse khi gửi OTP tới ${phone}.`);
      throw new ServiceUnavailableException('Không thể gửi mã OTP lúc này, vui lòng thử lại.');
    }

    if (codeResult !== '100') {
      const reason = ESMS_ERROR_MESSAGES[codeResult] ?? `Mã lỗi eSMS không xác định: ${codeResult}`;
      this.logger.error(`eSMS: gửi OTP tới ${phone} thất bại (CodeResult=${codeResult}) - ${reason}`);
      throw new ServiceUnavailableException('Không thể gửi mã OTP lúc này, vui lòng thử lại.');
    }
  }

  private extractCode(body: unknown): string | undefined {
    if (typeof body !== 'object' || body === null) {
      return undefined;
    }
    const record = body as Record<string, unknown>;
    const raw = record.CodeResult ?? record.CodeResponse;
    return raw === undefined || raw === null ? undefined : String(raw);
  }
}
