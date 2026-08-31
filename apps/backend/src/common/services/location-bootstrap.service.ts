import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

// 17 phường của Nha Trang - danh sách gốc trước khi Job Hunter thêm 3 phường bổ sung
// (Vĩnh Trường/Phương Sài/Ngọc Hiệp) vào prisma/seed.ts. KHÔNG đổi tên/chính tả, KHÔNG thêm/bớt.
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

// Giống hệt slugify() trong prisma/seed.ts (không tách ra util dùng chung để tránh đổi file
// ngoài phạm vi cho phép) - cùng thuật toán đảm bảo slug khớp với Area đã seed sẵn, không tạo
// bản ghi trùng lặp với cách viết slug khác.
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

// Root cause của "GET /areas trả []" khi database chưa từng chạy seed (staging/APK mới cài đặt
// trên máy chưa migrate+seed thủ công): không có cơ chế nào tự đảm bảo City "nha-trang" + Area
// tồn tại ngoài việc chạy `prisma db seed` bằng tay. Bootstrap tối thiểu, idempotent, chạy đúng
// 1 lần lúc app khởi động - KHÔNG thay thế seed.ts (seed.ts vẫn còn nguyên, vẫn seed thêm
// category/tài khoản mẫu), chỉ đảm bảo phần tối thiểu để Employer Location flow không bao giờ
// gặp "chưa có dữ liệu khu vực" chỉ vì DB rỗng.
@Injectable()
export class LocationBootstrapService implements OnModuleInit {
  private readonly logger = new Logger(LocationBootstrapService.name);

  constructor(private readonly prisma: PrismaService) {}

  async onModuleInit() {
    // Không chạy trong môi trường test - test suite (unit/e2e) tự quản lý dữ liệu DB test của
    // riêng nó (xem test/*.e2e-spec.ts, .env.test), bootstrap chạy song song ở đây có thể tạo
    // race/side effect ngoài ý muốn với các test case giả định DB test sạch.
    if (process.env.NODE_ENV === 'test' || process.env.DATABASE_URL?.includes('_test')) {
      return;
    }

    try {
      await this.bootstrap();
    } catch (error) {
      // Bootstrap lỗi (vd DB chưa sẵn sàng lúc app start, mất kết nối thoáng qua) KHÔNG được làm
      // app crash - toàn bộ API khác (auth, jobs, ...) không phụ thuộc bootstrap này để hoạt động.
      this.logger.error(
        `Bootstrap City/Area Nha Trang thất bại - GET /areas có thể tạm thời trả về danh sách rỗng cho tới khi seed thủ công hoặc app khởi động lại thành công. Lỗi: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    }
  }

  private async bootstrap() {
    const city = await this.prisma.city.upsert({
      where: { slug: 'nha-trang' },
      update: {},
      create: { name: 'Nha Trang', slug: 'nha-trang', isActive: true },
    });

    for (const name of NHA_TRANG_AREAS) {
      const slug = slugify(name);
      await this.prisma.area.upsert({
        where: { cityId_slug: { cityId: city.id, slug } },
        update: { isActive: true },
        create: { cityId: city.id, name, slug, isActive: true },
      });
    }

    this.logger.log(`Bootstrap City "nha-trang" + ${NHA_TRANG_AREAS.length} Area hoàn tất.`);
  }
}
