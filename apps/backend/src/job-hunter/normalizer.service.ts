import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { ExtractedJob, NormalizedJob, ResolvedLocation } from './types';
import { parseVietnameseDateText } from './date-normalizer';
import { parseSalaryText } from './salary-normalizer';

// Normalizer: chuẩn hoá ExtractedJob (text thô) thành NormalizedJob (dữ liệu có cấu trúc) -
// parse ngày (đặc tả Phần 7), lương, và cố khớp locationText vào City/Area thật đã có trong DB.
// Không khớp được location nào => location = { citySlug: null, areaSlug: null, raw: text gốc },
// KHÔNG tự gán bừa một khu vực.
@Injectable()
export class NormalizerService {
  constructor(private readonly prisma: PrismaService) {}

  async normalize(job: ExtractedJob, referenceDate: Date = new Date()): Promise<NormalizedJob> {
    return {
      sourceName: job.sourceName,
      sourceJobId: job.sourceJobId,
      sourceUrl: job.sourceUrl,
      title: job.title,
      description: job.description,
      companyName: job.companyName,
      location: await this.resolveLocation(job.locationText),
      salary: parseSalaryText(job.salaryText),
      sourcePublishedAt: parseVietnameseDateText(job.publishedText, referenceDate),
      sourceUpdatedAt: parseVietnameseDateText(job.updatedText, referenceDate),
    };
  }

  async normalizeMany(jobs: ExtractedJob[], referenceDate: Date = new Date()): Promise<NormalizedJob[]> {
    return Promise.all(jobs.map((j) => this.normalize(j, referenceDate)));
  }

  private async resolveLocation(locationText?: string): Promise<ResolvedLocation | null> {
    if (!locationText) return null;

    // Ưu tiên khớp Area trước (cụ thể hơn) - Area.name thường là tên phường/xã ngắn, dễ trùng
    // trong 1 câu địa chỉ dài hơn Ordinarily City. Dùng contains không phân biệt hoa thường.
    const areas = await this.prisma.area.findMany({ where: { isActive: true }, include: { city: true } });
    for (const area of areas) {
      if (containsToken(locationText, area.name)) {
        return { citySlug: area.city.slug, areaSlug: area.slug, raw: locationText };
      }
    }

    const cities = await this.prisma.city.findMany({ where: { isActive: true } });
    for (const city of cities) {
      if (containsToken(locationText, city.name)) {
        return { citySlug: city.slug, areaSlug: null, raw: locationText };
      }
    }

    return { citySlug: null, areaSlug: null, raw: locationText };
  }
}

function containsToken(haystack: string, needle: string): boolean {
  return haystack.toLowerCase().normalize('NFC').includes(needle.toLowerCase().normalize('NFC'));
}
