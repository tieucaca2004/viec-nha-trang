import { PrismaService } from '../../src/prisma/prisma.service';

/** Dữ liệu nền tối thiểu (thành phố/khu vực/danh mục) để tạo job trong test - idempotent qua upsert. */
export async function ensureBaseFixtures(prisma: PrismaService) {
  const city = await prisma.city.upsert({
    where: { slug: 'nha-trang' },
    update: {},
    create: { name: 'Nha Trang', slug: 'nha-trang' },
  });

  const area = await prisma.area.upsert({
    where: { cityId_slug: { cityId: city.id, slug: 'vinh-hai' } },
    update: {},
    create: { cityId: city.id, name: 'Vĩnh Hải', slug: 'vinh-hai' },
  });

  const otherArea = await prisma.area.upsert({
    where: { cityId_slug: { cityId: city.id, slug: 'loc-tho' } },
    update: {},
    create: { cityId: city.id, name: 'Lộc Thọ', slug: 'loc-tho' },
  });

  const category = await prisma.jobCategory.upsert({
    where: { slug: 'phuc-vu' },
    update: {},
    create: { name: 'Phục vụ', slug: 'phuc-vu' },
  });

  return { city, area, otherArea, category };
}

/**
 * Sinh số điện thoại VN hợp lệ (10 số, đầu 09) duy nhất cho mỗi test case.
 * `suite` là 1 chữ số phân biệt file test, tránh đụng số giữa các suite chạy chung DB.
 */
let counter = 0;
export function uniquePhone(suite: number): string {
  counter += 1;
  return `09${suite}${String(counter).padStart(7, '0')}`;
}
