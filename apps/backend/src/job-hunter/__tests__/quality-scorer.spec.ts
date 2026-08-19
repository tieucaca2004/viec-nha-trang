import { QualityScorerService } from '../quality-scorer.service';
import { NormalizedJob } from '../types';

const FULL_JOB: NormalizedJob = {
  sourceName: 'careerviet',
  title: 'Nhân viên phục vụ nhà hàng',
  description: 'Mô tả công việc đầy đủ chi tiết cho vị trí phục vụ nhà hàng ven biển Nha Trang.',
  companyName: 'Nhà hàng Biển Xanh',
  location: { citySlug: 'nha-trang', areaSlug: 'loc-tho', raw: 'Lộc Thọ' },
  salary: { min: 6_000_000, max: 8_000_000, unit: 'MONTH' },
  sourceUrl: 'https://careerviet.vn/jobs/abc',
  sourcePublishedAt: new Date(),
  sourceUpdatedAt: null,
};

describe('QualityScorerService', () => {
  const scorer = new QualityScorerService();

  it('job đầy đủ thông tin => điểm cao, đạt ngưỡng publish', () => {
    const scored = scorer.score(FULL_JOB);
    expect(scored.qualityScore).toBeGreaterThanOrEqual(80);
    expect(scorer.meetsPublishThreshold(scored)).toBe(true);
  });

  it('job thiếu hầu hết thông tin => điểm thấp, không đạt ngưỡng publish', () => {
    const sparse: NormalizedJob = {
      sourceName: 'facebook-group-x',
      title: 'Tuyển gấp',
      location: null,
      salary: null,
      sourcePublishedAt: null,
      sourceUpdatedAt: null,
    };
    const scored = scorer.score(sparse);
    expect(scored.qualityScore).toBeLessThan(60);
    expect(scorer.meetsPublishThreshold(scored)).toBe(false);
  });
});
