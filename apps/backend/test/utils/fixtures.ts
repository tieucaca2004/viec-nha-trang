import { randomInt } from 'crypto';
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
 * `suite` (tham số cũ, giữ lại cho tương thích ngược - KHÔNG còn quyết định tính duy nhất) từng
 * là 1 chữ số phân biệt file test, nhưng Jest sandbox module riêng cho mỗi file test (kể cả khi
 * chạy --runInBand) nên biến đếm `counter` reset về 0 ở MỖI file - 2 file cùng dùng 1 chữ số
 * `suite` có thể sinh trùng số điện thoại và đụng unique constraint thật trên DB test dùng
 * chung. Sửa bằng 7 chữ số cuối random thật (đủ không gian 10^7, xác suất trùng giữa các file
 * gần như bằng 0) thay vì phụ thuộc suite.
 *
 * Đầu số CỐ ĐỊNH "093" (không phải random) - đã kiểm chứng: validator IsPhoneNumber('VN') (dùng
 * libphonenumber-js) coi đầu số "099" là không ổn định (chỉ 1 phần số đuôi ngẫu nhiên hợp lệ,
 * ~10% bị từ chối dù đúng 10 chữ số) trong khi "090".."098" luôn hợp lệ với MỌI 7 số đuôi - chọn
 * "093" để tránh vùng rủi ro này hoàn toàn.
 */
export function uniquePhone(_suite?: number): string {
  const rand = randomInt(0, 10_000_000).toString().padStart(7, '0');
  return `093${rand}`;
}

let emailCounter = 0;
export function uniqueEmail(suite: string): string {
  emailCounter += 1;
  return `${suite}-${emailCounter}@example.test`;
}
