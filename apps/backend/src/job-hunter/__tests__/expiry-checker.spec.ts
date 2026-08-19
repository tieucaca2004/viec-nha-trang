import { ExpiryCheckerService } from '../expiry-checker.service';

describe('ExpiryCheckerService', () => {
  const service = new ExpiryCheckerService();
  const now = new Date('2026-08-19T00:00:00.000Z');

  it('có expiresAt trong quá khứ => hết hạn', () => {
    const result = service.isExpired(
      { expiresAt: new Date('2026-08-01T00:00:00.000Z'), sourcePublishedAt: null, sourceUpdatedAt: null, importedAt: null },
      now,
    );
    expect(result).toBe(true);
  });

  it('có expiresAt trong tương lai => chưa hết hạn', () => {
    const result = service.isExpired(
      { expiresAt: new Date('2026-09-01T00:00:00.000Z'), sourcePublishedAt: null, sourceUpdatedAt: null, importedAt: null },
      now,
    );
    expect(result).toBe(false);
  });

  it('không có expiresAt, mốc cập nhật gần nhất quá 45 ngày => hết hạn (stale)', () => {
    const result = service.isExpired(
      {
        expiresAt: null,
        sourcePublishedAt: new Date('2026-06-01T00:00:00.000Z'),
        sourceUpdatedAt: null,
        importedAt: new Date('2026-06-01T00:00:00.000Z'),
      },
      now,
    );
    expect(result).toBe(true);
  });

  it('không có expiresAt, cập nhật gần đây (< 45 ngày) => chưa hết hạn', () => {
    const result = service.isExpired(
      { expiresAt: null, sourcePublishedAt: null, sourceUpdatedAt: new Date('2026-08-10T00:00:00.000Z'), importedAt: null },
      now,
    );
    expect(result).toBe(false);
  });

  it('không có bất kỳ mốc thời gian nào => KHÔNG tự ý coi là hết hạn (không đủ thông tin)', () => {
    const result = service.isExpired({ expiresAt: null, sourcePublishedAt: null, sourceUpdatedAt: null, importedAt: null }, now);
    expect(result).toBe(false);
  });
});
