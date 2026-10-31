// Import dữ liệu bài Facebook đã thu thập (posts.json) vào bảng community_posts.
// - Idempotent: khóa chống trùng là sourceUrl (@unique); chạy lại chỉ cập nhật nội dung, KHÔNG
//   tạo trùng và KHÔNG đổi trạng thái kiểm duyệt đã set.
// - Mặc định mọi bản ghi mới vào PENDING_REVIEW (KHÔNG tự APPROVED).
// - Bỏ qua IRRELEVANT / thiếu post_url / thiếu nội dung.
// - Không log PII (không in contacts/điện thoại).
import { CommunityPostStatus, Prisma, PrismaClient } from '@prisma/client';
import * as fs from 'fs';
import { normalizePost, RawFacebookPost } from './community-post.normalizer';

interface ImportStats {
  total: number;
  created: number;
  updated: number;
  invalid: number;
  duplicates: number;
  relevant: number;
}

function buildContent(norm: ReturnType<typeof normalizePost>): Prisma.CommunityPostCreateInput | null {
  if (!norm) return null;
  return {
    source: norm.source,
    sourceName: norm.sourceName,
    sourcePostId: norm.sourcePostId,
    sourceUrl: norm.sourceUrl,
    sourceGroupName: norm.sourceGroupName,
    sourceGroupUrl: norm.sourceGroupUrl,
    postType: norm.postType,
    title: norm.title,
    body: norm.body,
    industry: norm.industry,
    employerName: norm.employerName,
    workLocation: norm.workLocation,
    salaryMin: norm.salaryMin,
    salaryMax: norm.salaryMax,
    salaryCurrency: norm.salaryCurrency,
    salaryPeriod: norm.salaryPeriod,
    salaryTextOriginal: norm.salaryTextOriginal,
    employmentType: norm.employmentType,
    workSchedule: norm.workSchedule,
    experienceRequired: norm.experienceRequired,
    benefits: norm.benefits,
    contactMethod: norm.contactMethod,
    contactPublic: norm.contactPublic,
    contactsRaw: norm.contactsRaw == null ? Prisma.JsonNull : (norm.contactsRaw as Prisma.InputJsonValue),
    dataQuality: norm.dataQuality,
    duplicateOfId: norm.duplicateOfId,
    postedAt: norm.postedAt,
    collectedAt: norm.collectedAt,
  };
}

// posts.json thực tế chứa lone surrogate escape (\uD800-\uDFFF đứng một mình) khiến JSON.parse của
// Node ném "lone leading surrogate" (Python vẫn đọc được). Thay escape surrogate đơn bằng U+FFFD
// để parse được - KHÔNG bịa nội dung, chỉ sửa ký tự Unicode hỏng.
function sanitizeLoneSurrogates(raw: string): string {
  return raw
    .replace(/\\u([Dd][89ABab][0-9A-Fa-f]{2})(?!\\u[Dd][C-Fc-f][0-9A-Fa-f]{2})/g, '\\uFFFD')
    .replace(/(?<!\\u[Dd][89ABab][0-9A-Fa-f]{2})\\u([Dd][C-Fc-f][0-9A-Fa-f]{2})/g, '\\uFFFD');
}

async function main() {
  const jsonPath = process.argv[2] ?? process.env.FACEBOOK_POSTS_JSON ?? '';
  if (!jsonPath || !fs.existsSync(jsonPath)) {
    console.error('Thiếu đường dẫn JSON. Dùng: ts-node src/community-posts/import-facebook.ts <posts.json>');
    process.exit(1);
  }

  if (process.env.NODE_ENV === 'production' && process.env.ALLOW_PROD_IMPORT !== '1') {
    console.error('Từ chối import vào production (đặt ALLOW_PROD_IMPORT=1 nếu thật sự muốn).');
    process.exit(1);
  }

  const raw = JSON.parse(sanitizeLoneSurrogates(fs.readFileSync(jsonPath, 'utf8')));
  if (!Array.isArray(raw)) {
    console.error('File JSON phải là mảng bài đăng.');
    process.exit(1);
  }

  const prisma = new PrismaClient();
  const stats: ImportStats = { total: raw.length, created: 0, updated: 0, invalid: 0, duplicates: 0, relevant: 0 };
  const seen = new Set<string>();

  try {
    for (const item of raw as RawFacebookPost[]) {
      const norm = normalizePost(item);
      if (!norm) {
        stats.invalid++;
        continue;
      }
      if (seen.has(norm.sourceUrl)) {
        stats.duplicates++;
        continue;
      }
      seen.add(norm.sourceUrl);
      stats.relevant++;

      const content = buildContent(norm);
      if (!content) {
        stats.invalid++;
        continue;
      }

      const existing = await prisma.communityPost.findUnique({ where: { sourceUrl: norm.sourceUrl }, select: { id: true } });
      if (existing) {
        // Cập nhật nội dung, KHÔNG đổi status/moderated* (giữ nguyên quyết định kiểm duyệt).
        await prisma.communityPost.update({
          where: { sourceUrl: norm.sourceUrl },
          data: {
            ...content,
            // Không set status ở đây.
          } as Prisma.CommunityPostUpdateInput,
        });
        stats.updated++;
      } else {
        await prisma.communityPost.create({
          data: { ...content, status: CommunityPostStatus.PENDING_REVIEW },
        });
        stats.created++;
      }
    }
  } finally {
    await prisma.$disconnect();
  }

  console.log(JSON.stringify(stats, null, 2));
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
