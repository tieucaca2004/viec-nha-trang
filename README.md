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

## Chạy PostgreSQL (development)

```bash
docker compose up -d        # PostgreSQL 16 + volume + healthcheck (xem docker-compose.yml)
```

Nếu môi trường không kéo được Docker image, dùng PostgreSQL cài trực tiếp - chỉ cần tạo database
`viec_nha_trang` và cập nhật `DATABASE_URL` cho khớp.

## Chạy backend (development)

```bash
cd apps/backend
cp .env.example .env        # sửa DATABASE_URL trỏ tới Postgres của bạn
npm install
npm run prisma:migrate      # tạo schema (migration đầu: 20260817083932_init)
npm run prisma:seed         # seed thành phố Nha Trang, khu vực, danh mục ngành nghề + tài khoản test
npm run start:dev           # http://localhost:3000/api/v1
```

Trong development, OTP được log ra console (`ConsoleSmsProvider`) thay vì gửi SMS thật — xem `SMS_PROVIDER` trong `.env`.

Swagger docs (tự sinh từ DTO thật qua `@nestjs/swagger` CLI plugin): `http://localhost:3000/api/docs`.

Tài khoản seed sẵn để test (KHÔNG phải dữ liệu người dùng thật):

| Vai trò | SĐT | Ghi chú |
|---|---|---|
| Admin | `0900000001` | role `ADMIN` |
| Employer | `0900000002` | "Hủ Tiếu Xào A Tiểu", 1 cơ sở, 2 tin mẫu |
| Job seeker | `0900000003` | hồ sơ cơ bản, ngành mong muốn "Phục vụ" |

### Chạy E2E test

```bash
createdb viec_nha_trang_test        # 1 lần, DB test riêng biệt với dev/production
cp .env.example .env.test           # sửa DATABASE_URL trỏ tới viec_nha_trang_test
npm run test:e2e                    # tự động migrate DB test rồi chạy 4 suite (job seeker/employer/admin/security)
```

Xem `docs/PHASE2-REPORT.md` để biết kết quả lần chạy gần nhất và các bug đã tìm-và-sửa qua E2E thật.

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

Kết quả Phase 2 (backend thật + PostgreSQL thật + E2E core flow): [`docs/PHASE2-REPORT.md`](docs/PHASE2-REPORT.md).
Các hạng mục phát hiện nhưng cố tình chưa làm (ngoài phạm vi): [`docs/ROADMAP.md`](docs/ROADMAP.md).
