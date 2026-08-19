import { Injectable } from '@nestjs/common';
import { NormalizedJob } from './types';

// LocationFilter: chỉ giữ lại job có vị trí thuộc phạm vi phục vụ của app (Nha Trang/Khánh Hòa).
// Job không xác định được vị trí, hoặc thuộc tỉnh/thành khác, bị loại khỏi luồng publish tự động
// (không đoán bừa vị trí để "cho đậu" filter).
const ALLOWED_CITY_SLUGS = new Set(['nha-trang', 'khanh-hoa']);

@Injectable()
export class LocationFilterService {
  isInScope(job: NormalizedJob): boolean {
    const citySlug = job.location?.citySlug;
    return citySlug != null && ALLOWED_CITY_SLUGS.has(citySlug);
  }

  filter(jobs: NormalizedJob[]): { inScope: NormalizedJob[]; outOfScope: NormalizedJob[] } {
    const inScope: NormalizedJob[] = [];
    const outOfScope: NormalizedJob[] = [];
    for (const job of jobs) {
      (this.isInScope(job) ? inScope : outOfScope).push(job);
    }
    return { inScope, outOfScope };
  }
}
