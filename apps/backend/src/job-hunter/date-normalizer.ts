// Chuẩn hoá text ngày tiếng Việt từ nguồn ngoài thành Date thật (đặc tả Phần 7).
// Tách thành hàm thuần (không phụ thuộc DI) để test dễ và dùng lại được ở nơi khác nếu cần.
//
// QUY TẮC BẮT BUỘC: không nhận diện được => trả về null. KHÔNG được tự bịa ngày đăng cho dữ liệu
// imported - một job không rõ ngày đăng phải hiển thị là "không rõ", không phải một ngày giả.
export function parseVietnameseDateText(text: string | undefined | null, referenceDate: Date): Date | null {
  if (!text) return null;
  const normalized = text.toLowerCase().trim();
  if (!normalized) return null;

  if (/hôm nay|today|vừa (đăng|xong)/.test(normalized)) {
    return new Date(referenceDate);
  }
  if (/hôm qua|yesterday/.test(normalized)) {
    return addDays(referenceDate, -1);
  }

  // "3 ngày trước", "2 tuần trước", "1 tháng trước"
  const relativeMatch = normalized.match(/(\d+)\s*(ngày|tuần|tháng)\s*trước/);
  if (relativeMatch) {
    const amount = Number(relativeMatch[1]);
    const unit = relativeMatch[2];
    if (unit === 'ngày') return addDays(referenceDate, -amount);
    if (unit === 'tuần') return addDays(referenceDate, -amount * 7);
    if (unit === 'tháng') return addMonths(referenceDate, -amount);
  }

  // "05/08/2026", "5-8-2026" (DD/MM/YYYY hoặc DD-MM-YYYY - định dạng phổ biến trên các trang VN)
  const dmyMatch = normalized.match(/(\d{1,2})[/-](\d{1,2})[/-](\d{4})/);
  if (dmyMatch) {
    const day = Number(dmyMatch[1]);
    const month = Number(dmyMatch[2]);
    const year = Number(dmyMatch[3]);
    const date = new Date(Date.UTC(year, month - 1, day));
    if (isValidDate(date) && date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day) {
      return date;
    }
    return null;
  }

  // "2026-08-05" (ISO)
  const isoMatch = normalized.match(/(\d{4})-(\d{1,2})-(\d{1,2})/);
  if (isoMatch) {
    const year = Number(isoMatch[1]);
    const month = Number(isoMatch[2]);
    const day = Number(isoMatch[3]);
    const date = new Date(Date.UTC(year, month - 1, day));
    if (isValidDate(date)) return date;
  }

  return null;
}

function addDays(date: Date, days: number): Date {
  const result = new Date(date);
  result.setUTCDate(result.getUTCDate() + days);
  return result;
}

function addMonths(date: Date, months: number): Date {
  const result = new Date(date);
  result.setUTCMonth(result.getUTCMonth() + months);
  return result;
}

function isValidDate(date: Date): boolean {
  return !Number.isNaN(date.getTime());
}
