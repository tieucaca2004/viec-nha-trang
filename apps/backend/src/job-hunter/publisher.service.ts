import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { ScoredJob } from './types';
import { QualityScorerService } from './quality-scorer.service';

// Publisher: bước cuối cùng của pipeline - ghi 1 ScoredJob (đã qua Extractor/Normalizer/
// Deduplicator/LocationFilter/QualityScorer) thành 1 row Job thật, giữ nguyên đầy đủ provenance
// (sourceType=IMPORTED, sourceName/sourceUrl/sourceJobId/sourcePublishedAt/sourceUpdatedAt/
// importedAt - KHÔNG BAO GIỜ mất sourceUrl).
//
// Job.employerId/employerLocationId là NOT NULL trong schema hiện tại (không đổi để tránh phá
// hợp đồng API/business logic đăng job của user thật) - vì vậy mỗi nguồn IMPORTED cần 1
// "employer đại diện nguồn" (KHÔNG PHẢI employer thật, không claim là 1 doanh nghiệp có thật -
// UI luôn phải hiển thị "Nguồn: <sourceName>" cho job IMPORTED, không hiển thị như tin của
// employer tự đăng - xem đặc tả Phần 11) để giữ đúng ràng buộc FK mà không giả mạo dữ liệu.
//
// LƯU Ý IDEMPOTENCY: upsert dùng unique (sourceName, sourceJobId). Nếu 1 nguồn không cung cấp
// sourceJobId ổn định, mỗi lần publish sẽ tạo Job MỚI thay vì cập nhật - khi có collector thật,
// PHẢI trích id/slug ổn định từ sourceUrl làm sourceJobId để giữ deterministic.
@Injectable()
export class PublisherService {
  private readonly logger = new Logger(PublisherService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly qualityScorer: QualityScorerService,
  ) {}

  async publish(job: ScoredJob, referenceDate: Date = new Date()) {
    if (!job.location?.citySlug) {
      throw new Error(`PublisherService.publish: job "${job.title}" thiếu vị trí đã resolve - phải qua LocationFilter trước.`);
    }

    const employer = await this.ensureSourcePlaceholderEmployer(job.sourceName);
    const location = await this.ensureSourcePlaceholderLocation(employer.id, job.location.citySlug, job.location.areaSlug);
    const category = await this.guessCategory(job.title, job.description);
    const status = this.qualityScorer.meetsPublishThreshold(job) ? 'ACTIVE' : 'PENDING_REVIEW';

    return this.prisma.job.upsert({
      where: { sourceName_sourceJobId: { sourceName: job.sourceName, sourceJobId: job.sourceJobId ?? '' } },
      update: {
        title: job.title,
        description: job.description,
        salaryMin: job.salary?.min ?? 0,
        salaryMax: job.salary?.max ?? job.salary?.min ?? 0,
        salaryUnit: job.salary?.unit ?? 'MONTH',
        sourceUrl: job.sourceUrl,
        sourceUpdatedAt: job.sourceUpdatedAt,
        importedAt: referenceDate,
      },
      create: {
        employerId: employer.id,
        employerLocationId: location.id,
        categoryId: category.id,
        cityId: location.cityId,
        areaId: location.areaId,
        latitude: location.latitude,
        longitude: location.longitude,
        title: job.title,
        description: job.description,
        employmentType: 'FULL_TIME',
        salaryMin: job.salary?.min ?? 0,
        salaryMax: job.salary?.max ?? job.salary?.min ?? 0,
        salaryUnit: job.salary?.unit ?? 'MONTH',
        status,
        publishedAt: job.sourcePublishedAt ?? referenceDate,
        sourceType: 'IMPORTED',
        sourceName: job.sourceName,
        sourceJobId: job.sourceJobId,
        sourceUrl: job.sourceUrl,
        sourcePublishedAt: job.sourcePublishedAt,
        sourceUpdatedAt: job.sourceUpdatedAt,
        importedAt: referenceDate,
      },
    });
  }

  async publishMany(jobs: ScoredJob[], referenceDate: Date = new Date()) {
    const results = [];
    for (const job of jobs) {
      try {
        results.push(await this.publish(job, referenceDate));
      } catch (error) {
        this.logger.warn(`Bỏ qua job "${job.title}" (${job.sourceName}): ${error instanceof Error ? error.message : String(error)}`);
      }
    }
    return results;
  }

  private async ensureSourcePlaceholderEmployer(sourceName: string) {
    const email = `imported+${sourceName.toLowerCase().replace(/[^a-z0-9]+/g, '-')}@viecnhatrang.internal`;
    const existingUser = await this.prisma.user.findUnique({ where: { email }, include: { employerProfile: true } });
    if (existingUser?.employerProfile) return existingUser.employerProfile;

    const user =
      existingUser ?? (await this.prisma.user.create({ data: { email, roles: ['EMPLOYER'], authProvider: 'EMAIL' } }));

    return this.prisma.employerProfile.create({
      data: {
        userId: user.id,
        businessName: `Nguồn: ${sourceName}`,
        description: `Tin tuyển dụng tổng hợp từ nguồn công khai "${sourceName}" - không phải tài khoản doanh nghiệp thật, chỉ đại diện provenance cho dữ liệu import.`,
      },
    });
  }

  private async ensureSourcePlaceholderLocation(employerId: string, citySlug: string, areaSlug: string | null) {
    const city = await this.prisma.city.findUniqueOrThrow({ where: { slug: citySlug } });
    const matchedArea = areaSlug ? await this.prisma.area.findFirst({ where: { cityId: city.id, slug: areaSlug } }) : null;
    // Không khớp được area cụ thể (chỉ biết city) -> dùng area đầu tiên của city làm xấp xỉ, ghi
    // rõ trong tên location là "ước lượng" để không giả vờ đây là vị trí chính xác.
    const area = matchedArea ?? (await this.prisma.area.findFirstOrThrow({ where: { cityId: city.id }, orderBy: { name: 'asc' } }));

    const existing = await this.prisma.employerLocation.findFirst({ where: { employerId, cityId: city.id, areaId: area.id } });
    if (existing) return existing;

    return this.prisma.employerLocation.create({
      data: {
        employerId,
        name: `Vị trí ước lượng (${area.name})`,
        address: `${area.name}, ${city.name}`,
        cityId: city.id,
        areaId: area.id,
        // Chưa có toạ độ thật từ nguồn imported - dùng tâm khu vực gần đúng nhất hiện có
        // (trung bình toạ độ các employer location đã biết trong area, hoặc 0/0 nếu chưa có).
        latitude: 0,
        longitude: 0,
      },
    });
  }

  private async guessCategory(title: string, description?: string) {
    const text = `${title} ${description ?? ''}`.toLowerCase();
    const categories = await this.prisma.jobCategory.findMany({ where: { isActive: true } });
    const match = categories.find((c) => text.includes(c.name.toLowerCase()));
    if (match) return match;

    const fallback = categories.find((c) => c.slug === 'khac') ?? categories[0];
    if (!fallback) throw new Error('Chưa có JobCategory nào trong DB - chạy seed trước.');
    return fallback;
  }
}
