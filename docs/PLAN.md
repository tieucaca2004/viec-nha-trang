# VIỆC NHA TRANG — Kế hoạch kiến trúc (trước khi mở rộng scale/infra)

Tài liệu này thực hiện yêu cầu §58 của master prompt: trình bày kiến trúc/kế hoạch trước khi
thực hiện thay đổi lớn. Nó cũng ghi lại quyết định đã được xác nhận với người dùng ở đầu phase
này: **giữ backend NestJS + PostgreSQL + Prisma đã có (đã qua 2 phase, có migration thật, seed
idempotent, 34 E2E test PASS) thay vì viết lại toàn bộ sang Firebase/Firestore**, và điều chỉnh
phần hạ tầng/triển khai để vẫn thỏa mãn tinh thần "không thuê VPS riêng, serverless/managed,
autoscaling" của master prompt.

## 0. Vì sao không rewrite sang Firestore

Master prompt yêu cầu Firestore, nhưng:

- Backend hiện tại là NestJS + PostgreSQL + Prisma, đã có migration thật, RBAC, validation,
  Swagger phản ánh DTO thật, và **34 E2E test PASS** qua 2 lần chạy liên tiếp (job seeker,
  employer, admin, security — bao gồm cả kiểm tra IDOR, ownership, JWT giả mạo, SQL injection).
- Rewrite sang Firestore nghĩa là bỏ toàn bộ phần đó và viết lại từ đầu: security rules thay
  guard, Cloud Functions thay controller, denormalization thủ công thay JOIN, không có
  migration/rollback thật.
- Người dùng đã xác nhận: **giữ NestJS + PostgreSQL**, triển khai theo hướng managed/serverless
  (Cloud Run + Cloud SQL) thay vì VPS tự quản, để vẫn đạt được mục tiêu thật sự đằng sau yêu cầu
  Firestore (không vận hành server riêng, autoscale, không phải tự patch OS).
- Điều này không vi phạm nguyên tắc "độc lập hoàn toàn với pshop-music" (§1) — đã xác minh
  bằng `grep` toàn repo, không có tham chiếu nào tới `pshop-music`.

Những phần khác của master prompt (multi-city, scalability, cost control, load testing,
security, matching engine, one-tap apply, verification, report/review...) áp dụng nguyên vẹn
lên stack Postgres — chỉ khác công cụ, không khác nguyên tắc.

## 1. Architecture overview

```
                    ┌─────────────────────┐
                    │   Mobile (Flutter)   │  Android + iOS
                    └──────────┬───────────┘
                               │ HTTPS (REST + JWT)
                    ┌──────────▼───────────┐
                    │  Cloud Run (NestJS)   │  stateless, autoscale 0→N
                    │  apps/backend         │
                    └──────────┬───────────┘
                               │ Cloud SQL Auth Proxy (private IP)
                    ┌──────────▼───────────┐
                    │  Cloud SQL PostgreSQL │  managed, automated backup
                    └───────────────────────┘

     ┌─────────────────┐        ┌────────────────────┐
     │ Firebase Cloud    │◄──────┤  Cloud Run (NestJS)  │  push notifications
     │ Messaging (FCM)    │      │  NotificationsService│  (project độc lập viec-nha-trang,
     └─────────────────┘        └────────────────────┘   KHÔNG dùng Firestore/Auth)

     ┌─────────────────┐        ┌────────────────────┐
     │  Next.js Admin CMS │◄────┤  cùng Cloud Run API   │
     └─────────────────┘        └────────────────────┘
```

- **Backend là 1 stateless service** (không session in-memory, JWT stateless trừ refresh-token
  hash lưu DB để revoke được) → chạy được nhiều instance song song trên Cloud Run.
- **Firebase chỉ dùng cho FCM** (push notification) — không dùng Firebase Auth, không dùng
  Firestore, không dùng Firebase Storage ở giai đoạn này. Project Firebase (nếu tạo) phải là
  project riêng `viec-nha-trang`, tách biệt hoàn toàn khỏi `pshop-music` (đúng §1/§4).
- **Object storage** (avatar, ảnh cơ sở) dùng Google Cloud Storage bucket riêng (S3-compatible
  interface đã có sẵn trong `.env.example`), không phải Firebase Storage — tránh phụ thuộc thêm
  vào Firebase ngoài phần bắt buộc (push).

## 2. Tech stack (giữ nguyên phase 1-2, bổ sung phần triển khai)

| Layer | Lựa chọn | Thay đổi so với phase 1-2 |
|---|---|---|
| Mobile | Flutter | Không đổi |
| Backend | NestJS + TypeScript | Không đổi |
| Database | PostgreSQL qua Prisma | Không đổi cấu trúc; **triển khai** chuyển từ "Postgres tự cài" sang Cloud SQL |
| Deployment | **Cloud Run** (container, autoscale, scale-to-zero khi rảnh) | Mới — thay cho "chạy trên VPS" |
| Push notification | **Firebase Cloud Messaging** (project riêng) | Mới — hiện thực hóa phần đã có interface sẵn từ phase 1 |
| Object storage | Google Cloud Storage | Mới — endpoint đã có sẵn trong `.env.example`, giờ điền giá trị thật |
| Admin CMS | Next.js | Không đổi; deploy Cloud Run hoặc Vercel-style static+API tùy hạ tầng thật khi có |
| CI | GitHub Actions | Mới — lint/build/test tự động trên PR |
| Load testing | k6 | Mới — script + kế hoạch, xem `docs/LOAD_TESTING.md` |
| Monitoring | Google Cloud Monitoring + Cloud Logging (Cloud Run tự động xuất log/metric) | Mới — không cần cài thêm agent vì Cloud Run có sẵn |
| Error tracking | Sentry (self-hosted-free tier hoặc SaaS free tier) HOẶC Cloud Error Reporting | Đề xuất, chưa triển khai — xem Risks |

## 3. Repository structure (không đổi, đã đúng)

```
apps/
  backend/   NestJS REST API (đã có: modules, prisma schema+migration, 34 e2e test)
  mobile/    Flutter app
  admin/     Next.js admin CMS
docs/        Toàn bộ tài liệu bắt buộc theo §55
docker-compose.yml   Postgres dev local
Dockerfile (mới)     Build image Cloud Run cho apps/backend
.github/workflows/   CI (mới)
```

## 4. Database schema

Không đổi so với phase 1-2 — 21 bảng, đã có migration `20260817083932_init`, đã review FK/index/
enum/unique constraint (xem `docs/DATABASE.md` mới, phản ánh đúng `prisma/schema.prisma`).
`city_id`/`area_id` đã có sẵn trên `jobs`/`employer_locations` từ đầu (đa thành phố, §31 gốc và
§3 của master prompt này — không hard-code Nha Trang vào logic).

## 5. "Firestore collections" → không áp dụng

Vì giữ Postgres, không có Firestore collection. Các nguyên tắc chống hotspot của §32 (mỗi job
là document riêng, không global counter bị ghi bởi hàng nghìn client, index cho các trường lọc
phổ biến) áp dụng dưới dạng tương đương trong Postgres:

- Mỗi job là 1 row riêng trong bảng `jobs` (không có bảng lưu jobs dạng JSON blob duy nhất).
- Không có "global counter" — các số liệu (`applicationCount`, `viewCount`...) là cột trên
  chính row `jobs`, update qua `UPDATE ... SET x = x + 1` (row-level lock ngắn, không phải một
  document toàn cục bị hàng nghìn client tranh ghi).
- Index đã có cho các truy vấn MVP quan trọng: `[areaId, status]`, `[categoryId, status]`,
  `[employerId]`, `[jobId, status]` trên applications, `[userId, readAt]` trên notifications.
  Xem `docs/DATABASE.md`.
- Không tải toàn bộ `jobs` về client — `JobsService.findMany` đã có `limit`/`offset`
  (mặc định 20, tối đa 50) từ phase 1.

## 6. Security model

Không đổi nguyên tắc từ phase 1-2 (đã pass 11 security E2E test), bổ sung phần hạ tầng:

- JWT (access ngắn hạn + refresh dài hạn, hash lưu DB để revoke) — role đọc lại từ DB mỗi
  request (fix ở phase 2, không tin JWT claim cũ).
- RBAC qua `RolesGuard`, ownership luôn kiểm tra server-side (không tin client gửi `employerId`).
- Input validation qua `class-validator` + `whitelist: true` (đã phát hiện và fix 3 DTO thiếu
  decorator ở phase 2).
- Rate limiting qua `@nestjs/throttler`, đặc biệt route OTP.
- Cloud SQL: **không expose public IP** — Cloud Run kết nối qua Cloud SQL Auth Proxy/Unix
  socket, không cần whitelist IP hay VPC phức tạp cho MVP.
- Secret quản lý qua **Google Secret Manager**, không commit vào repo (đã có `.env.example`
  không chứa secret thật).
- Chi tiết đầy đủ: `docs/SECURITY.md` (mới).

## 7. API architecture

REST `/api/v1`, đã có 45 route thật (xem `docs/API.md` mới, liệt kê từ controller thật, không
phải tài liệu tưởng tượng). Swagger tự sinh từ DTO thật tại `/api/docs`.

## 8. Authentication architecture

Phone OTP (đã hoạt động, verify qua console trong dev). Google/Apple Sign-In: interface đã có,
implement thật (`AuthService.loginWithGoogle/loginWithApple`) là việc **ngoài phạm vi phase
này** — cần Google/Apple OAuth client ID/secret thật, đã ghi vào `docs/ROADMAP.md` từ phase 2,
giữ nguyên trạng thái đó (§40 gốc: không tự ý mở rộng scope).

## 9. Notification architecture

- Trong DB: bảng `notifications` đã có, ghi mỗi khi có sự kiện (ứng tuyển mới, đổi trạng thái...).
- Push thật: tích hợp **Firebase Cloud Messaging** bằng `firebase-admin` SDK ở backend
  (server-to-server, không cần Firebase Auth/Firestore) — xem mục "FCM push notification
  integration" đã triển khai trong phase này. Mobile app cần thêm `deviceToken` vào hồ sơ user
  để nhận push (đã có sẵn dependency `firebase_messaging` trong `pubspec.yaml` từ phase 1,
  nhưng wiring device-token thật ở mobile chưa làm — ghi vào ROADMAP vì cần Flutter SDK để
  build/test, hiện không có trong môi trường này).

## 10. Scalability strategy

Chi tiết: `docs/SCALABILITY.md` (mới). Tóm tắt:

- Cloud Run autoscale theo request, scale-to-zero khi không có traffic (kiểm soát chi phí ở
  quy mô nhỏ, tự động scale lên khi traffic tăng).
- Cloud SQL: bắt đầu ở tier nhỏ (db-custom-1-3840 hoặc tương đương), PgBouncer/Cloud SQL
  connection pooling để tránh cạn kết nối khi nhiều Cloud Run instance cùng mở connection.
  Prisma connection pool giới hạn (`connection_limit` trong `DATABASE_URL`) để không vượt quá
  giới hạn của tier Cloud SQL đang dùng.
- Pagination bắt buộc mọi list endpoint (đã có).
- Đọc nhiều/ghi ít (search, filter, detail) → có thể thêm cache lớp ứng dụng (in-memory LRU
  cho categories/areas gần như tĩnh) khi cần — chưa cần ở MVP vì các bảng này nhỏ (15-17 dòng).
- Không dùng SELECT * tải toàn bộ bảng — mọi truy vấn jobs đều qua `findMany` có `where`+`take`.

## 11. Load testing strategy

Chi tiết + script thật: `docs/LOAD_TESTING.md` (mới, dùng k6). **Trung thực về giới hạn môi
trường**: không có Cloud Run/Cloud SQL instance thật đang chạy trong phiên làm việc này để chạy
load test thật ở quy mô 1.000-5.000 concurrent — script đã viết, chạy được, nhưng cần một môi
trường đã deploy thật để lấy số liệu P95/P99/cost thật. Không tuyên bố đã chạy nếu chưa chạy.

## 12. Cost control strategy

Chi tiết: `docs/COST.md` (mới) — ước tính chi phí Cloud Run + Cloud SQL + FCM theo các mốc
người dùng (1k/10k/50k), nguyên tắc kiểm soát (pagination, không polling, không listener
realtime không cần thiết — đã đúng vì dùng REST, không phải Firestore realtime listener).

## 13. CI/CD strategy

GitHub Actions: lint + typecheck + build + test (unit khi có, e2e cần Postgres service
container) trên mỗi PR cho `apps/backend` và `apps/admin`. Deploy job (build Docker image, push
Cloud Run) được viết dưới dạng workflow **manual/tag-triggered**, không tự động deploy production
vì chưa có GCP project/credentials thật trong môi trường này — ghi rõ trong workflow comment.

## 14. MVP milestones (đối chiếu §54 master prompt)

M1 Foundation, M2 Auth, M3 Job Marketplace, M4 Applications, M5 Employer, M7 Admin, M8 Security,
M9 Testing đã **DONE** từ phase 1-2 (xem `docs/PHASE2-REPORT.md`).

Phase này (gọi là **M-infra**, bổ sung không thay thế M6/M10/M11):
- M6 Notifications: nâng từ "ghi DB" lên "ghi DB + push FCM thật".
- M10 Load Testing: **kế hoạch + script sẵn sàng chạy**, chưa chạy thật (cần môi trường deploy).
- M11 Production Preparation: Dockerfile, deployment guide, CI, cost/scalability docs.

## 15. Risks

- **Không có GCP project thật trong môi trường này** → không thể deploy/test Cloud Run, Cloud
  SQL, FCM thật, hay chạy load test thật. Mọi phần này được chuẩn bị (code/script/docs) nhưng
  cần một người có quyền truy cập GCP console để thực thi và xác nhận số liệu thật.
- **Firebase project cho FCM cần được tạo thủ công** (`viec-nha-trang`, tách biệt `pshop-music`)
  và service account key cần được cấp — không có trong môi trường này, code đọc key qua biến
  môi trường (`FCM_SERVICE_ACCOUNT_JSON` hoặc file path), không hard-code.
- **Google/Apple OAuth chưa implement** — cần client ID/secret thật từ Google Cloud Console/
  Apple Developer, ngoài phạm vi phase này (đã ghi ROADMAP).
- **Flutter SDK không có trong môi trường này** (đã ghi nhận từ phase 2) — phần mobile (device
  token cho FCM, v.v.) không thể build/test ở đây.

## 16. Recommended implementation order (phase này)

1. `docs/DATABASE.md`, `docs/API.md`, `docs/SECURITY.md`, `docs/ENVIRONMENT.md` — tài liệu hóa
   những gì đã có thật (không tốn rủi ro, giá trị ngay).
2. `Dockerfile` + `docs/DEPLOYMENT.md` — chuẩn bị container hóa cho Cloud Run.
3. FCM push notification integration thật (backend-side).
4. `docs/SCALABILITY.md`, `docs/COST.md`, `docs/LOAD_TESTING.md` + k6 script.
5. `docs/TESTING.md`.
6. CI workflow (GitHub Actions).
7. Verify: build + e2e test vẫn PASS sau mọi thay đổi, commit, push.

Không động vào `apps/mobile` hay `apps/admin` ngoài việc đọc để viết docs chính xác (Flutter
SDK không có sẵn; admin không cần thay đổi vì vẫn gọi cùng REST API).
