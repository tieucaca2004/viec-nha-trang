import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CreateJobDto, UpdateJobDto } from './dto/create-job.dto';
import { JobSortBy, QueryJobsDto } from './dto/query-jobs.dto';

@Injectable()
export class JobsService {
  constructor(private readonly prisma: PrismaService) {}

  async create(userId: string, dto: CreateJobDto) {
    // Xác minh số điện thoại trước khi đăng tuyển (đặc tả §3) - cùng nguyên tắc với apply() ở
    // ApplicationsService: message 'PHONE_NOT_VERIFIED' cố định để frontend nhận diện.
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user?.isPhoneVerified) {
      throw new ForbiddenException('PHONE_NOT_VERIFIED');
    }

    const employer = await this.prisma.employerProfile.findUnique({ where: { userId } });
    if (!employer) throw new NotFoundException('Chưa có hồ sơ nhà tuyển dụng.');

    const location = await this.prisma.employerLocation.findUnique({ where: { id: dto.employerLocationId } });
    if (!location || location.employerId !== employer.id) {
      throw new ForbiddenException('Địa điểm không thuộc nhà tuyển dụng này.');
    }

    return this.prisma.job.create({
      data: {
        employerId: employer.id,
        employerLocationId: location.id,
        categoryId: dto.categoryId,
        cityId: location.cityId,
        areaId: location.areaId,
        latitude: location.latitude,
        longitude: location.longitude,
        title: dto.title,
        description: dto.description,
        requirements: dto.requirements,
        benefits: dto.benefits,
        headcount: dto.headcount,
        employmentType: dto.employmentType,
        shifts: dto.shifts,
        shiftStartTime: dto.shiftStartTime,
        shiftEndTime: dto.shiftEndTime,
        salaryMin: dto.salaryMin,
        salaryMax: dto.salaryMax,
        salaryUnit: dto.salaryUnit,
        startUrgency: dto.startUrgency,
        requiredExperience: dto.requiredExperience,
        isUrgent: dto.isUrgent ?? false,
        status: 'ACTIVE',
        publishedAt: new Date(),
        expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
      },
    });
  }

  async findMany(query: QueryJobsDto) {
    const limit = query.limit ?? 20;
    const offset = query.offset ?? 0;

    const where: Prisma.JobWhereInput = {
      status: 'ACTIVE',
      deletedAt: null,
      ...(query.categoryId ? { categoryId: query.categoryId } : {}),
      ...(query.areaId ? { areaId: query.areaId } : {}),
      ...(query.cityId ? { cityId: query.cityId } : {}),
      ...(query.employmentType ? { employmentType: query.employmentType } : {}),
      ...(query.shift ? { shifts: { has: query.shift } } : {}),
      ...(query.salaryUnit ? { salaryUnit: query.salaryUnit } : {}),
      ...(query.salaryMin != null ? { salaryMax: { gte: query.salaryMin } } : {}),
      ...(query.salaryMax != null ? { salaryMin: { lte: query.salaryMax } } : {}),
      ...(query.isUrgent ? { isUrgent: true } : {}),
      ...(query.startUrgency ? { startUrgency: query.startUrgency } : {}),
      ...(query.keyword
        ? {
            OR: [
              { title: { contains: query.keyword, mode: 'insensitive' } },
              { category: { name: { contains: query.keyword, mode: 'insensitive' } } },
              { employer: { businessName: { contains: query.keyword, mode: 'insensitive' } } },
            ],
          }
        : {}),
    };

    const hasCoords = query.latitude != null && query.longitude != null;

    // Sort theo khoảng cách cần haversine (không tính được trong SQL vì V1 không có PostGIS -
    // xem docs/SCALABILITY.md), và filter theo radiusKm làm thay đổi tổng số kết quả sau khi lọc
    // - cả hai trường hợp này bắt buộc phải lấy toàn bộ ứng viên rồi lọc/sắp xếp/phân trang trong
    // ứng dụng. Ngược lại (sort theo lương hoặc mới nhất, không lọc bán kính) có thể - và PHẢI -
    // sort + phân trang ngay ở DB để page 1 chứa đúng kết quả cao/thấp nhất, không phải sort sau
    // khi đã cắt trang (bug đã sửa - xem FULL AUDIT mục 6/High).
    const needsInMemorySortOrFilter =
      (hasCoords && query.radiusKm != null) || (hasCoords && (query.sortBy === JobSortBy.DISTANCE || !query.sortBy));

    if (!needsInMemorySortOrFilter) {
      const orderBy: Prisma.JobOrderByWithRelationInput =
        query.sortBy === JobSortBy.SALARY ? { salaryMax: 'desc' } : { publishedAt: 'desc' };

      const [candidates, total] = await Promise.all([
        this.prisma.job.findMany({
          where,
          include: { employer: true, category: true, area: true, employerLocation: true },
          orderBy,
          take: limit,
          skip: offset,
        }),
        this.prisma.job.count({ where }),
      ]);

      const data = candidates.map((job) => ({
        ...job,
        distanceKm: hasCoords ? this.haversineKm(query.latitude!, query.longitude!, job.latitude, job.longitude) : null,
      }));

      return { data, meta: { total, limit, offset } };
    }

    // Không PostGIS ở V1: lấy tập ứng viên rồi tính khoảng cách + sắp xếp trong ứng dụng.
    // Đủ dùng cho quy mô 1 thành phố; khi mở rộng đa thành phố sẽ thêm PostGIS/geo-index.
    const candidates = await this.prisma.job.findMany({
      where,
      include: { employer: true, category: true, area: true, employerLocation: true },
    });

    let results = candidates.map((job) => ({
      ...job,
      distanceKm: this.haversineKm(query.latitude!, query.longitude!, job.latitude, job.longitude),
    }));

    if (query.radiusKm) {
      results = results.filter((job) => (job.distanceKm ?? Infinity) <= query.radiusKm!);
    }

    if (query.sortBy === JobSortBy.SALARY) {
      results.sort((a, b) => b.salaryMax - a.salaryMax);
    } else {
      results.sort((a, b) => (a.distanceKm ?? Infinity) - (b.distanceKm ?? Infinity));
    }

    const total = results.length;
    results = results.slice(offset, offset + limit);

    return { data: results, meta: { total, limit, offset } };
  }

  // viewerId/viewerRoles đến từ OptionalJwtAuthGuard - undefined nếu người xem chưa đăng nhập.
  // Job không ACTIVE (DRAFT/CLOSED/EXPIRED/...) chỉ được xem bởi chính chủ hoặc ADMIN, không public.
  async findOne(id: string, viewerId?: string, viewerRoles?: string[]) {
    const job = await this.prisma.job.findUnique({
      where: { id },
      include: { employer: true, category: true, area: true, employerLocation: true },
    });
    if (!job || job.deletedAt) throw new NotFoundException('Không tìm thấy tin tuyển dụng.');

    const isOwner = viewerId != null && job.employer.userId === viewerId;
    const isAdmin = viewerRoles?.includes('ADMIN') ?? false;

    if (job.status !== 'ACTIVE' && !isOwner && !isAdmin) {
      throw new NotFoundException('Không tìm thấy tin tuyển dụng.');
    }

    if (!isOwner) {
      await this.prisma.job.update({ where: { id }, data: { viewCount: { increment: 1 } } });
      job.viewCount += 1;
    }

    return job;
  }

  async update(userId: string, jobId: string, dto: UpdateJobDto) {
    const job = await this.assertOwnership(userId, jobId);
    return this.prisma.job.update({ where: { id: job.id }, data: { ...dto } });
  }

  async close(userId: string, jobId: string) {
    const job = await this.assertOwnership(userId, jobId);
    return this.prisma.job.update({ where: { id: job.id }, data: { status: 'CLOSED' } });
  }

  async renew(userId: string, jobId: string) {
    const job = await this.assertOwnership(userId, jobId);
    return this.prisma.job.update({
      where: { id: job.id },
      data: { status: 'ACTIVE', expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000) },
    });
  }

  // Đẩy tin / tuyển gấp - V1 đánh dấu trực tiếp; khi bật thanh toán sẽ yêu cầu Subscription ACTIVE trước.
  async boost(userId: string, jobId: string) {
    const job = await this.assertOwnership(userId, jobId);
    return this.prisma.job.update({
      where: { id: job.id },
      data: { isBoosted: true, boostedUntil: new Date(Date.now() + 3 * 24 * 60 * 60 * 1000) },
    });
  }

  async listByEmployer(userId: string) {
    const employer = await this.prisma.employerProfile.findUnique({ where: { userId } });
    if (!employer) return [];
    return this.prisma.job.findMany({ where: { employerId: employer.id, deletedAt: null }, orderBy: { createdAt: 'desc' } });
  }

  private async assertOwnership(userId: string, jobId: string) {
    const job = await this.prisma.job.findUnique({ where: { id: jobId }, include: { employer: true } });
    if (!job || job.deletedAt) throw new NotFoundException('Không tìm thấy tin tuyển dụng.');
    if (job.employer.userId !== userId) throw new ForbiddenException('Bạn không có quyền với tin này.');
    return job;
  }

  private haversineKm(lat1: number, lon1: number, lat2: number, lon2: number): number {
    const toRad = (deg: number) => (deg * Math.PI) / 180;
    const R = 6371;
    const dLat = toRad(lat2 - lat1);
    const dLon = toRad(lon2 - lon1);
    const a =
      Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
  }
}
