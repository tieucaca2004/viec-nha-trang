import { Injectable } from '@nestjs/common';
import { RawJob } from './interfaces/raw-job.interface';
import { ExtractedJob } from './types';

// Extractor: kiểm tra RawJob có đủ thông tin tối thiểu để xử lý tiếp không (title + sourceName
// bắt buộc - không có 2 trường này thì không thể tạo Job hợp lệ), và trim/chuẩn hoá whitespace.
// KHÔNG parse ngày/lương/địa điểm ở đây - đó là việc của NormalizerService.
@Injectable()
export class ExtractorService {
  extract(raw: RawJob): ExtractedJob | null {
    const title = raw.title?.trim();
    const sourceName = raw.sourceName?.trim();
    if (!title || !sourceName) return null;

    return {
      sourceName,
      sourceJobId: raw.sourceJobId?.trim() || undefined,
      sourceUrl: raw.sourceUrl?.trim() || undefined,
      title,
      description: this.cleanText(raw.description),
      companyName: this.cleanText(raw.companyName),
      locationText: this.cleanText(raw.locationText),
      salaryText: this.cleanText(raw.salaryText),
      publishedText: this.cleanText(raw.publishedText),
      updatedText: this.cleanText(raw.updatedText),
    };
  }

  extractMany(raws: RawJob[]): ExtractedJob[] {
    return raws.map((r) => this.extract(r)).filter((j): j is ExtractedJob => j !== null);
  }

  private cleanText(value?: string): string | undefined {
    if (!value) return undefined;
    const trimmed = value.replace(/\s+/g, ' ').trim();
    return trimmed.length > 0 ? trimmed : undefined;
  }
}
