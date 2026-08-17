// Seed dữ liệu khởi tạo hệ thống thật (không phải mock data thay database):
// thành phố Nha Trang, các khu vực (phường/xã) và danh mục ngành nghề.
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

const NHA_TRANG_AREAS = [
  'Lộc Thọ',
  'Tân Lập',
  'Phước Tiến',
  'Phước Tân',
  'Phước Long',
  'Phước Hải',
  'Vĩnh Hải',
  'Vĩnh Phước',
  'Vĩnh Thọ',
  'Xương Huân',
  'Vạn Thạnh',
  'Vạn Thắng',
  'Vĩnh Nguyên',
  'Vĩnh Ngọc',
  'Vĩnh Hiệp',
  'Vĩnh Trung',
  'Vĩnh Thái',
];

const CATEGORIES = [
  'Phục vụ',
  'Phụ bếp',
  'Đầu bếp',
  'Thu ngân',
  'Pha chế',
  'Tạp vụ',
  'Bán hàng',
  'Giao hàng',
  'Kho',
  'Kỹ thuật',
  'Văn phòng',
  'Khách sạn',
  'Du lịch',
  'Lao động phổ thông',
  'Khác',
];

function slugify(input: string): string {
  return input
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/đ/gi, (m) => (m === 'đ' ? 'd' : 'D'))
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/(^-|-$)/g, '');
}

async function main() {
  const city = await prisma.city.upsert({
    where: { slug: 'nha-trang' },
    update: {},
    create: { name: 'Nha Trang', slug: 'nha-trang', isActive: true },
  });

  for (const areaName of NHA_TRANG_AREAS) {
    const slug = slugify(areaName);
    await prisma.area.upsert({
      where: { cityId_slug: { cityId: city.id, slug } },
      update: {},
      create: { cityId: city.id, name: areaName, slug, isActive: true },
    });
  }

  for (let i = 0; i < CATEGORIES.length; i++) {
    const name = CATEGORIES[i];
    const slug = slugify(name);
    await prisma.jobCategory.upsert({
      where: { slug },
      update: {},
      create: { name, slug, sortOrder: i, isActive: true },
    });
  }

  console.log(`Seeded city "${city.name}" with ${NHA_TRANG_AREAS.length} areas and ${CATEGORIES.length} categories.`);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
