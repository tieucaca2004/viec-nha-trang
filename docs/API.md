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
| POST | `/auth/logout` | — | Thu hồi refresh token phía server (revoke); idempotent, không throw với token rác/hết hạn. Thêm khi sửa lỗi High #7 (FULL AUDIT) — trước đó "đăng xuất" chỉ xoá token phía client |
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
| GET | `/jobs` | — | Filter: keyword, categoryId, areaId, cityId, latitude/longitude/radiusKm, employmentType, shift, salaryUnit, salaryMin, salaryMax, isUrgent, startUrgency, sortBy; pagination `limit`/`offset`. `startUrgency` thêm ở Phase 3 (mobile filter §10); `salaryMax` thêm khi sửa lỗi High #9 (FULL AUDIT — filter lương min/max ở mobile) |
| GET | `/jobs/mine` | 🔒[EMPLOYER] | |
| GET | `/jobs/:id` | 🔒 (optional) | Tăng `viewCount` — chỉ khi người xem KHÔNG phải chủ tin. Job không `ACTIVE` chỉ owner/admin xem được, người khác nhận 404 (sửa lỗi Critical #4, FULL AUDIT) |
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
| GET | `/employer/jobs/:jobId/applications` | 🔒[EMPLOYER] | Chỉ chủ job xem được applicant của job đó. `jobSeeker.user.phone` — sửa ở Phase 3 (trước đó thiếu `include` nên field này luôn undefined, tính năng "Gọi ứng viên" phía mobile không thể hoạt động) |
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
| POST | `/reviews` | 🔒 | `applicationId` bắt buộc, phải thuộc đúng reviewer, và application phải ở trạng thái `HIRED` — trước đó `applicationId` optional nên có thể bypass kiểm tra bằng cách bỏ field này, đã sửa (Critical #5, FULL AUDIT). `employerId`/`jobSeekerId` server tự suy ra từ application, không nhận từ client |
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
