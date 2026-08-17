# SECURITY — VIỆC NHA TRANG

Ghi lại chính xác các biện pháp bảo mật đã triển khai và đã kiểm chứng (không phải checklist lý
thuyết). Xem `docs/PHASE2-REPORT.md` để biết 11 security E2E test đã PASS thế nào.

## Authentication

- Đăng nhập bằng SĐT + OTP. Mã OTP được hash (scrypt, `src/common/services/hash.util.ts`)
  trước khi lưu DB — **không lưu OTP plaintext**. Có `attempts` counter và `OTP_MAX_ATTEMPTS`
  để chặn brute-force mã OTP.
- Access token JWT ngắn hạn (mặc định 15 phút), refresh token dài hạn (30 ngày) — refresh token
  cũng được hash trước khi lưu DB, có `revoked_at` để thu hồi khi dùng refresh (rotate).
- Rate limiting riêng cho `/auth/otp/request` (mặc định 3/phút/IP) và `/auth/otp/verify`
  (mặc định 5/phút/IP) qua `@nestjs/throttler`, cấu hình được qua env
  (`OTP_REQUEST_THROTTLE_LIMIT`, `OTP_VERIFY_THROTTLE_LIMIT`) — production giữ mặc định thấp,
  môi trường test nới ra để chạy E2E nhanh.

## Authorization (RBAC + ownership)

- Vai trò (`JOB_SEEKER`/`EMPLOYER`/`ADMIN`) đọc **từ DB tại mỗi request** (`JwtStrategy.validate`),
  không tin claim cũ trong JWT — sửa ở Phase 2 sau khi phát hiện qua E2E rằng đổi role không có
  tác dụng ngay nếu tin JWT claim (xem `docs/PHASE2-REPORT.md` mục bug #2).
- `RolesGuard` chặn ở tầng route theo role. Nhưng role đúng không đủ — **ownership luôn được
  kiểm tra lại ở service layer**: employer chỉ sửa/đóng/xem applicant của job **của chính họ**
  (`JobsService`/`ApplicationsService` so `job.employer.userId` với `userId` từ JWT, không phải
  từ body/param client gửi). Đã kiểm chứng bằng E2E: Employer B không thể sửa/đóng job của
  Employer A, không xem được applicant của Employer A, không đổi được trạng thái application của
  Employer A — và dữ liệu thật **không đổi** sau các request 403 đó (kiểm tra bằng Prisma trực
  tiếp trong test, không chỉ status code).
- User bị `isBanned=true` hoặc `deletedAt` khác null → JWT hợp lệ vẫn bị từ chối ngay
  (`UnauthorizedException` trong `JwtStrategy`), không cần đợi token hết hạn.

## Input validation

- `ValidationPipe` toàn cục: `whitelist: true` (loại field lạ), `forbidNonWhitelisted: true`
  (400 nếu client gửi field không khai báo trong DTO), `transform: true`.
- **Bài học Phase 2**: field có `@Type(() => Number)` nhưng thiếu decorator `class-validator`
  (`@IsNumber`/`@IsLatitude`/...) bị chính `whitelist` xóa âm thầm khỏi payload — 3 DTO đã dính
  lỗi này (tọa độ nhà tuyển dụng, tọa độ hồ sơ ứng viên, filter `isUrgent`), đã fix. Bài học cho
  DTO mới: **mọi field nhận từ client phải có ít nhất 1 decorator từ `class-validator`**, không
  chỉ `class-transformer`.
- Test SQL injection cơ bản (`'; DROP TABLE jobs; --` trong ô tìm kiếm) đã chạy qua E2E — an
  toàn vì Prisma luôn dùng parameterized query, không nối chuỗi SQL thủ công ở bất kỳ đâu trong
  codebase.

## Data exposure / privacy

- `passwordHash` (hiện luôn `null` vì V1 không dùng password) **không bao giờ được serialize**
  ra response — cả `/me` lẫn `/admin/users`/`/admin/employers`. Đã fix ở Phase 2 bằng
  `select` tường minh (`src/common/services/safe-select.ts`) sau khi phát hiện field này lọt ra
  response thật qua kiểm tra live, không chỉ đọc code.
- Số điện thoại: chỉ trả về cho chính chủ tài khoản (`/me`) hoặc cho phía có quan hệ hợp lệ
  (employer xem applicant đã ứng tuyển vào job của họ). Không có endpoint public liệt kê số điện
  thoại người dùng khác.
- Response lỗi 403/404 không kèm theo dữ liệu của resource bị từ chối truy cập (đã assert trong
  security E2E test: `res.body.data` phải `undefined` khi bị chặn).

## Rate limiting & anti-spam

- Toàn cục: `ThrottlerModule` (`THROTTLE_TTL`/`THROTTLE_LIMIT`, mặc định 60 request/phút/IP).
- OTP: giới hạn riêng, chặt hơn (xem trên).
- Chống đăng ứng tuyển trùng: unique constraint DB `(job_id, job_seeker_id)` trên bảng
  `applications` — **chặn ở tầng dữ liệu**, không chỉ tầng service (nên kể cả nếu có race
  condition/bug ở service layer sau này, DB vẫn không cho phép trùng).
- Chống lưu job trùng: unique constraint `(user_id, job_id)` trên `saved_jobs`.

## Secrets & environment

- Không commit `.env` thật — chỉ `.env.example` (không chứa secret thật, các giá trị nhạy cảm
  để trống hoặc placeholder rõ ràng như `change-me-access-secret`).
- `.gitignore` chặn mọi `apps/backend/.env*` trừ `.env.example`.
- Kế hoạch production (Cloud Run): secret (JWT secret, DB credential, FCM service account key)
  quản lý qua **Google Secret Manager**, mount vào Cloud Run runtime qua biến môi trường —
  không hard-code, không commit. Chi tiết: `docs/DEPLOYMENT.md`.

## Route debug OTP (chỉ tồn tại ngoài production)

`GET /auth/otp/debug/:phone` được thêm để load test (`apps/backend/loadtest/scenarios.js`) có
thể đăng nhập hàng trăm/hàng nghìn VU tự động mà không cần đọc log server. Đây là bề mặt tấn công
mới nên phải nêu rõ:

- Tự trả `404` nếu `NODE_ENV === 'production'` — kiểm tra tại mỗi request, không chỉ lúc đăng
  ký route, nên không thể "quên tắt" bằng cách chỉ sửa code một chỗ.
- Tự trả `404` nếu `SMS_PROVIDER` đang cấu hình không phải `console` — production luôn phải
  dùng SMS provider thật (không phải `ConsoleSmsProvider`), nên route này tự vô hiệu ở đó dù ai
  đó lỡ để `NODE_ENV` sai.
- Chỉ trả lại mã OTP **vừa được chính tiến trình này "gửi"** (lưu trong bộ nhớ, mất khi restart)
  — không có cách nào dùng route này để lấy OTP của người dùng thật trong production, kể cả nếu
  2 điều kiện chặn ở trên bị vô hiệu hóa nhầm, vì `ConsoleSmsProvider` sẽ không được dùng ở đó.
- Vẫn nên được review kỹ trước khi lên bất kỳ môi trường nào gần production (staging có thể vẫn
  bật `NODE_ENV=staging` + `SMS_PROVIDER=console` để chạy load test, nhưng cần ý thức rõ đây là
  cấu hình "không an toàn cho production", ghi trong `docs/ROADMAP.md`).

## Những gì CHƯA có (trung thực, không tô hồng)

- **Google/Apple Sign-In** chưa implement thật (stub trả 501) — cần OAuth client thật.
- **App Check** (Firebase) — chưa tích hợp, cân nhắc khi có mobile build thật để chống bot gọi
  API trực tiếp ngoài app.
- **WAF/Cloud Armor** trước Cloud Run — chưa cấu hình, cân nhắc khi có traffic thật đáng lo về
  DDoS/abuse tầng network (khác với application-level rate limit đã có).
- **Automated security rules test** — không áp dụng vì không dùng Firestore; tương đương của nó
  (E2E RBAC/ownership test) đã có và PASS, xem `docs/PHASE2-REPORT.md`.
- **Audit log cho hành động của user thường** (không phải admin) — hiện `audit_logs` chỉ ghi
  hành động admin. Có thể mở rộng nếu cần điều tra abuse từ phía user thường sau này.
