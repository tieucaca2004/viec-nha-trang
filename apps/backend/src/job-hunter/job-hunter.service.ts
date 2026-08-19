import { Injectable, Logger } from '@nestjs/common';
import { Collector } from './interfaces/collector.interface';
import { ExtractorService } from './extractor.service';
import { NormalizerService } from './normalizer.service';
import { DeduplicatorService } from './deduplicator.service';
import { QualityScorerService } from './quality-scorer.service';
import { LocationFilterService } from './location-filter.service';
import { PublisherService } from './publisher.service';

// Orchestrator toàn bộ pipeline (đặc tả Phần 4):
// Collector -> RawJob -> Extractor -> Normalizer -> Deduplicator -> QualityScorer
// -> LocationFilter -> Publisher
// (ExpiryChecker chạy riêng, định kỳ trên Job đã publish - không phải bước import 1 lần).
//
// Batch này CHƯA có cron/collector thật nào tự động gọi runOnce() - chỉ là foundation gọi được
// thủ công/qua test với ManualCollector. Không tự ý bật crawler thật.
@Injectable()
export class JobHunterService {
  private readonly logger = new Logger(JobHunterService.name);

  constructor(
    private readonly extractor: ExtractorService,
    private readonly normalizer: NormalizerService,
    private readonly deduplicator: DeduplicatorService,
    private readonly qualityScorer: QualityScorerService,
    private readonly locationFilter: LocationFilterService,
    private readonly publisher: PublisherService,
  ) {}

  async runOnce(collector: Collector, referenceDate: Date = new Date()) {
    const raw = await collector.collect();
    const extracted = this.extractor.extractMany(raw);
    const normalized = await this.normalizer.normalizeMany(extracted, referenceDate);

    const { inScope, outOfScope } = this.locationFilter.filter(normalized);
    if (outOfScope.length > 0) {
      this.logger.log(`${outOfScope.length} job ngoài phạm vi Nha Trang/Khánh Hòa từ nguồn "${collector.sourceName}" - bỏ qua.`);
    }

    const groups = this.deduplicator.group(inScope);
    const canonicalJobs = groups.map((g) => g.canonical);
    const scored = this.qualityScorer.scoreMany(canonicalJobs);

    const published = await this.publisher.publishMany(scored, referenceDate);

    return {
      collected: raw.length,
      extracted: extracted.length,
      inScope: inScope.length,
      outOfScope: outOfScope.length,
      duplicateGroups: groups.length,
      duplicatesFound: groups.reduce((sum, g) => sum + g.duplicates.length, 0),
      published: published.length,
    };
  }
}
