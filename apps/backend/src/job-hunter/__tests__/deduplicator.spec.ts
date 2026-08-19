import { DeduplicatorService } from '../deduplicator.service';
import { NormalizedJob } from '../types';

function job(overrides: Partial<NormalizedJob>): NormalizedJob {
  return {
    sourceName: 'careerviet',
    title: 'Nhân viên phục vụ nhà hàng',
    location: { citySlug: 'nha-trang', areaSlug: 'loc-tho', raw: 'Lộc Thọ, Nha Trang' },
    salary: { min: 6_000_000, max: 8_000_000, unit: 'MONTH' },
    sourcePublishedAt: null,
    sourceUpdatedAt: null,
    ...overrides,
  };
}

describe('DeduplicatorService (đặc tả Phần 8)', () => {
  let service: DeduplicatorService;
  beforeEach(() => (service = new DeduplicatorService()));

  it('cùng sourceName + sourceJobId => trùng', () => {
    const a = job({ sourceJobId: 'abc-123' });
    const b = job({ sourceJobId: 'abc-123', title: 'Nhân viên phục vụ (đã cập nhật)' });
    expect(service.areDuplicates(a, b)).toBe(true);
  });

  it('cùng canonical URL (khác query string) => trùng', () => {
    const a = job({ sourceUrl: 'https://careerviet.vn/jobs/abc?utm=fb' });
    const b = job({ sourceUrl: 'https://careerviet.vn/jobs/abc/' });
    expect(service.areDuplicates(a, b)).toBe(true);
  });

  it('title/employer/location/salary tương tự nhau từ 2 nguồn khác nhau => trùng', () => {
    const a = job({ sourceName: 'careerviet', companyName: 'Nhà hàng Biển Xanh' });
    const b = job({ sourceName: 'topcv', companyName: 'Nhà hàng Biển Xanh' });
    expect(service.areDuplicates(a, b)).toBe(true);
  });

  it('job hoàn toàn khác nhau (title/location/salary) => không trùng', () => {
    const a = job({ title: 'Nhân viên phục vụ nhà hàng' });
    const b = job({
      title: 'Kỹ sư điện công nghiệp',
      location: { citySlug: 'khanh-hoa', areaSlug: null, raw: 'Cam Ranh' },
      salary: { min: 15_000_000, max: 20_000_000, unit: 'MONTH' },
    });
    expect(service.areDuplicates(a, b)).toBe(false);
  });

  it('group() gom đúng các job trùng vào 1 canonical, giữ các job khác nhau riêng lẻ', () => {
    const jobs: NormalizedJob[] = [
      job({ sourceName: 'careerviet', sourceJobId: '1', title: 'Phục vụ nhà hàng' }),
      job({ sourceName: 'topcv', sourceJobId: '2', title: 'Phục vụ nhà hàng', companyName: undefined }),
      job({
        sourceName: 'careerviet',
        sourceJobId: '3',
        title: 'Kỹ sư điện',
        location: { citySlug: 'khanh-hoa', areaSlug: null, raw: 'Cam Ranh' },
        salary: { min: 15_000_000, max: 20_000_000, unit: 'MONTH' },
      }),
    ];

    const groups = service.group(jobs);
    expect(groups).toHaveLength(2);
    const restaurantGroup = groups.find((g) => g.canonical.title === 'Phục vụ nhà hàng');
    expect(restaurantGroup?.duplicates).toHaveLength(1);
  });
});
