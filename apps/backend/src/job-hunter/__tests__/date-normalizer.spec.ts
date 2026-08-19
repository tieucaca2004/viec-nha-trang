import { parseVietnameseDateText } from '../date-normalizer';

describe('parseVietnameseDateText (đặc tả Phần 7 - date handling)', () => {
  const reference = new Date('2026-08-19T00:00:00.000Z');

  it('"Đăng hôm nay" -> ngày hiện tại', () => {
    expect(parseVietnameseDateText('Đăng hôm nay', reference)?.toISOString()).toBe(reference.toISOString());
  });

  it('"hôm qua" -> hôm nay trừ 1 ngày', () => {
    const result = parseVietnameseDateText('hôm qua', reference);
    expect(result?.toISOString().slice(0, 10)).toBe('2026-08-18');
  });

  it('"3 ngày trước" -> trừ đúng 3 ngày', () => {
    const result = parseVietnameseDateText('Đăng 3 ngày trước', reference);
    expect(result?.toISOString().slice(0, 10)).toBe('2026-08-16');
  });

  it('"2 tuần trước" -> trừ đúng 14 ngày', () => {
    const result = parseVietnameseDateText('2 tuần trước', reference);
    expect(result?.toISOString().slice(0, 10)).toBe('2026-08-05');
  });

  it('"1 tháng trước" -> trừ đúng 1 tháng', () => {
    const result = parseVietnameseDateText('1 tháng trước', reference);
    expect(result?.toISOString().slice(0, 10)).toBe('2026-07-19');
  });

  it('"Cập nhật 05/08/2026" -> parse đúng ngày DD/MM/YYYY', () => {
    const result = parseVietnameseDateText('Cập nhật 05/08/2026', reference);
    expect(result?.toISOString().slice(0, 10)).toBe('2026-08-05');
  });

  it('"2026-08-05" (ISO) -> parse đúng', () => {
    const result = parseVietnameseDateText('2026-08-05', reference);
    expect(result?.toISOString().slice(0, 10)).toBe('2026-08-05');
  });

  it('ngày không hợp lệ (32/13/2026) -> null, KHÔNG bịa ra ngày gần đúng', () => {
    expect(parseVietnameseDateText('32/13/2026', reference)).toBeNull();
  });

  it('text không nhận diện được -> null (không bịa ngày)', () => {
    expect(parseVietnameseDateText('sắp hết hạn', reference)).toBeNull();
  });

  it('undefined/rỗng -> null', () => {
    expect(parseVietnameseDateText(undefined, reference)).toBeNull();
    expect(parseVietnameseDateText('', reference)).toBeNull();
  });
});
