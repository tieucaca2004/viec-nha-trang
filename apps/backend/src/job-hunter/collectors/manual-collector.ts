import { Collector } from '../interfaces/collector.interface';
import { RawJob } from '../interfaces/raw-job.interface';

// Collector "thủ công" - nhận sẵn 1 danh sách RawJob (vd admin dán tay từ 1 nguồn MANUAL/UNSUPPORTED
// - đặc tả Phần 6: nguồn không cho phép thu thập tự động thì đánh dấu MANUAL, không cố bypass).
// Đây là implementation DUY NHẤT của Collector trong batch này - dùng để test toàn bộ pipeline
// (Extractor -> ... -> Publisher) mà không cần crawler thật.
export class ManualCollector implements Collector {
  constructor(
    public readonly sourceName: string,
    private readonly jobs: RawJob[],
  ) {}

  async collect(): Promise<RawJob[]> {
    return this.jobs;
  }
}
