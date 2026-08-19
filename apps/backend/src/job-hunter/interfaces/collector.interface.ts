import { RawJob } from './raw-job.interface';

// Collector là điểm mở rộng DUY NHẤT để thêm nguồn dữ liệu thật sau này (website/API/RSS/partner).
// Batch này CHỈ xây interface + 1 implementation thủ công (ManualCollector) để có foundation
// test được - KHÔNG có Facebook collector thật, KHÔNG bypass login/CAPTCHA/access control nào.
export interface Collector {
  readonly sourceName: string;
  collect(): Promise<RawJob[]>;
}
