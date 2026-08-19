import { Module } from '@nestjs/common';
import { ExtractorService } from './extractor.service';
import { NormalizerService } from './normalizer.service';
import { DeduplicatorService } from './deduplicator.service';
import { QualityScorerService } from './quality-scorer.service';
import { LocationFilterService } from './location-filter.service';
import { ExpiryCheckerService } from './expiry-checker.service';
import { PublisherService } from './publisher.service';
import { JobHunterService } from './job-hunter.service';

@Module({
  providers: [
    ExtractorService,
    NormalizerService,
    DeduplicatorService,
    QualityScorerService,
    LocationFilterService,
    ExpiryCheckerService,
    PublisherService,
    JobHunterService,
  ],
  exports: [JobHunterService, ExpiryCheckerService],
})
export class JobHunterModule {}
