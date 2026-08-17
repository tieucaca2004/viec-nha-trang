# VIỆC NHA TRANG — Kiến trúc hệ thống (V1 MVP)

Tài liệu này thực hiện yêu cầu ở mục 48 của đặc tả: phân tích, đề xuất kiến trúc, tech stack, database, API, auth, role/permission, mobile navigation, admin CMS, dependency — trước khi code.

## 1. Phạm vi triển khai (bám sát mục 37)

Repo này triển khai **PHASE 1 — MVP** của roadmap (mục 43):

- Mobile app (Android + iOS) cho Người tìm việc và Nhà tuyển dụng
- Backend REST API
- PostgreSQL database (schema hỗ trợ đa khu vực ngay từ đầu — mục 31)
- Authentication (SĐT + OTP, khung sẵn cho Google/Apple Sign-In)
- Đăng tin, tìm việc, bộ lọc, ứng tuyển 1 chạm, quản lý ứng viên
- Push notification (khung tích hợp FCM/APNs)
- Admin CMS tối thiểu (Users, Employers, Jobs, Applications, Reports, Categories, Areas, Verification)

**Không** triển khai ở V1 (khung kiến trúc đã chừa chỗ mở rộng, xem mục 9):
AI tạo tin, matching-score nâng cao (điểm số cơ bản có sẵn, học máy thì chưa), cổng thanh toán thật (chỉ có bảng `payments`/`subscriptions` + interface), bản đồ nâng cao, đa ngôn ngữ, đa thành phố (schema có nhưng chỉ seed Nha Trang).

## 2. Tech stack

| Layer | Lựa chọn | Lý do |
|---|---|---|
| Mobile | **Flutter** (Dart) | Một codebase cho Android + iOS, hiệu năng gần native, phù hợp UI đơn giản/nhanh theo mục 4 |
| Backend API | **NestJS** (TypeScript, Node.js) | Kiến trúc module hóa rõ ràng (mục 48: modular/maintainable), RBAC dễ triển khai qua Guards, hệ sinh thái lớn |
| Database | **PostgreSQL** | Quan hệ rõ ràng, hỗ trợ PostGIS sau này cho geo-query, JSON columns cho các trường linh hoạt |
| ORM | **Prisma** | Migration rõ ràng, type-safe, dễ soft-delete/audit |
| Auth | JWT (access + refresh) + OTP qua SMS provider (interface, chưa gắn nhà cung cấp cụ thể) | Tách được provider SMS sau này (Twilio/ESMS/Speed SMS...) |
| Push notification | Firebase Cloud Messaging (Android + iOS) | Chuẩn cross-platform |
| Admin CMS | **Next.js** (React) tối giản, gọi thẳng admin REST API | Không cần app riêng phức tạp ở V1 |
| File/ảnh | Object storage interface (S3-compatible), nén ảnh phía client trước khi upload | mục 34 hiệu năng |
| Thanh toán | Interface `PaymentProvider` (VNPay/MoMo/ZaloPay/IAP implement sau) | mục 28: không hard-code 1 cổng |

## 3. Kiến trúc tổng thể

```
apps/
  backend/     -> NestJS REST API (modular theo domain)
  mobile/      -> Flutter app (Android + iOS)
  admin/       -> Next.js admin CMS
docs/          -> tài liệu kiến trúc, API
```

Backend tách module theo domain, mỗi module có controller/service/DTO riêng, dùng chung Prisma client:

```
auth, users, job-seekers, employers, jobs, categories, areas,
applications, saved-jobs, reviews, reports, notifications,
subscriptions, payments, admin
```

Nguyên tắc: **Nha Trang không hard-code** — mọi truy vấn theo khu vực đi qua bảng `cities` → `areas`, seed data chỉ chèn Nha Trang nhưng code không biết tên "Nha Trang" ở tầng logic (chỉ ở tầng seed/config).

## 4. Database schema (tóm tắt — xem `apps/backend/prisma/schema.prisma`)

Các bảng chính đúng theo mục 30, mở rộng đa khu vực theo mục 31:

- `cities`, `areas` (area thuộc city; Nha Trang là 1 row trong `cities`)
- `users` (tài khoản gốc — 1 user có thể vừa là job_seeker vừa employer, theo mục 5)
- `job_seekers` (hồ sơ ứng viên, 1-1 với users)
- `employers` (hồ sơ nhà tuyển dụng/doanh nghiệp, 1-1 với users)
- `employer_locations` (1 employer có nhiều cơ sở/địa điểm, mỗi location có lat/lng/area)
- `job_categories`
- `jobs` (thuộc employer_location, category, area, city; có lat/lng riêng để không phụ thuộc geo của location)
- `applications` (job_seeker ứng tuyển job, có state machine trạng thái theo mục 16)
- `saved_jobs`
- `reviews` (2 chiều: job_seeker→employer, employer→job_seeker, dùng `reviewer_type`)
- `reports` (báo cáo tin/người dùng, polymorphic qua `target_type`/`target_id`)
- `notifications`
- `subscriptions`, `packages`, `payments` (khung gói trả phí + thanh toán)
- `settings` (cấu hình hệ thống, admin sửa được)
- `audit_logs` (mọi hành động admin quan trọng)

Tất cả bảng có `created_at`, `updated_at`; các bảng dữ liệu người dùng quan trọng có `deleted_at` (soft delete) — đúng mục 30.

## 5. Authentication & Role/Permission

- Đăng nhập: SĐT + OTP (bắt buộc V1), Google Sign-In và Apple Sign-In (interface sẵn, bật bằng feature flag).
- 1 bảng `users` duy nhất, có cột `roles` (mảng: `job_seeker`, `employer`, `admin`) — **không tách 2 hệ thống tài khoản** (đúng mục 5). Một user có thể có cả hồ sơ job_seeker lẫn employer.
- JWT access token (ngắn hạn) + refresh token (dài hạn, lưu hash trong DB để revoke được).
- RBAC bằng NestJS Guards (`RolesGuard`) đọc từ `roles` trên JWT payload, kiểm tra lại quyền sở hữu resource ở service layer (vd. employer chỉ sửa được job của chính mình) — **server luôn là nguồn sự thật**, client không có quyền ghi trực tiếp (mục 32).
- Rate limiting cho endpoint OTP và các endpoint ghi dữ liệu (chống spam, mục 35).

## 6. API design

REST, versioned `/api/v1`. Chuẩn response `{ data, meta, error }`. Pagination kiểu cursor/limit cho job list (mục 34: không tải toàn bộ danh sách).

Nhóm endpoint chính (chi tiết trong `docs/API.md`):

- `POST /auth/otp/request`, `POST /auth/otp/verify`, `POST /auth/google`, `POST /auth/apple`, `POST /auth/refresh`
- `GET/PATCH /me`, `GET/PATCH /me/job-seeker-profile`, `GET/PATCH /me/employer-profile`
- `GET /jobs` (filter: category, area, radius+lat/lng, shift, salary, employment_type, urgent), `GET /jobs/:id`, `POST /jobs` (employer), `PATCH /jobs/:id`, `POST /jobs/:id/close`, `POST /jobs/:id/renew`, `POST /jobs/:id/boost`
- `POST /jobs/:id/apply`, `GET /applications/me` (job seeker), `GET /employer/jobs/:id/applications`, `PATCH /applications/:id/status`
- `POST /saved-jobs/:jobId`, `DELETE /saved-jobs/:jobId`, `GET /saved-jobs`
- `GET /categories`, `GET /areas?cityId=`
- `POST /reviews`, `GET /reviews?targetType=&targetId=`
- `POST /reports`
- `GET /notifications`, `PATCH /notifications/:id/read`
- Admin: `/admin/users`, `/admin/employers`, `/admin/jobs`, `/admin/applications`, `/admin/reports`, `/admin/categories`, `/admin/areas`, `/admin/verification/:employerId`

## 7. Mobile navigation (mục 7)

Bottom nav 5 mục cho job seeker: Việc làm, Đã lưu, Ứng tuyển, Thông báo, Cá nhân.
Nếu user có role employer: thêm nút nổi "+ ĐĂNG TUYỂN" và tab Cá nhân đổi thành khu vực quản lý (Tin của tôi / Ứng viên).

## 8. Môi trường

`development`, `staging`, `production` tách bằng file `.env.*`, không commit secret thật. Seed data (categories, areas Nha Trang) chạy qua Prisma seed script — đây không phải mock data thay database, mà là dữ liệu khởi tạo hệ thống thật (danh mục/khu vực), đúng tinh thần mục 48.

## 9. Điểm mở rộng đã chừa sẵn

- `PaymentProvider` interface — cắm VNPay/MoMo/ZaloPay/IAP sau, không đổi schema.
- `MatchScoreService` — hiện tính điểm cơ bản theo rule (ngành, khu vực, khoảng cách, ca, lương); nâng cấp AI/ML sau không đổi API contract.
- `jobs`/`employer_locations` có `city_id`, `area_id`, `lat`, `lng` ngay từ đầu — thêm thành phố mới chỉ là thêm row vào `cities`/`areas`, không sửa schema hay logic.
- `AiJobDraftService` — endpoint `POST /ai/job-draft` (stub trả lỗi 501 "not implemented" ở V1) theo đúng mục 14: AI chỉ **gợi ý**, không tự đăng.
