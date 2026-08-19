// Các kiểu dữ liệu trung gian đi qua từng tầng của JobHunter pipeline:
// Collector -> RawJob -> Extractor -> ExtractedJob -> Normalizer -> NormalizedJob
// -> Deduplicator -> QualityScorer -> LocationFilter -> ExpiryChecker -> Publisher

export interface ExtractedJob {
  sourceName: string;
  sourceJobId?: string;
  sourceUrl?: string;
  title: string;
  description?: string;
  companyName?: string;
  locationText?: string;
  salaryText?: string;
  publishedText?: string;
  updatedText?: string;
}

export interface ParsedSalary {
  min: number;
  max: number;
  /** HOUR | DAY | MONTH | SHIFT - khớp SalaryUnit trong schema. Không xác định được thì null. */
  unit: 'HOUR' | 'DAY' | 'MONTH' | 'SHIFT' | null;
}

export interface ResolvedLocation {
  citySlug: string | null;
  areaSlug: string | null;
  /** Text gốc không khớp được vào City/Area nào đã biết - giữ lại để hiển thị/debug. */
  raw: string;
}

export interface NormalizedJob {
  sourceName: string;
  sourceJobId?: string;
  sourceUrl?: string;
  title: string;
  description?: string;
  companyName?: string;
  location: ResolvedLocation | null;
  salary: ParsedSalary | null;
  /** Ngày đăng THẬT đã parse từ nguồn - null nếu không xác định được (KHÔNG bịa). */
  sourcePublishedAt: Date | null;
  sourceUpdatedAt: Date | null;
}

export interface ScoredJob extends NormalizedJob {
  qualityScore: number; // 0-100
}

export interface DedupeGroup {
  canonical: NormalizedJob;
  duplicates: NormalizedJob[];
}
