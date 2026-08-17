# ENVIRONMENT — VIỆC NHA TRANG

3 môi trường: `development`, `staging`, `production` — tách bằng file `.env.<environment>` per
app, không bao giờ commit giá trị thật. Chỉ `.env.example` được commit.

## apps/backend

Nguồn sự thật: [`apps/backend/.env.example`](../apps/backend/.env.example).

| Biến | Bắt buộc | Mô tả |
|---|---|---|
| `NODE_ENV` | có | `development` \| `staging` \| `production` — quyết định file `.env.<NODE_ENV>` nào được `ConfigModule` nạp thêm |
| `PORT` | có | Cổng HTTP, Cloud Run tự set `PORT` runtime — code đã đọc `process.env.PORT` nên tương thích sẵn |
| `DATABASE_URL` | có | Connection string PostgreSQL. Production: Cloud SQL qua Unix socket/Auth Proxy (xem `docs/DEPLOYMENT.md`) |
| `JWT_ACCESS_SECRET` / `JWT_ACCESS_EXPIRES_IN` | có | Ký access token. Production: lấy từ Secret Manager, không đặt trong file |
| `JWT_REFRESH_SECRET` / `JWT_REFRESH_EXPIRES_IN` | có | Ký refresh token |
| `SMS_PROVIDER` | có | `console` (dev, log OTP ra log) — production cần implement thêm provider thật (chưa có ở phase này, xem ROADMAP) |
| `OTP_TTL_SECONDS` / `OTP_MAX_ATTEMPTS` | có | Chống brute-force OTP |
| `OTP_REQUEST_THROTTLE_LIMIT` / `OTP_VERIFY_THROTTLE_LIMIT` | không | Mặc định 3/5 mỗi phút mỗi IP. Chỉ nới ở `.env.test` |
| `THROTTLE_TTL` / `THROTTLE_LIMIT` | có | Rate limit toàn cục |
| `STORAGE_ENDPOINT` / `STORAGE_BUCKET` / `STORAGE_ACCESS_KEY` / `STORAGE_SECRET_KEY` | không (chưa dùng) | Dành cho upload ảnh (avatar, ảnh cơ sở) qua Google Cloud Storage — interface đã có, chưa có endpoint upload thật, xem ROADMAP |
| `FCM_PROJECT_ID` | không | Project Firebase **riêng** `viec-nha-trang` (KHÔNG dùng chung `pshop-music`) dùng cho push notification |
| `FCM_SERVICE_ACCOUNT_JSON` | không | Nội dung JSON service account (production: Secret Manager, KHÔNG commit file `.json` vào repo) |
| `FCM_SERVICE_ACCOUNT_FILE` | không | Đường dẫn tới file service account (dev local, thay thế cho biến JSON ở trên) |

Không đặt cả `FCM_SERVICE_ACCOUNT_JSON` lẫn `FCM_SERVICE_ACCOUNT_FILE`/không đặt gì cả → push
notification tự động no-op (log cảnh báo, không throw) — app vẫn chạy bình thường ở dev không
cần Firebase.

### apps/backend/.env.test (chỉ dùng cho `npm run test:e2e`)

Trỏ `DATABASE_URL` vào **database test riêng biệt** (`viec_nha_trang_test`), không bao giờ
trùng với dev/production — `test/global-setup.ts` chủ động từ chối chạy nếu `DATABASE_URL`
không chứa `_test` trong tên, để tránh lỡ tay xóa dữ liệu thật.

## apps/admin

| Biến | Mô tả |
|---|---|
| `NEXT_PUBLIC_API_BASE_URL` | URL backend (`http://localhost:3000/api/v1` dev, URL Cloud Run production) |

## apps/mobile

Truyền qua `--dart-define` lúc build (không phải file `.env` vì Flutter build-time, không phải
runtime env):

| Define | Mô tả |
|---|---|
| `API_BASE_URL` | URL backend |
| `APP_ENV` | `development`/`staging`/`production` |
| `DEFAULT_CITY_SLUG` | Mặc định `nha-trang` — không hard-code tên thành phố vào logic (§3) |

## Nguyên tắc

- Không bao giờ commit `.env`, `.env.production`, `.env.staging`, hay bất kỳ file chứa secret
  thật — `.gitignore` đã chặn `apps/backend/.env*` (trừ `.env.example`) và tương tự cho admin.
- Production/staging secrets sống trong **Google Secret Manager**, không trong file trên đĩa —
  Cloud Run đọc secret qua biến môi trường được mount tại deploy time (xem `docs/DEPLOYMENT.md`).
- Không có secret nào của `pshop-music` được dùng ở đây — project Firebase, GCP project,
  database, mọi credential đều độc lập hoàn toàn theo yêu cầu §1.
