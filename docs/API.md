# API — VIỆC NHA TRANG

REST, prefix `/api/v1`. Nguồn sự thật là Swagger tự sinh từ DTO thật tại `/api/docs` (và
`/api/docs-json` cho máy đọc) khi backend đang chạy — bảng dưới đây liệt kê từ controller thật
(`grep` trực tiếp trong `apps/backend/src`, không phải tài liệu viết tay tách rời code).

`🔒` = cần `Authorization: Bearer <accessToken>`. `🔒[ROLE]` = cần thêm đúng role đó (kiểm tra
server-side qua `RolesGuard`, không tin role client tự khai — §34/§8).

## Auth

| Method | Path | Auth | Ghi chú |
|---|---|---|---|
| POST | `/auth/otp/request` | — | Rate-limited (`OTP_REQUEST_THROTTLE_LIMIT`, mặc định 3/phút/IP) |
| POST | `/auth/otp/verify` | — | Trả `accessToken`+`refreshToken`; rate-limited (mặc định 5/phút/IP) |
| POST | `/auth/refresh` | — | Đổi refresh token cũ (bị revoke) lấy cặp token mới |
| POST | `/auth/google` | — | Chưa implement — trả 501, xem `docs/ROADMAP.md` |
| POST | `/auth/apple` | — | Chưa implement — trả 501, xem `docs/ROADMAP.md` |

## Hồ sơ cá nhân (`/me`)

| Method | Path | Auth | Ghi chú |
|---|---|---|---|
| GET | `/me` | 🔒 | Không bao giờ trả `passwordHash` (xem `docs/SECURITY.md`) |
| PATCH | `/me/roles` | 🔒 | Thêm role (`JOB_SEEKER`/`EMPLOYER`) vào tài khoản hiện có — không tạo tài khoản mới (§5) |
| GET | `/me/job-seeker-profile` | 🔒 | 404 nếu chưa tạo |
| PUT | `/me/job-seeker-profile` | 🔒[JOB_SEEKER] | Tạo/cập nhật, CV không bắt buộc |
| GET | `/me/employer-profile` | 🔒 | 404 nếu chưa tạo |
| PUT | `/me/employer-profile` | 🔒[EMPLOYER] | |
| GET | `/me/employer-profile/locations` | 🔒[EMPLOYER] | |
| POST | `/me/employer-profile/locations` | 🔒[EMPLOYER] | |

## Danh mục & khu vực (public, đọc)

| Method | Path | Auth | Ghi chú |
|---|---|---|---|
| GET | `/categories` | — | Chỉ `isActive=true` |
| GET | `/cities` | — | |
| GET | `/areas?cityId=` | — | |

## Việc làm

| Method | Path | Auth | Ghi chú |
|---|---|---|---|
| GET | `/jobs` | — | Filter: keyword, categoryId, areaId, cityId, latitude/longitude/radiusKm, employmentType, shift, salaryUnit, salaryMin, isUrgent, sortBy; pagination `limit`/`offset` |
| GET | `/jobs/mine` | 🔒[EMPLOYER] | |
| GET | `/jobs/:id` | — | Tăng `viewCount` |
| POST | `/jobs` | 🔒[EMPLOYER] | Lương (`salaryMin`/`salaryMax`/`salaryUnit`) bắt buộc — §21 |
| PATCH | `/jobs/:id` | 🔒[EMPLOYER] | Chỉ chủ job mới sửa được (ownership check server-side) |
| POST | `/jobs/:id/close` | 🔒[EMPLOYER] | |
| POST | `/jobs/:id/renew` | 🔒[EMPLOYER] | |
| POST | `/jobs/:id/boost` | 🔒[EMPLOYER] | Đánh dấu `isBoosted` — chưa gắn thanh toán thật |

## Ứng tuyển

| Method | Path | Auth | Ghi chú |
|---|---|---|---|
| POST | `/jobs/:jobId/apply` | 🔒[JOB_SEEKER] | Ứng tuyển 1 chạm; idempotent (apply lại trả về application đã có, không tạo trùng — unique constraint DB) |
| GET | `/applications/me` | 🔒[JOB_SEEKER] | |
| GET | `/employer/jobs/:jobId/applications` | 🔒[EMPLOYER] | Chỉ chủ job xem được applicant của job đó |
| PATCH | `/applications/:id/status` | 🔒[EMPLOYER] | State machine `NEW→VIEWED→CONTACTED→INTERVIEW→HIRED\|NOT_SUITABLE\|NO_SHOW`, chuyển sai thứ tự → 400 |

## Đã lưu

| Method | Path | Auth |
|---|---|---|
| GET | `/saved-jobs` | 🔒 |
| POST | `/saved-jobs/:jobId` | 🔒 |
| DELETE | `/saved-jobs/:jobId` | 🔒 |

## Đánh giá & báo cáo

| Method | Path | Auth | Ghi chú |
|---|---|---|---|
| POST | `/reviews` | 🔒 | Chặn nếu gắn `applicationId` mà status khác `HIRED` |
| GET | `/reviews?targetType=&targetId=` | 🔒 | |
| POST | `/reports` | 🔒 | |

## Thông báo

| Method | Path | Auth |
|---|---|---|
| GET | `/notifications` | 🔒 |
| PATCH | `/notifications/:id/read` | 🔒 |

## Admin (tất cả 🔒[ADMIN])

| Method | Path | Ghi chú |
|---|---|---|
| GET | `/admin/dashboard` | Tổng user/seeker/employer/active jobs/tin mới hôm nay/applications/reports mở |
| GET | `/admin/users` | |
| POST | `/admin/users/:id/ban` | Ghi `audit_logs` |
| POST | `/admin/users/:id/unban` | Ghi `audit_logs` |
| GET | `/admin/employers` | |
| POST | `/admin/employers/:id/verify` | Đổi `verificationLevel`, ghi `audit_logs` |
| GET | `/admin/jobs` | Filter theo `status` |
| PATCH | `/admin/jobs/:id/status` | Ghi `audit_logs` |
| POST | `/admin/jobs/:id/remove` | Soft delete, ghi `audit_logs` |
| GET | `/admin/applications` | |
| GET | `/admin/reports` | Filter theo `status` |
| PATCH | `/admin/reports/:id/resolve` | Ghi `audit_logs` |
| GET | `/admin/categories` | |
| POST | `/admin/categories` | Ghi `audit_logs` |
| PATCH | `/admin/categories/:id` | Ghi `audit_logs` |
| GET | `/admin/areas` | |
| POST | `/admin/areas` | Ghi `audit_logs` |
| PATCH | `/admin/areas/:id` | Ghi `audit_logs` |

**Tổng: 45 route** — khớp số route Nest log ra khi boot (`RouterExplorer` log), đã xác minh live
ở Phase 2.

## Chuẩn lỗi

Response lỗi theo format mặc định của Nest exception filter: `{ statusCode, message, error }`.
`400` = validation lỗi (thiếu field bắt buộc, sai kiểu, field lạ bị `whitelist` chặn). `401` =
chưa đăng nhập/token không hợp lệ. `403` = đăng nhập rồi nhưng sai role hoặc không phải chủ sở
hữu resource. `404` = không tìm thấy. `429` = vượt rate limit (chủ yếu OTP).
