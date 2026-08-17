// Seed dữ liệu khởi tạo hệ thống thật (không phải mock data thay database):
// thành phố Nha Trang, các khu vực (phường/xã), danh mục ngành nghề, và các
// tài khoản/tin tuyển dụng mẫu ở mức MVP để dev/test luồng end-to-end.
// Idempotent: chạy lại nhiều lần không tạo dữ liệu trùng lặp (dùng upsert/findFirst-or-create).
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

// Không dùng dữ liệu cá nhân thật - đầu số 09xxxxxxx dành riêng cho test/demo.
const TEST_ADMIN_PHONE = '0900000001';
const TEST_EMPLOYER_PHONE = '0900000002';
const TEST_JOB_SEEKER_PHONE = '0900000003';

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

  const areaByName = new Map<string, string>();
  for (const areaName of NHA_TRANG_AREAS) {
    const slug = slugify(areaName);
    const area = await prisma.area.upsert({
      where: { cityId_slug: { cityId: city.id, slug } },
      update: {},
      create: { cityId: city.id, name: areaName, slug, isActive: true },
    });
    areaByName.set(areaName, area.id);
  }

  const categoryByName = new Map<string, string>();
  for (let i = 0; i < CATEGORIES.length; i++) {
    const name = CATEGORIES[i];
    const slug = slugify(name);
    const category = await prisma.jobCategory.upsert({
      where: { slug },
      update: {},
      create: { name, slug, sortOrder: i, isActive: true },
    });
    categoryByName.set(name, category.id);
  }

  // ---- Tài khoản admin mẫu ----
  const adminUser = await prisma.user.upsert({
    where: { phone: TEST_ADMIN_PHONE },
    update: {},
    create: {
      phone: TEST_ADMIN_PHONE,
      roles: ['ADMIN'],
      isPhoneVerified: true,
      authProvider: 'PHONE',
    },
  });

  // ---- Tài khoản nhà tuyển dụng mẫu ----
  const employerUser = await prisma.user.upsert({
    where: { phone: TEST_EMPLOYER_PHONE },
    update: {},
    create: {
      phone: TEST_EMPLOYER_PHONE,
      roles: ['EMPLOYER'],
      isPhoneVerified: true,
      authProvider: 'PHONE',
    },
  });

  const employerProfile = await prisma.employerProfile.upsert({
    where: { userId: employerUser.id },
    update: {},
    create: {
      userId: employerUser.id,
      businessName: 'Hủ Tiếu Xào A Tiểu',
      description: 'Quán ăn gia đình tại Vĩnh Hải, Nha Trang.',
      verificationLevel: 'BUSINESS_VERIFIED',
    },
  });

  let employerLocation = await prisma.employerLocation.findFirst({
    where: { employerId: employerProfile.id, name: 'Hủ Tiếu Xào A Tiểu - Vĩnh Hải' },
  });
  if (!employerLocation) {
    employerLocation = await prisma.employerLocation.create({
      data: {
        employerId: employerProfile.id,
        name: 'Hủ Tiếu Xào A Tiểu - Vĩnh Hải',
        address: '12 Đường Củ Chi, Vĩnh Hải, Nha Trang',
        cityId: city.id,
        areaId: areaByName.get('Vĩnh Hải')!,
        latitude: 12.2586,
        longitude: 109.1946,
        phone: TEST_EMPLOYER_PHONE,
      },
    });
  }

  // ---- Tài khoản người tìm việc mẫu ----
  const jobSeekerUser = await prisma.user.upsert({
    where: { phone: TEST_JOB_SEEKER_PHONE },
    update: {},
    create: {
      phone: TEST_JOB_SEEKER_PHONE,
      roles: ['JOB_SEEKER'],
      isPhoneVerified: true,
      authProvider: 'PHONE',
    },
  });

  await prisma.jobSeekerProfile.upsert({
    where: { userId: jobSeekerUser.id },
    update: {},
    create: {
      userId: jobSeekerUser.id,
      fullName: 'Nguyễn Văn A (test)',
      areaId: areaByName.get('Vĩnh Hải'),
      latitude: 12.26,
      longitude: 109.195,
      desiredCategoryId: categoryByName.get('Phục vụ'),
      experienceLevel: 'UNDER_1_YEAR',
      shiftPreferences: ['EVENING', 'FLEXIBLE'],
      desiredSalaryMin: 25000,
      desiredSalaryMax: 35000,
      salaryUnit: 'HOUR',
      isSeeking: true,
    },
  });

  // ---- Tin tuyển dụng mẫu ----
  const sampleJobs = [
    {
      title: 'Phục vụ nhà hàng',
      categoryName: 'Phục vụ',
      headcount: 2,
      employmentType: 'PART_TIME' as const,
      shifts: ['EVENING' as const],
      shiftStartTime: '17:00',
      shiftEndTime: '22:00',
      salaryMin: 28000,
      salaryMax: 32000,
      salaryUnit: 'HOUR' as const,
      startUrgency: 'IMMEDIATE' as const,
      isUrgent: true,
      description: 'Phục vụ bàn, order món, dọn dẹp khu vực ăn uống.',
    },
    {
      title: 'Pha chế đồ uống',
      categoryName: 'Pha chế',
      headcount: 1,
      employmentType: 'PART_TIME' as const,
      shifts: ['AFTERNOON' as const, 'EVENING' as const],
      shiftStartTime: '14:00',
      shiftEndTime: '22:00',
      salaryMin: 30000,
      salaryMax: 38000,
      salaryUnit: 'HOUR' as const,
      startUrgency: 'WITHIN_3_DAYS' as const,
      isUrgent: false,
      description: 'Pha chế trà sữa, cà phê, đồ uống theo công thức có sẵn.',
    },
  ];

  for (const job of sampleJobs) {
    const existing = await prisma.job.findFirst({
      where: { employerLocationId: employerLocation.id, title: job.title },
    });
    if (existing) continue;

    await prisma.job.create({
      data: {
        employerId: employerProfile.id,
        employerLocationId: employerLocation.id,
        categoryId: categoryByName.get(job.categoryName)!,
        cityId: city.id,
        areaId: employerLocation.areaId,
        latitude: employerLocation.latitude,
        longitude: employerLocation.longitude,
        title: job.title,
        description: job.description,
        headcount: job.headcount,
        employmentType: job.employmentType,
        shifts: job.shifts,
        shiftStartTime: job.shiftStartTime,
        shiftEndTime: job.shiftEndTime,
        salaryMin: job.salaryMin,
        salaryMax: job.salaryMax,
        salaryUnit: job.salaryUnit,
        startUrgency: job.startUrgency,
        requiredExperience: 'NOT_REQUIRED',
        isUrgent: job.isUrgent,
        status: 'ACTIVE',
        publishedAt: new Date(),
        expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
      },
    });
  }

  console.log(
    `Seeded city "${city.name}" with ${NHA_TRANG_AREAS.length} areas, ${CATEGORIES.length} categories, ` +
      `admin=${adminUser.phone}, employer=${employerUser.phone}, jobSeeker=${jobSeekerUser.phone}, ` +
      `${sampleJobs.length} sample jobs.`,
  );
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
