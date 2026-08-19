// Đầu ra thô của Collector - CHƯA parse/normalize. Mỗi RawJob PHẢI giữ đủ thông tin để không bao
// giờ mất nguồn gốc (đặc tả Phần 4: "Không được mất URL nguồn").
export interface RawJob {
  sourceName: string;
  sourceJobId?: string;
  sourceUrl?: string;
  title: string;
  description?: string;
  companyName?: string;
  /** Vị trí dạng text thô từ nguồn, vd "Nha Trang, Khánh Hòa" - Normalizer sẽ cố khớp vào City/Area thật. */
  locationText?: string;
  /** Mức lương dạng text thô, vd "8-12 triệu/tháng" - Normalizer cố parse ra số. */
  salaryText?: string;
  /** Text ngày đăng thô từ nguồn, vd "Đăng hôm nay", "3 ngày trước" - KHÔNG tự bịa nếu thiếu. */
  publishedText?: string;
  /** Text ngày cập nhật thô từ nguồn, vd "Cập nhật 05/08/2026". */
  updatedText?: string;
  /** Payload gốc đầy đủ (nếu có) để debug/audit sau này - không bắt buộc dùng ngay. */
  raw?: Record<string, unknown>;
}
