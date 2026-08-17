# DATABASE — VIỆC NHA TRANG

Nguồn sự thật là [`apps/backend/prisma/schema.prisma`](../apps/backend/prisma/schema.prisma).
Tài liệu này tóm tắt để dễ đọc — nếu lệch với schema thật, schema thắng. Migration đầu tiên:
`apps/backend/prisma/migrations/20260817083932_init/`.

PostgreSQL, quản lý qua Prisma. 21 bảng, tất cả có `created_at`/`updated_at`; các bảng dữ liệu
người dùng quan trọng có `deleted_at` (soft delete: `users`, `employer_locations`, `jobs`).

## Sơ đồ quan hệ (rút gọn)

```
cities 1──n areas
users 1──1 job_seeker_profiles
users 1──1 employer_profiles
employer_profiles 1──n employer_locations
employer_locations n──1 areas/cities
employer_profiles 1──n jobs
employer_locations 1──n jobs
job_categories 1──n jobs
areas/cities 1──n jobs
job_seeker_profiles 1──n applications
jobs 1──n applications
users 1──n saved_jobs, notifications, reports (là reporter), audit_logs (là actor)
jobs 1──n saved_jobs
reviews: reviewer_user → users; employer/job_seeker mục tiêu là optional FK (2 chiều)
reports: polymorphic qua target_type + job_id/review_id/target_user_id
employer_profiles 1──n subscriptions n──1 packages; subscriptions 1──n payments
```

## Bảng theo nhóm chức năng

### Đa khu vực (§31/§3 — không hard-code Nha Trang)
- **cities** — `id, name, slug, is_active`. V1 chỉ seed 1 row (Nha Trang) nhưng không có gì
  trong code phụ thuộc cứng vào giá trị này.
- **areas** — thuộc 1 city (`city_id`), unique theo `(city_id, slug)`, index `city_id`.

### Tài khoản & vai trò (§5/§8)
- **users** — `phone` (unique), `email` (unique), `password_hash` (không dùng ở V1, luôn `null`,
  **không bao giờ serialize ra API** — xem `docs/SECURITY.md`), `roles` (mảng enum, 1 user có
  thể vừa `JOB_SEEKER` vừa `EMPLOYER`), `is_banned`, `deleted_at`.
- **refresh_tokens** — hash của refresh token (không lưu plaintext), có `revoked_at` để thu hồi.
- **otp_codes** — hash mã OTP, `attempts`, `expires_at`, `consumed_at` — chống replay/spam.

### Hồ sơ người tìm việc (§11/§12)
- **job_seeker_profiles** — 1-1 với `users`. `desired_category_id`, `area_id`, `latitude/longitude`
  optional (GPS không bắt buộc). `is_looking_now` = toggle "Tôi đang cần việc ngay". Index trên
  `area_id`, `desired_category_id` (dùng cho matching/filter).

### Nhà tuyển dụng (§12/§13)
- **employer_profiles** — 1-1 với `users`. `verification_level` enum
  (`UNVERIFIED → PHONE_VERIFIED → BUSINESS_VERIFIED → TRUSTED`), `rating_avg`/`rating_count`
  cập nhật khi có review mới.
- **employer_locations** — 1 employer có nhiều cơ sở, mỗi cơ sở có `city_id`/`area_id`/
  `latitude`/`longitude` riêng. Index `employer_id`, `area_id`.

### Danh mục ngành nghề (§14)
- **job_categories** — `slug` unique, `sort_order`, `is_active`. Admin CRUD được (không
  hard-code danh sách vào UI).

### Tin tuyển dụng (§6/§10/§15/§16 gốc)
- **jobs** — trường bắt buộc: `salary_min`, `salary_max`, `salary_unit`, `employment_type`,
  `shifts[]`. Counter đếm ngay trên row (`view_count`, `application_count`, `contacted_count`,
  `interview_count`, `hired_count`) — không phải global counter bị hàng nghìn client tranh ghi
  (mỗi update là `UPDATE jobs SET x = x + 1 WHERE id = ...`, khóa row đơn, không khóa bảng).
  Index: `[area_id, status]`, `[category_id, status]`, `[employer_id]` — khớp các truy vấn tìm
  kiếm/lọc/quản lý tin thực tế.

### Ứng tuyển (§21/§22 mới, §11/§16 gốc)
- **applications** — unique `(job_id, job_seeker_id)` → **chống spam apply trùng ở tầng DB**,
  không chỉ ở tầng service. `status` theo state machine
  `NEW → VIEWED → CONTACTED → INTERVIEW → HIRED | NOT_SUITABLE | NO_SHOW`. `match_score`
  (0-100) lưu tại thời điểm apply. Index `[job_seeker_id]`, `[job_id, status]`.
- **saved_jobs** — unique `(user_id, job_id)` chống lưu trùng.

### Đánh giá & báo cáo (§27/§28)
- **reviews** — 2 chiều (`reviewer_type` = `JOB_SEEKER` hoặc `EMPLOYER`), có thể gắn với
  `application_id` cụ thể để xác nhận "đã thực sự làm việc" trước khi cho review (service layer
  chặn nếu `application.status != HIRED`). `criteria_scores` là JSON cho các tiêu chí phụ.
- **reports** — polymorphic (`target_type` = `JOB`/`REVIEW`/`USER`), `reason` enum đầy đủ theo
  §27 (fake job, scam, sai lương, sai địa điểm, thu phí ứng viên, spam...).

### Thông báo (§23)
- **notifications** — ghi vào DB mỗi sự kiện quan trọng (đơn mới, đổi trạng thái...). Index
  `[user_id, read_at]` cho query "chưa đọc" nhanh. Push FCM thật gắn thêm ở tầng service (xem
  `docs/PLAN.md` §9) — bảng này không đổi khi thêm push, chỉ là thêm 1 side-effect khi insert.

### Gói trả phí & thanh toán (§38, khung sẵn — chưa implement thật)
- **packages**, **subscriptions**, **payments** — khung dữ liệu đã có (loại gói, trạng thái,
  provider thanh toán như VNPay/MoMo/ZaloPay/IAP), nhưng **chưa có tích hợp cổng thanh toán
  thật** — nằm ngoài phạm vi các phase đã làm, xem `docs/ROADMAP.md`.

### Vận hành (§29/§34/§37)
- **settings** — key-value JSON, admin chỉnh cấu hình hệ thống không cần deploy lại.
- **audit_logs** — ghi mọi hành động quan trọng của admin (`user.ban`, `employer.verify`,
  `job.setStatus`, `report.resolve`, ...), index `[target_type, target_id]`.

## Vì sao không có hotspot kiểu Firestore (§32 gốc)

- Không có 1 document/row duy nhất bị hàng nghìn client ghi đồng thời. Mỗi job, mỗi application,
  mỗi notification là 1 row độc lập.
- Counter (view/application/contacted/interview/hired count) nằm trên chính row `jobs`, update
  bằng increment nguyên tử (`{ increment: 1 }` trong Prisma → `UPDATE ... SET x = x + 1`), khóa
  ở mức row trong PostgreSQL (MVCC), không khóa toàn bảng.
- Index được thiết kế theo truy vấn thật (list jobs theo khu vực+trạng thái, theo danh mục+trạng
  thái, theo employer), không tạo index tràn lan.
