import { LocationFilterService } from '../location-filter.service';
import { NormalizedJob } from '../types';

function job(citySlug: string | null): NormalizedJob {
  return {
    sourceName: 'careerviet',
    title: 'Test job',
    location: citySlug ? { citySlug, areaSlug: null, raw: citySlug } : null,
    salary: null,
    sourcePublishedAt: null,
    sourceUpdatedAt: null,
  };
}

describe('LocationFilterService', () => {
  const filterService = new LocationFilterService();

  it('citySlug nha-trang => trong phạm vi', () => {
    expect(filterService.isInScope(job('nha-trang'))).toBe(true);
  });

  it('citySlug khanh-hoa => trong phạm vi', () => {
    expect(filterService.isInScope(job('khanh-hoa'))).toBe(true);
  });

  it('citySlug ho-chi-minh (ngoài phạm vi) => bị loại', () => {
    expect(filterService.isInScope(job('ho-chi-minh'))).toBe(false);
  });

  it('không xác định được vị trí (location=null) => bị loại, không đoán bừa', () => {
    expect(filterService.isInScope(job(null))).toBe(false);
  });

  it('filter() tách đúng inScope/outOfScope', () => {
    const jobs = [job('nha-trang'), job('ho-chi-minh'), job('khanh-hoa'), job(null)];
    const { inScope, outOfScope } = filterService.filter(jobs);
    expect(inScope).toHaveLength(2);
    expect(outOfScope).toHaveLength(2);
  });
});
