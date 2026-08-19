import { parseSalaryText } from '../salary-normalizer';

describe('parseSalaryText', () => {
  it('"8-12 triệu/tháng" -> min/max nhân triệu, unit MONTH', () => {
    expect(parseSalaryText('8-12 triệu/tháng')).toEqual({ min: 8_000_000, max: 12_000_000, unit: 'MONTH' });
  });

  it('"50k/giờ" -> min=max=50000, unit HOUR', () => {
    expect(parseSalaryText('50k/giờ')).toEqual({ min: 50_000, max: 50_000, unit: 'HOUR' });
  });

  it('"300-350 nghìn/ca" -> unit SHIFT', () => {
    expect(parseSalaryText('300-350 nghìn/ca')).toEqual({ min: 300_000, max: 350_000, unit: 'SHIFT' });
  });

  it('"Thoả thuận" -> null (không bịa số)', () => {
    expect(parseSalaryText('Thoả thuận')).toBeNull();
  });

  it('rỗng/undefined -> null', () => {
    expect(parseSalaryText('')).toBeNull();
    expect(parseSalaryText(undefined)).toBeNull();
  });

  it('không có số nào -> null', () => {
    expect(parseSalaryText('lương hấp dẫn')).toBeNull();
  });
});
