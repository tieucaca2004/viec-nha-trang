import { Injectable, NotFoundException } from '@nestjs/common';
import { CommunityPostStatus, CommunityPostType, Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CommunityPostRowLike, toPublicCommunityPost, PublicCommunityPost } from './community-post.normalizer';

// Chỉ các trường được phép trả về công khai - TUYỆT ĐỐI không có contactsRaw/contactPublic/PII.
const PUBLIC_SELECT = {
  id: true,
  postType: true,
  title: true,
  body: true,
  industry: true,
  employerName: true,
  workLocation: true,
  salaryMin: true,
  salaryMax: true,
  salaryCurrency: true,
  salaryPeriod: true,
  salaryTextOriginal: true,
  employmentType: true,
  workSchedule: true,
  experienceRequired: true,
  benefits: true,
  contactMethod: true,
  postedAt: true,
  sourceGroupName: true,
  sourceUrl: true,
  dataQuality: true,
} satisfies Prisma.CommunityPostSelect;

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 50;

export interface PublicListParams {
  type?: CommunityPostType;
  industry?: string;
  location?: string;
  employmentType?: string;
  minSalary?: number;
  limit?: number;
  offset?: number;
}

export interface AdminListParams {
  status?: CommunityPostStatus;
  type?: CommunityPostType;
  limit?: number;
  offset?: number;
}

@Injectable()
export class CommunityPostsService {
  constructor(private readonly prisma: PrismaService) {}

  // Điều kiện "còn hạn hiển thị": chưa có expiresAt, hoặc expiresAt ở tương lai.
  private notExpired(): Prisma.CommunityPostWhereInput {
    return { OR: [{ expiresAt: null }, { expiresAt: { gt: new Date() } }] };
  }

  async listPublic(params: PublicListParams): Promise<{ data: PublicCommunityPost[]; meta: { total: number; limit: number; offset: number } }> {
    const limit = Math.min(Math.max(params.limit ?? DEFAULT_LIMIT, 1), MAX_LIMIT);
    const offset = Math.max(params.offset ?? 0, 0);
    const where: Prisma.CommunityPostWhereInput = {
      status: CommunityPostStatus.APPROVED,
      ...(params.type ? { postType: params.type } : {}),
      ...(params.industry ? { industry: { contains: params.industry, mode: 'insensitive' } } : {}),
      ...(params.location ? { workLocation: { contains: params.location, mode: 'insensitive' } } : {}),
      ...(params.employmentType ? { employmentType: params.employmentType } : {}),
      ...(params.minSalary != null ? { salaryMin: { gte: params.minSalary } } : {}),
      AND: [this.notExpired()],
    };

    const [rows, total] = await Promise.all([
      this.prisma.communityPost.findMany({
        where,
        select: PUBLIC_SELECT,
        orderBy: [{ postedAt: 'desc' }, { createdAt: 'desc' }],
        take: limit,
        skip: offset,
      }),
      this.prisma.communityPost.count({ where }),
    ]);

    return { data: rows.map((r) => toPublicCommunityPost(r as CommunityPostRowLike)), meta: { total, limit, offset } };
  }

  async findPublicOne(id: string): Promise<PublicCommunityPost> {
    const row = await this.prisma.communityPost.findFirst({
      where: { id, status: CommunityPostStatus.APPROVED, AND: [this.notExpired()] },
      select: PUBLIC_SELECT,
    });
    if (!row) throw new NotFoundException('Không tìm thấy bài đăng.');
    return toPublicCommunityPost(row as CommunityPostRowLike);
  }

  async listAdmin(params: AdminListParams) {
    const limit = Math.min(Math.max(params.limit ?? DEFAULT_LIMIT, 1), MAX_LIMIT);
    const offset = Math.max(params.offset ?? 0, 0);
    const where: Prisma.CommunityPostWhereInput = {
      ...(params.status ? { status: params.status } : {}),
      ...(params.type ? { postType: params.type } : {}),
    };
    const [data, total] = await Promise.all([
      this.prisma.communityPost.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        take: limit,
        skip: offset,
      }),
      this.prisma.communityPost.count({ where }),
    ]);
    return { data, total, limit, offset };
  }

  async stats() {
    const [byStatusRaw, byTypeRaw, total] = await Promise.all([
      this.prisma.communityPost.groupBy({ by: ['status'], _count: { _all: true } }),
      this.prisma.communityPost.groupBy({ by: ['postType'], _count: { _all: true } }),
      this.prisma.communityPost.count(),
    ]);
    const byStatus = Object.fromEntries(byStatusRaw.map((r) => [r.status, r._count._all]));
    const byType = Object.fromEntries(byTypeRaw.map((r) => [r.postType, r._count._all]));
    return { total, byStatus, byType };
  }

  async moderate(
    adminId: string,
    id: string,
    status: CommunityPostStatus,
    note?: string,
  ) {
    const existing = await this.prisma.communityPost.findUnique({ where: { id } });
    if (!existing) throw new NotFoundException('Không tìm thấy bài đăng cộng đồng.');

    // Khi duyệt: đặt thời điểm hết hạn hiển thị (30 ngày). Khi từ chối: bỏ hạn hiển thị.
    const expiresAt = status === CommunityPostStatus.APPROVED ? new Date(Date.now() + 30 * 24 * 60 * 60 * 1000) : null;
    return this.prisma.communityPost.update({
      where: { id },
      data: { status, moderatedAt: new Date(), moderatedBy: adminId, moderationNote: note ?? null, expiresAt },
    });
  }
}
