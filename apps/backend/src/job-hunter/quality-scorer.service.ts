import { Injectable } from '@nestjs/common';
import { NormalizedJob, ScoredJob } from './types';

// QualityScorer: chấm điểm 0-100 dựa trên độ đầy đủ/hợp lệ của dữ liệu - dùng để quyết định
// job imported nào đủ chất lượng publish thẳng (ACTIVE) hay cần PENDING_REVIEW (điểm thấp).
@Injectable()
export class QualityScorerService {
  score(job: NormalizedJob): ScoredJob {
    let score = 0;

    if (job.title && job.title.length >= 8) score += 20;
    if (job.description && job.description.length >= 40) score += 20;
    if (job.companyName) score += 15;
    if (job.location?.areaSlug || job.location?.citySlug) score += 20;
    if (job.salary) score += 15;
    if (job.sourceUrl) score += 5;
    if (job.sourcePublishedAt) score += 5;

    return { ...job, qualityScore: Math.min(score, 100) };
  }

  scoreMany(jobs: NormalizedJob[]): ScoredJob[] {
    return jobs.map((j) => this.score(j));
  }

  // Ngưỡng publish thẳng ACTIVE - dưới ngưỡng này phải vào PENDING_REVIEW cho admin duyệt tay.
  meetsPublishThreshold(job: ScoredJob): boolean {
    return job.qualityScore >= 60;
  }
}
