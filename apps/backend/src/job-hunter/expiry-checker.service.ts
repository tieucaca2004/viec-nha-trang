import { Injectable } from '@nestjs/common';

const DEFAULT_STALE_DAYS = 45;

export interface ExpiryCheckInput {
  expiresAt: Date | null;
  sourcePublishedAt: Date | null;
  sourceUpdatedAt: Date | null;
  importedAt: Date | null;
}

// ExpiryChecker: quyết định 1 Job (đặc biệt là IMPORTED - không có luồng renew() chủ động như
// USER_CREATED) có nên coi là hết hạn không, dựa trên expiresAt tường minh (nếu có) hoặc mốc
// cập nhật gần nhất đã biết (KHÔNG suy đoán ngày đăng nếu cả 3 mốc đều null).
@Injectable()
export class ExpiryCheckerService {
  isExpired(job: ExpiryCheckInput, now: Date = new Date(), staleDays: number = DEFAULT_STALE_DAYS): boolean {
    if (job.expiresAt) {
      return now.getTime() > job.expiresAt.getTime();
    }

    const lastKnownActivity = mostRecent(job.sourceUpdatedAt, job.sourcePublishedAt, job.importedAt);
    if (!lastKnownActivity) return false; // không đủ thông tin - không tự ý coi là hết hạn.

    const staleThresholdMs = staleDays * 24 * 60 * 60 * 1000;
    return now.getTime() - lastKnownActivity.getTime() > staleThresholdMs;
  }
}

function mostRecent(...dates: (Date | null)[]): Date | null {
  const valid = dates.filter((d): d is Date => d !== null);
  if (valid.length === 0) return null;
  return new Date(Math.max(...valid.map((d) => d.getTime())));
}
