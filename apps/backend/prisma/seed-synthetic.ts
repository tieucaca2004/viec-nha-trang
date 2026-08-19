// Synthetic data seed (đặc tả JobHunter Phần 2/3) - SINH DỮ LIỆU TỔNG HỢP để test search/filter/
// dashboard/matching/UX ở quy mô lớn, KHÔNG PHẢI người dùng thật.
//
// NGUYÊN TẮC BẮT BUỘC:
// - Mọi Job sinh ra có sourceType=SYNTHETIC, sourceName='synthetic' - phân biệt rõ với
//   USER_CREATED/IMPORTED, KHÔNG BAO GIỜ giả mạo thành job người dùng thật đăng.
// - Mọi User (employer/seeker) sinh ra dùng email @viecnhatrang.internal (domain KHÔNG deliverable,
//   dành riêng cho dữ liệu tổng hợp) - KHÔNG dùng email/số điện thoại thật của bất kỳ ai, KHÔNG có
//   số điện thoại (phone=null) nên KHÔNG THỂ tham gia luồng xác minh SMS/liên hệ thật.
// - Tên người sinh từ pool họ+tên đệm+tên phổ biến trong tiếng Việt (KHÔNG dùng tên người nổi
//   tiếng/có thể nhận dạng - đây là các tổ hợp họ tên phổ biến, không định danh cá nhân cụ thể).
// - Script này KHÔNG được wire vào `npm run seed` mặc định / CI - chỉ chạy thủ công qua
//   `npm run seed:synthetic` khi cần dữ liệu lớn để test, tránh làm chậm/ô nhiễm test suite CI.
// - Deterministic: cùng SEED cho ra cùng dữ liệu; idempotent qua upsert theo khoá xác định
//   (email cho User, sourceJobId cho Job) - chạy lại KHÔNG tạo trùng lặp.
import { PrismaClient, SalaryUnit, ExperienceLevel, EmploymentType, RequiredExperience, ShiftPreference } from '@prisma/client';

const prisma = new PrismaClient();

const SEED = 20260819;
const TARGET_EMPLOYERS = 500;
const TARGET_SEEKERS = 5000;
const TARGET_JOBS = 3000;

// ---------- PRNG deterministic (mulberry32) - KHÔNG dùng Math.random() ở đâu trong file này ----------
function mulberry32(seed: number) {
  let a = seed;
  return function random(): number {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rng = mulberry32(SEED);
function pick<T>(arr: readonly T[]): T {
  return arr[Math.floor(rng() * arr.length)];
}
function pickN<T>(arr: readonly T[], n: number): T[] {
  const pool = [...arr];
  const result: T[] = [];
  for (let i = 0; i < n && pool.length > 0; i++) {
    const idx = Math.floor(rng() * pool.length);
    result.push(pool.splice(idx, 1)[0]);
  }
  return result;
}
function intBetween(min: number, max: number): number {
  return Math.floor(rng() * (max - min + 1)) + min;
}
function chance(p: number): boolean {
  return rng() < p;
}

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

// ---------- Danh mục ngành nghề (đặc tả Phần 2 - 26 ngành) ----------
const SYNTHETIC_CATEGORIES = [
  'Nhà hàng',
  'Khách sạn',
  'Du lịch',
  'F&B',
  'Sales',
  'Marketing',
  'Kế toán',
  'Nhân sự',
  'Hành chính',
  'IT',
  'Thiết kế',
  'Xây dựng',
  'Kỹ thuật',
  'Điện',
  'Cơ khí',
  'Logistics',
  'Kho vận',
  'Tài xế',
  'Bán lẻ',
  'Chăm sóc khách hàng',
  'Lao động phổ thông',
  'Y tế',
  'Giáo dục',
  'Spa',
  'Làm đẹp',
  'Bảo vệ',
];

// Khánh Hòa (ngoài Nha Trang) - đại diện Cam Ranh/Ninh Hòa/Diên Khánh/Vạn Ninh để phân bố vị trí
// đa dạng hơn thay vì dồn 100% vào Nha Trang, vẫn đúng đặc tả "Nha Trang, Khánh Hòa".
const KHANH_HOA_AREAS = ['Cam Ranh', 'Ninh Hòa', 'Diên Khánh', 'Vạn Ninh', 'Cam Lâm'];

// ---------- Pool họ tên tiếng Việt phổ biến (KHÔNG phải người nổi tiếng - tổ hợp chung chung) ----------
const FAMILY_NAMES = ['Nguyễn', 'Trần', 'Lê', 'Phạm', 'Hoàng', 'Huỳnh', 'Phan', 'Vũ', 'Võ', 'Đặng', 'Bùi', 'Đỗ', 'Ngô', 'Dương', 'Lý'];
const MIDDLE_NAMES = ['Văn', 'Thị', 'Hữu', 'Đức', 'Minh', 'Thành', 'Ngọc', 'Thanh', 'Xuân', 'Quang'];
const GIVEN_NAMES = [
  'An',
  'Bình',
  'Chi',
  'Cường',
  'Dũng',
  'Duyên',
  'Giang',
  'Hà',
  'Hải',
  'Hạnh',
  'Hiếu',
  'Hoa',
  'Hùng',
  'Huy',
  'Khang',
  'Lan',
  'Linh',
  'Long',
  'Mai',
  'My',
  'Nam',
  'Nga',
  'Ngân',
  'Nhung',
  'Oanh',
  'Phương',
  'Quân',
  'Quyên',
  'Sơn',
  'Tâm',
  'Thảo',
  'Thịnh',
  'Thu',
  'Thùy',
  'Tiến',
  'Trang',
  'Trung',
  'Tuấn',
  'Tú',
  'Uyên',
  'Vy',
];

function randomPersonName(): string {
  return `${pick(FAMILY_NAMES)} ${pick(MIDDLE_NAMES)} ${pick(GIVEN_NAMES)}`;
}

// ---------- Business name templates theo nhóm ngành ----------
const BUSINESS_PREFIX: Record<string, string[]> = {
  default: ['Công ty', 'Cửa hàng', 'Cơ sở'],
  'Nhà hàng': ['Nhà hàng', 'Quán ăn', 'Nhà hàng hải sản'],
  'F&B': ['Quán cà phê', 'Trà sữa', 'Quán ăn nhanh'],
  'Khách sạn': ['Khách sạn', 'Homestay', 'Resort'],
  'Du lịch': ['Công ty du lịch', 'Tour du lịch'],
  Spa: ['Spa', 'Trung tâm chăm sóc sắc đẹp'],
  'Làm đẹp': ['Salon tóc', 'Thẩm mỹ viện'],
  'Bán lẻ': ['Siêu thị mini', 'Cửa hàng tiện lợi'],
  IT: ['Công ty công nghệ', 'Studio phần mềm'],
  'Bảo vệ': ['Công ty bảo vệ'],
};
const BUSINESS_SUFFIX_WORDS = [
  'Biển Xanh',
  'Hoàng Gia',
  'Phương Nam',
  'Ánh Dương',
  'Bình Minh',
  'Sao Việt',
  'Nha Trang',
  'Thái Bình Dương',
  'Sông Cái',
  'Hòn Chồng',
  'Trường Sa',
  'Vĩnh Hải',
  'An Phú',
  'Đại Dương',
  'Miền Trung',
];

function randomBusinessName(categoryName: string): string {
  const prefixes = BUSINESS_PREFIX[categoryName] ?? BUSINESS_PREFIX.default;
  return `${pick(prefixes)} ${pick(BUSINESS_SUFFIX_WORDS)}`;
}

// ---------- Title / description variation engine ----------
const ROLE_NOUNS: Record<string, string[]> = {
  'Nhà hàng': ['Phục vụ', 'Phụ bếp', 'Bếp chính', 'Thu ngân', 'Quản lý ca'],
  'Khách sạn': ['Lễ tân', 'Buồng phòng', 'Quản lý khách sạn', 'Bellman'],
  'Du lịch': ['Hướng dẫn viên', 'Điều hành tour', 'Nhân viên vé'],
  'F&B': ['Pha chế', 'Nhân viên order', 'Phục vụ quán'],
  Sales: ['Nhân viên kinh doanh', 'Sales bất động sản', 'Tư vấn bán hàng'],
  Marketing: ['Nhân viên marketing', 'Content creator', 'Chạy quảng cáo Facebook'],
  'Kế toán': ['Kế toán viên', 'Kế toán kho', 'Kế toán tổng hợp'],
  'Nhân sự': ['Nhân viên tuyển dụng', 'Chuyên viên C&B'],
  'Hành chính': ['Nhân viên hành chính', 'Thư ký văn phòng'],
  IT: ['Lập trình viên', 'Nhân viên IT hỗ trợ', 'Tester'],
  'Thiết kế': ['Thiết kế đồ hoạ', 'Designer UI/UX'],
  'Xây dựng': ['Thợ xây', 'Giám sát công trình', 'Kỹ sư xây dựng'],
  'Kỹ thuật': ['Kỹ thuật viên', 'Bảo trì máy'],
  Điện: ['Thợ điện', 'Kỹ sư điện'],
  'Cơ khí': ['Thợ cơ khí', 'Vận hành máy CNC'],
  Logistics: ['Nhân viên logistics', 'Điều phối vận tải'],
  'Kho vận': ['Nhân viên kho', 'Thủ kho'],
  'Tài xế': ['Tài xế giao hàng', 'Lái xe tải', 'Tài xế công nghệ'],
  'Bán lẻ': ['Nhân viên bán hàng', 'Thu ngân siêu thị'],
  'Chăm sóc khách hàng': ['Tổng đài viên', 'CSKH online'],
  'Lao động phổ thông': ['Lao động phổ thông', 'Bốc xếp hàng hoá'],
  'Y tế': ['Điều dưỡng', 'Dược sĩ bán hàng'],
  'Giáo dục': ['Giáo viên tiếng Anh', 'Trợ giảng'],
  Spa: ['Kỹ thuật viên spa', 'Massage trị liệu'],
  'Làm đẹp': ['Thợ làm tóc', 'Nhân viên nail'],
  'Bảo vệ': ['Bảo vệ ca đêm', 'Bảo vệ toà nhà'],
};
const TITLE_DESCRIPTORS = ['gấp', 'lương cao', 'không cần kinh nghiệm', 'part-time', 'full-time', 'theo ca', ''];

function randomTitle(categoryName: string, areaName: string): string {
  const roles = ROLE_NOUNS[categoryName] ?? ['Nhân viên'];
  const role = pick(roles);
  const descriptor = pick(TITLE_DESCRIPTORS);
  const base = `Tuyển ${role} khu vực ${areaName}`;
  return descriptor ? `${base} - ${descriptor}` : base;
}

const DESC_INTRO = [
  'Chúng tôi đang cần tuyển bổ sung nhân sự cho vị trí này.',
  'Cơ sở đang mở rộng và cần thêm người ngay.',
  'Vị trí phù hợp cho người muốn làm việc ổn định lâu dài.',
  'Môi trường làm việc thân thiện, đồng nghiệp hỗ trợ nhiệt tình.',
];
const DESC_DUTIES = [
  'Công việc chính bao gồm hỗ trợ vận hành hàng ngày theo phân công.',
  'Thực hiện đúng quy trình đã được đào tạo, đảm bảo chất lượng phục vụ.',
  'Phối hợp cùng các bộ phận khác để hoàn thành mục tiêu chung.',
  'Chủ động báo cáo tiến độ công việc cho quản lý trực tiếp.',
];
const DESC_BENEFITS_SENTENCE = [
  'Có hỗ trợ ăn ca, thưởng doanh số theo tháng.',
  'Được đóng bảo hiểm đầy đủ sau thời gian thử việc.',
  'Xét tăng lương định kỳ theo năng lực.',
  'Có xe đưa đón hoặc hỗ trợ chi phí đi lại.',
];

function randomDescription(): string {
  return [pick(DESC_INTRO), pick(DESC_DUTIES), pick(DESC_BENEFITS_SENTENCE)].join(' ');
}

const BENEFITS_POOL = [
  'Thưởng lễ Tết',
  'Bảo hiểm đầy đủ',
  'Ăn ca miễn phí',
  'Đồng phục',
  'Đào tạo tại chỗ',
  'Thưởng doanh số',
  'Xét tăng lương định kỳ',
  'Môi trường trẻ trung',
  'Hỗ trợ chỗ ở',
  'Xe đưa đón',
];
const SKILLS_POOL = [
  'Giao tiếp tốt',
  'Chịu được áp lực',
  'Có xe máy',
  'Tiếng Anh cơ bản',
  'Tin học văn phòng',
  'Kinh nghiệm phục vụ',
  'Sức khoẻ tốt',
  'Trung thực',
  'Chăm chỉ',
  'Có kinh nghiệm bán hàng',
];

// Mức lương "tier" theo nhóm ngành (baseline tháng, đơn vị đồng) - HIỆU CHỈNH từ khảo sát nguồn
// thật (xem prisma/salary-benchmarks.ts - 21 observation từ CareerViet/TopCV/VieclamTot/Trung
// tâm DVVL Khánh Hòa/... qua WebSearch, KHÔNG mở được từng trang do egress proxy chặn WebFetch -
// mỗi tier dưới đây trích dẫn observation gốc, confidence MEDIUM trừ khi ghi chú khác).
const SALARY_TIER_MONTH: Record<string, [number, number]> = {
  IT: [10_000_000, 22_000_000], // nhatrangjob.vn: lập trình CSDL tới 22tr (MEDIUM)
  'Thiết kế': [8_000_000, 18_000_000], // chưa khảo sát riêng - giữ ước tính cũ (LOW)
  Marketing: [7_000_000, 16_000_000], // chưa khảo sát riêng - giữ ước tính cũ (LOW)
  'Kế toán': [7_000_000, 15_000_000], // topcv.vn/123job.vn: phổ biến 7-15tr, TAZA GROUP niêm yết 10-15tr (MEDIUM)
  Sales: [6_000_000, 15_000_000], // joboko.com cứng 6tr+hoa hồng, FMCG tổng 12-15tr (MEDIUM)
  'Nhân sự': [7_000_000, 15_000_000], // chưa khảo sát riêng - giữ ước tính cũ (LOW)
  'Hành chính': [5_500_000, 11_000_000], // chưa khảo sát riêng - giữ ước tính cũ (LOW)
  'Y tế': [8_000_000, 18_000_000], // chưa khảo sát riêng - giữ ước tính cũ (LOW)
  'Giáo dục': [10_000_000, 20_000_000], // VN-wide 25-40tr (LOW, khả năng lệch cao do gộp HN/HCM) - hạ thận trọng cho Nha Trang, xem HOUR tier riêng cho part-time
  'Kỹ thuật': [10_000_000, 20_000_000], // careerviet.vn: kỹ thuật/kỹ sư chung 10-20tr (MEDIUM)
  Điện: [7_000_000, 14_000_000], // chưa khảo sát riêng - giữ ước tính cũ (LOW)
  'Cơ khí': [6_500_000, 13_000_000], // chưa khảo sát riêng - giữ ước tính cũ (LOW)
  'Xây dựng': [7_000_000, 15_000_000], // careerviet.vn: 7-15tr (MEDIUM)
  Logistics: [8_000_000, 12_000_000], // careerviet.vn/vietnamworks.com, VN-wide (LOW)
  'Kho vận': [8_000_000, 12_000_000], // cùng nguồn Logistics (LOW)
  'Tài xế': [7_500_000, 15_000_000], // thongtinvieclamkhanhhoa.vn 7.5-8tr entry + careerviet.vn 8-15tr theo loại xe (MEDIUM)
  'Bảo vệ': [4_500_000, 9_000_000], // muaban.net/123job.vn ca đêm (MEDIUM)
  'Bán lẻ': [9_000_000, 13_000_000], // vieclamtot.com Coop Nha Trang (MEDIUM)
  'Chăm sóc khách hàng': [7_000_000, 14_000_000], // vieclam24h.vn KHÔNG có số riêng Nha Trang (LOW)
  'Du lịch': [7_000_000, 10_000_000], // hoteljob.vn/nhatrangjob.vn hướng dẫn viên, chưa gồm phụ cấp/tip (MEDIUM)
  'Khách sạn': [3_000_000, 7_000_000], // tuyendungnhatrang.com lễ tân 3-5 sao, LƯƠNG CỨNG - tip/thưởng cộng thêm ngoài mức này (MEDIUM)
  Spa: [4_000_000, 12_000_000], // topcv.vn TAZA GROUP: cứng 4tr + hoa hồng 15%+tip (thu nhập thực tế có thể cao hơn nhiều - chỉ mô hình hoá phần lương cố định) (LOW)
  'Làm đẹp': [4_000_000, 10_000_000], // chưa khảo sát riêng, ước tính theo Spa (LOW)
  'Lao động phổ thông': [5_000_000, 8_000_000], // search không trả số cụ thể cho Nha Trang - giữ mặc định thận trọng (LOW)
  'Nhà hàng': [4_000_000, 8_000_000], // careerviet.vn/tuyendungnhatrang.com: "thoả thuận" 2.5-5tr bất thường thấp (có thể chỉ phụ cấp+tip) - suy luận nối tiếp thận trọng, KHÔNG phải quan sát trực tiếp (LOW)
  default: [5_000_000, 10_000_000],
};

// Mức lương theo GIỜ cho nhóm có bằng chứng thật là part-time/hourly phổ biến (đặc tả: "Nếu dữ
// liệu chứng minh 18-25k/h là phổ biến ở một phân khúc → GIỮ NGUYÊN, không nâng chỉ vì AI cho là
// thấp"). Dùng TRỰC TIẾP (không suy ra từ chia SALARY_TIER_MONTH/208h) để phản ánh đúng số liệu
// thật đã khảo sát, thay vì suy diễn.
//
// GIỚI HẠN: search không cho đủ dữ liệu để tách 5 phân khúc cafe (sinh viên/bình dân/phổ thông/
// du lịch/cao cấp) như yêu cầu ban đầu - chỉ có 1 cụm "part-time cafe nói chung" (LOW, VN-wide,
// không riêng Nha Trang). Ghi nhận đây là gap, KHÔNG bịa 5 mức riêng biệt không có căn cứ.
const SALARY_TIER_HOUR: Partial<Record<string, [number, number]>> = {
  'F&B': [14_000, 27_000], // muaban.net/careerviet.vn part-time cafe (LOW, VN-wide) - giữ nguyên, không nâng
  'Bảo vệ': [19_000, 22_000], // vieclamtot.com Lotte Mart Nha Trang (MEDIUM)
  'Giáo dục': [25_000, 35_000], // careerviet.vn/vietnamworks.com GV tiếng Anh part-time (LOW, VN-wide)
};

function randomSalaryMonth(categoryName: string): [number, number] {
  const [lo, hi] = SALARY_TIER_MONTH[categoryName] ?? SALARY_TIER_MONTH.default;
  const min = intBetween(lo, hi - 1_000_000);
  const max = min + intBetween(500_000, hi - min);
  return [min, max];
}

function randomSalaryHour(categoryName: string): [number, number] | null {
  const tier = SALARY_TIER_HOUR[categoryName];
  if (!tier) return null;
  const [lo, hi] = tier;
  const min = intBetween(lo, hi - 1_000);
  const max = min + intBetween(500, Math.max(500, hi - min));
  return [min, Math.min(max, hi)];
}

const EMPLOYMENT_TYPES: EmploymentType[] = ['FULL_TIME', 'PART_TIME', 'SHIFT_BASED', 'SEASONAL'];
const REQUIRED_EXPERIENCE_WEIGHTS: RequiredExperience[] = [
  'NOT_REQUIRED',
  'NOT_REQUIRED',
  'PREFERRED',
  'PREFERRED',
  'REQUIRED',
];
const EXPERIENCE_LEVELS: ExperienceLevel[] = ['NONE', 'UNDER_1_YEAR', 'ONE_TO_3_YEARS', 'OVER_3_YEARS'];

function randomShifts(employmentType: EmploymentType): ShiftPreference[] {
  if (employmentType === 'FULL_TIME') return chance(0.7) ? ['FLEXIBLE'] : pickN(['MORNING', 'AFTERNOON'], 2);
  const pool: ShiftPreference[] = ['MORNING', 'AFTERNOON', 'EVENING', 'NIGHT'];
  return pickN(pool, intBetween(1, 2));
}

function randomSalaryUnit(employmentType: EmploymentType): SalaryUnit {
  if (employmentType === 'SHIFT_BASED') return 'SHIFT';
  if (employmentType === 'PART_TIME') return chance(0.5) ? 'HOUR' : 'SHIFT';
  return 'MONTH';
}

async function main() {
  console.log(`[seed:synthetic] SEED=${SEED} - bắt đầu (idempotent, có thể chạy lại an toàn)...`);

  // ---- City "Khánh Hòa" (ngoài Nha Trang) + areas ----
  const khanhHoaCity = await prisma.city.upsert({
    where: { slug: 'khanh-hoa' },
    update: {},
    create: { name: 'Khánh Hòa', slug: 'khanh-hoa', isActive: true },
  });
  const khanhHoaAreaIds: string[] = [];
  for (const name of KHANH_HOA_AREAS) {
    const slug = slugify(name);
    const area = await prisma.area.upsert({
      where: { cityId_slug: { cityId: khanhHoaCity.id, slug } },
      update: {},
      create: { cityId: khanhHoaCity.id, name, slug, isActive: true },
    });
    khanhHoaAreaIds.push(area.id);
  }

  const nhaTrangCity = await prisma.city.findUniqueOrThrow({ where: { slug: 'nha-trang' } });
  const nhaTrangAreas = await prisma.area.findMany({ where: { cityId: nhaTrangCity.id } });
  if (nhaTrangAreas.length === 0) {
    throw new Error('Chưa có Area nào cho Nha Trang - chạy `npm run seed` (seed chính) trước khi chạy seed:synthetic.');
  }

  // ---- 26 ngành nghề (Phần 2) - upsert, không trùng với 15 category có sẵn ----
  const allAreas = [...nhaTrangAreas.map((a) => ({ ...a, cityId: nhaTrangCity.id })), ...(await prisma.area.findMany({ where: { cityId: khanhHoaCity.id } }))];

  const existingCategoriesCount = await prisma.jobCategory.count();
  const categoryByName = new Map<string, string>();
  for (let i = 0; i < SYNTHETIC_CATEGORIES.length; i++) {
    const name = SYNTHETIC_CATEGORIES[i];
    const slug = slugify(name);
    const category = await prisma.jobCategory.upsert({
      where: { slug },
      update: {},
      create: { name, slug, sortOrder: existingCategoriesCount + i, isActive: true },
    });
    categoryByName.set(name, category.id);
  }

  const categoryNames = Array.from(categoryByName.keys());

  // ---- 500 synthetic employers + 1 location mỗi employer ----
  console.log(`[seed:synthetic] Tạo/đảm bảo ${TARGET_EMPLOYERS} employer tổng hợp...`);
  const employerRefs: Array<{ employerId: string; cityId: string; areaId: string; latitude: number; longitude: number }> = [];

  for (let i = 1; i <= TARGET_EMPLOYERS; i++) {
    const email = `synthetic-employer-${String(i).padStart(4, '0')}@viecnhatrang.internal`;
    const categoryName = pick(categoryNames);
    const area = pick(allAreas);
    const businessName = `${randomBusinessName(categoryName)} #${i}`;

    const user = await prisma.user.upsert({
      where: { email },
      update: {},
      create: { email, roles: ['EMPLOYER'], authProvider: 'EMAIL', isEmailVerified: false },
    });

    const employer = await prisma.employerProfile.upsert({
      where: { userId: user.id },
      update: {},
      create: {
        userId: user.id,
        businessName,
        description: `Dữ liệu mẫu (SYNTHETIC) - đại diện 1 cơ sở kinh doanh ngành ${categoryName} để test tìm kiếm/lọc, không phải doanh nghiệp thật.`,
      },
    });

    let location = await prisma.employerLocation.findFirst({ where: { employerId: employer.id } });
    if (!location) {
      // Toạ độ trung tâm Nha Trang + jitter nhỏ deterministic - đủ để test khoảng cách/bán kính,
      // không claim là vị trí GPS chính xác thật.
      const baseLat = 12.2388;
      const baseLng = 109.1967;
      location = await prisma.employerLocation.create({
        data: {
          employerId: employer.id,
          name: `${businessName} - Cơ sở ${area.name}`,
          address: `${area.name}, ${area.cityId === nhaTrangCity.id ? 'Nha Trang' : 'Khánh Hòa'}`,
          cityId: area.cityId,
          areaId: area.id,
          latitude: baseLat + (rng() - 0.5) * 0.15,
          longitude: baseLng + (rng() - 0.5) * 0.15,
        },
      });
    }

    employerRefs.push({ employerId: employer.id, cityId: location.cityId, areaId: location.areaId, latitude: location.latitude, longitude: location.longitude });
  }

  // ---- 5000 synthetic job seekers ----
  console.log(`[seed:synthetic] Tạo/đảm bảo ${TARGET_SEEKERS} hồ sơ ứng viên tổng hợp...`);
  const now = new Date();
  for (let i = 1; i <= TARGET_SEEKERS; i++) {
    const email = `synthetic-seeker-${String(i).padStart(5, '0')}@viecnhatrang.internal`;
    const user = await prisma.user.upsert({
      where: { email },
      update: {},
      // phone=null CHỦ ĐÍCH - synthetic seeker không có số điện thoại nào để không thể tham gia
      // luồng xác minh SMS/liên hệ thật (đặc tả Phần 3: "Không cho synthetic seeker tham gia
      // flow liên hệ thật", "Không gửi SMS/email tới synthetic accounts").
      create: { email, roles: ['JOB_SEEKER'], authProvider: 'EMAIL', isEmailVerified: false },
    });

    const existingProfile = await prisma.jobSeekerProfile.findUnique({ where: { userId: user.id } });
    if (existingProfile) continue;

    const categoryName = pick(categoryNames);
    const area = pick(allAreas);
    const ageYears = intBetween(18, 55);
    const dob = new Date(now.getFullYear() - ageYears, intBetween(0, 11), intBetween(1, 28));
    const experienceLevel = pick(EXPERIENCE_LEVELS);
    const [salaryMin, salaryMax] = randomSalaryMonth(categoryName);

    await prisma.jobSeekerProfile.create({
      data: {
        userId: user.id,
        fullName: randomPersonName(),
        areaId: area.id,
        desiredCategoryId: categoryByName.get(categoryName),
        dateOfBirth: dob,
        experienceLevel,
        skills: pickN(SKILLS_POOL, intBetween(2, 4)),
        shiftPreferences: pickN(['MORNING', 'AFTERNOON', 'EVENING', 'NIGHT', 'FLEXIBLE'], intBetween(1, 2)),
        desiredSalaryMin: salaryMin,
        desiredSalaryMax: salaryMax,
        salaryUnit: 'MONTH',
        isSeeking: true,
      },
    });
  }

  // ---- 3000 synthetic jobs ----
  console.log(`[seed:synthetic] Tạo/đảm bảo ${TARGET_JOBS} tin tuyển dụng tổng hợp...`);
  const usedTitles = new Set<string>();
  for (let i = 1; i <= TARGET_JOBS; i++) {
    const sourceJobId = `synthetic-job-${String(i).padStart(6, '0')}`;

    const employerRef = employerRefs[i % employerRefs.length];
    const areaRow = allAreas.find((a) => a.id === employerRef.areaId)!;
    const categoryName = pick(categoryNames);
    const employmentType = pick(EMPLOYMENT_TYPES);

    let title = randomTitle(categoryName, areaRow.name);
    let attempt = 0;
    while (usedTitles.has(title) && attempt < 5) {
      title = `${randomTitle(categoryName, areaRow.name)} (${i})`;
      attempt += 1;
    }
    usedTitles.add(title);

    const salaryUnit = randomSalaryUnit(employmentType);
    // Ưu tiên mức lương theo GIỜ khảo sát trực tiếp (SALARY_TIER_HOUR) khi có, thay vì suy ra từ
    // lương tháng chia 208h - vì phép chia có thể cho ra mức cao hơn thực tế đã khảo sát (đặc tả:
    // "GIỮ NGUYÊN, không nâng mức lương chỉ vì AI cho rằng mức đó thấp").
    const directHourTier = salaryUnit === 'HOUR' ? randomSalaryHour(categoryName) : null;
    let salaryMin: number;
    let salaryMax: number;
    if (directHourTier) {
      [salaryMin, salaryMax] = directHourTier;
    } else {
      const [salaryMinMonth, salaryMaxMonth] = randomSalaryMonth(categoryName);
      const unitDivisor = salaryUnit === 'HOUR' ? 208 : salaryUnit === 'DAY' || salaryUnit === 'SHIFT' ? 26 : 1;
      salaryMin = Math.max(1, Math.round(salaryMinMonth / unitDivisor));
      salaryMax = Math.max(salaryMin, Math.round(salaryMaxMonth / unitDivisor));
    }

    // Publish trong 60 ngày gần đây - đây là mốc "hệ thống seed coi như đã đăng", không phải claim
    // về 1 nguồn ngoài không kiểm soát được (khác hẳn nguyên tắc "không bịa ngày" áp dụng cho IMPORTED).
    const publishedAt = new Date(now.getTime() - intBetween(0, 60) * 24 * 60 * 60 * 1000);

    let status: 'ACTIVE' | 'PENDING_REVIEW' | 'EXPIRED' | 'CLOSED' = 'ACTIVE';
    let expiresAt: Date | null = new Date(publishedAt.getTime() + 30 * 24 * 60 * 60 * 1000);
    const statusRoll = rng();
    if (statusRoll < 0.05) {
      status = 'PENDING_REVIEW';
    } else if (statusRoll < 0.1) {
      status = 'EXPIRED';
      expiresAt = new Date(publishedAt.getTime() + intBetween(1, 20) * 24 * 60 * 60 * 1000);
    } else if (statusRoll < 0.15) {
      status = 'CLOSED';
    }

    const employerLocationId = (
      await prisma.employerLocation.findFirstOrThrow({ where: { employerId: employerRef.employerId } })
    ).id;
    // upsert (không phải create-if-missing) - đặc tả "regenerate 3.000 synthetic jobs" nghĩa là mỗi
    // lần chạy lại seed với generator đã cập nhật (vd. benchmark lương mới) PHẢI ghi đè lại dữ liệu
    // của các dòng đã tồn tại, không được bỏ qua (skip) như trước - nếu không mọi hiệu chỉnh salary
    // tier sẽ không bao giờ phản ánh vào DB một khi 3000 tin đã được tạo lần đầu.
    const jobData = {
      employerId: employerRef.employerId,
      employerLocationId,
      categoryId: categoryByName.get(categoryName)!,
      cityId: employerRef.cityId,
      areaId: employerRef.areaId,
      latitude: employerRef.latitude,
      longitude: employerRef.longitude,
      title,
      description: randomDescription(),
      benefits: pickN(BENEFITS_POOL, intBetween(2, 4)).join(', '),
      headcount: intBetween(1, 5),
      employmentType,
      shifts: randomShifts(employmentType),
      salaryMin,
      salaryMax,
      salaryUnit,
      requiredExperience: pick(REQUIRED_EXPERIENCE_WEIGHTS),
      isUrgent: chance(0.1),
      status,
      publishedAt,
      expiresAt,
      sourceType: 'SYNTHETIC' as const,
      sourceName: 'synthetic',
      sourceJobId,
      sourcePublishedAt: publishedAt,
      importedAt: now,
    };
    await prisma.job.upsert({
      where: { sourceName_sourceJobId: { sourceName: 'synthetic', sourceJobId } },
      create: jobData,
      update: jobData,
    });
  }

  const [employerCount, seekerCount, jobCount] = await Promise.all([
    prisma.employerProfile.count({ where: { user: { email: { endsWith: '@viecnhatrang.internal' } } } }),
    prisma.jobSeekerProfile.count({ where: { user: { email: { endsWith: '@viecnhatrang.internal' } } } }),
    prisma.job.count({ where: { sourceType: 'SYNTHETIC' } }),
  ]);

  console.log(
    `[seed:synthetic] Hoàn tất. Tổng hiện có trong DB: ${employerCount} synthetic employers, ${seekerCount} synthetic seekers, ${jobCount} synthetic jobs.`,
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
