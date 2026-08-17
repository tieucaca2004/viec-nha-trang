# VIỆC NHA TRANG

**Tìm việc gần bạn. Tuyển người thật. Lương rõ ràng. Ứng tuyển 1 chạm.**

Local job marketplace kết nối người tìm việc và nhà tuyển dụng tại Nha Trang, Khánh Hòa (V1). Xem đầy đủ đặc tả sản phẩm và các quyết định kiến trúc tại [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Cấu trúc repo

```
apps/
  backend/   NestJS REST API + PostgreSQL (Prisma)
  mobile/    Flutter app (Android + iOS) - người tìm việc & nhà tuyển dụng
  admin/     Next.js admin CMS
docs/
  ARCHITECTURE.md   Phân tích kiến trúc, tech stack, DB, API, auth, RBAC (đặc tả mục 48)
```

## Yêu cầu

- Node.js 20+, PostgreSQL 14+
- Flutter 3.22+ (để build mobile)

## Chạy backend (development)

```bash
cd apps/backend
cp .env.example .env        # sửa DATABASE_URL trỏ tới Postgres của bạn
npm install
npm run prisma:migrate      # tạo schema
npm run prisma:seed         # seed thành phố Nha Trang, khu vực, danh mục ngành nghề
npm run start:dev           # http://localhost:3000/api/v1
```

Trong development, OTP được log ra console (`ConsoleSmsProvider`) thay vì gửi SMS thật — xem `SMS_PROVIDER` trong `.env`.

## Chạy admin CMS

```bash
cd apps/admin
cp .env.example .env.local
npm install
npm run dev                 # http://localhost:3001 (mặc định 3000, đổi nếu trùng port backend)
```

Đăng nhập admin dùng số điện thoại đã có role `ADMIN` trong DB (gán trực tiếp qua Prisma Studio hoặc migration, chưa có UI tự cấp quyền admin ở V1 vì lý do bảo mật).

## Chạy mobile app

```bash
cd apps/mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1   # 10.0.2.2 cho Android emulator
```

Build release:

```bash
flutter build apk --dart-define=API_BASE_URL=https://api.viecnhaTrang.com/api/v1
flutter build ios --dart-define=API_BASE_URL=https://api.viecnhaTrang.com/api/v1
```

## Môi trường

Tách `development` / `staging` / `production` qua file `.env.<environment>` ở từng app (đặc tả mục 48). Không commit `.env` thật — chỉ commit `.env.example`.

## Phạm vi đã triển khai

Xem mục "Phạm vi triển khai" trong [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) để biết chính xác những gì thuộc MVP (Phase 1) và những gì để dành cho Phase 2-4 theo roadmap gốc.
