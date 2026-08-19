import { ParsedSalary } from './types';

// Parse text lương tiếng Việt phổ biến trên các trang tuyển dụng thành số thật.
// Không nhận diện được số nào => trả về null (không bịa mức lương).
export function parseSalaryText(text: string | undefined | null): ParsedSalary | null {
  if (!text) return null;
  const normalized = text.toLowerCase().trim();
  if (!normalized || /thoả thuận|thỏa thuận|negotiable/.test(normalized)) return null;

  const numbers = extractNumbers(normalized);
  if (numbers.length === 0) return null;

  // Nhân theo đơn vị chung của cả cụm (vd "8-12 triệu" => cả 8 và 12 đều là triệu, không phải
  // chỉ số đứng ngay trước chữ "triệu") - phổ biến hơn nhiều so với mỗi số có suffix riêng.
  const multiplier = detectMultiplier(normalized);
  const scaled = numbers.map((n) => Math.round(n * multiplier));

  const unit = detectUnit(normalized);
  const min = Math.min(...scaled);
  const max = Math.max(...scaled);

  return { min, max, unit };
}

// "8-12 triệu", "8 - 12tr", "50k", "8tr đến 12tr" -> tách các số thô, chưa nhân đơn vị.
function extractNumbers(text: string): number[] {
  const results: number[] = [];
  const pattern = /\d+(?:[.,]\d+)?/g;
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(text)) !== null) {
    const value = Number(match[0].replace(',', '.'));
    if (!Number.isNaN(value) && value > 0) results.push(value);
  }
  return results;
}

function detectMultiplier(text: string): number {
  if (/triệu|tr\b/.test(text)) return 1_000_000;
  // "k" thường đứng dính liền sau số (vd "50k") nên không có word boundary giữa số và "k" -
  // chỉ cần "k" không phải 1 phần của chữ khác (không có chữ cái ngay sau).
  if (/nghìn|ngàn|\dk(?![a-z])/.test(text)) return 1_000;
  return 1;
}

function detectUnit(text: string): ParsedSalary['unit'] {
  if (/\/\s*(giờ|gio)|hourly/.test(text)) return 'HOUR';
  if (/\/\s*(ngày|ngay)|daily/.test(text)) return 'DAY';
  if (/\/\s*ca|per shift/.test(text)) return 'SHIFT';
  if (/\/\s*(tháng|thang)|monthly/.test(text)) return 'MONTH';
  return null;
}
