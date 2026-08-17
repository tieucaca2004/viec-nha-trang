# MOBILE — VIỆC NHA TRANG (Flutter)

Ứng dụng người dùng cuối là **app di động Flutter** (Android + iOS) — web (`apps/admin`) chỉ
dùng cho quản trị/CMS, không phải sản phẩm cho seeker/employer. `apps/mobile` gọi thẳng
`apps/backend` (NestJS), không có backend-for-frontend riêng.

## Kiến trúc thư mục

```
lib/
  core/
    config/    AppConfig — đọc --dart-define, không hard-code URL production
    network/   ApiClient (JWT, timeout, retry-on-401), ApiException (map lỗi → tiếng Việt)
    storage/   SecureTokenStorage — flutter_secure_storage (Keychain/Keystore)
    auth/      Session (ChangeNotifier) — access/refresh token, roles, activeRole
    theme/     AppTheme
  features/
    auth/            data/ (AuthService) + presentation/ (onboarding, phone login, OTP)
    jobs/             data/ (JobsService) + presentation/ (home, job detail, filter sheet, JobCard)
    applications/     data/ (ApplicationsService) + presentation/ (tabs theo trạng thái)
    saved_jobs/       data/ (SavedJobsService) + presentation/
    notifications/    data/ (NotificationsService) + presentation/
    profile/          data/ (JobSeekerProfileService) + presentation/ (profile, form hồ sơ)
    employer/         data/ (EmployerJobsService, EmployerProfileService) + presentation/
                       (dashboard, đăng tin wizard, quản lý ứng viên)
  shared/
    models/    Job, Application (dùng chung nhiều feature)
    widgets/   MainNavScaffold (bottom nav seeker/employer), AsyncStateView (Loading/Empty/Error)
    services/  PushService
```

Mỗi feature tách `data/` (gọi API thô, trả JSON hoặc model) khỏi `presentation/` (widget, state
UI) — không có file khổng lồ trộn network + UI.

## State management: `provider`, không phải Riverpod

Đặc tả Phase 3 yêu cầu Riverpod "hoặc giải pháp tương đương nếu repository đã có convention
khác". `apps/mobile` từ Phase 1 đã dùng `provider` (`ChangeNotifier` + `Consumer`/`context.read`)
xuyên suốt — Session, và mọi service (`JobsService`, `ApplicationsService`, ...) được cung cấp
qua `MultiProvider` ở `main.dart`. Giữ nguyên convention này thay vì viết lại toàn bộ sang
Riverpod, đúng theo điều khoản "tương đương" của đặc tả — không có lý do kỹ thuật để rewrite.

`Session extends ChangeNotifier` là nguồn sự thật duy nhất cho auth state; `main.dart` dùng
`Consumer<Session>` để route reactive (chưa đăng nhập → onboarding/login, đã đăng nhập →
`MainNavScaffold` với nav đúng theo `session.activeRole`).

## Networking

- `ApiClient` (`core/network/api_client.dart`): base URL từ `AppConfig.apiBaseUrl`, gắn
  `Authorization: Bearer <accessToken>`, timeout 15s, tự động gọi `/auth/refresh` khi gặp 401
  rồi retry đúng 1 lần trước khi logout, map lỗi mạng/timeout/HTTP thành `ApiException` với
  `userMessage` tiếng Việt thân thiện (không bao giờ lộ stack trace ra UI — §26).
- Không có mock trong luồng production — mọi service gọi thẳng backend thật. Test dùng
  `package:http/testing.dart` `MockClient` (không cần thêm dependency mock).
- 3 environment: `development`/`staging`/`production`, chọn qua `--dart-define=APP_ENV=...` +
  `--dart-define=API_BASE_URL=...` lúc build (xem `docs/ENVIRONMENT.md`). Không có URL production
  nào nằm trong source.

## Auth

Phone OTP (request → verify) — khớp `POST /auth/otp/request` + `/auth/otp/verify` thật của
backend. Google/Apple **chưa** implement ở mobile vì backend trả 501 cho `/auth/google` và
`/auth/apple` (xem `docs/API.md`, `docs/ROADMAP.md`) — không tự chế API phía client.

Session (access/refresh token, roles, activeRole) lưu qua `flutter_secure_storage`
(`SecureTokenStorage`) — Android Keystore / iOS Keychain, thay cho `shared_preferences` không mã
hoá ở Phase 1. Đổi role (seeker ⇄ employer) gọi `PATCH /me/roles` thật, không tạo tài khoản mới.

## Lỗ hổng API phát hiện và sửa trong Phase 3

Theo đúng nguyên tắc "chỉ sửa backend khi thật sự cần, không tự đoán API" — 2 gap có thật, sửa
tối thiểu, backward-compatible:

1. **Filter "Khi nào cần người" không có trên backend.** Bộ lọc job mobile (§10) cần lọc theo
   `startUrgency` nhưng `GET /jobs` chưa có param này. Thêm `startUrgency?: StartUrgency` (optional,
   `@IsEnum`) vào `QueryJobsDto` + nối vào `where` clause của `JobsService.findMany` — field mới
   hoàn toàn optional, không ảnh hưởng client cũ.
2. **Employer không xem được SĐT ứng viên (bug thật).** `JobSeekerProfile` không có field
   `phone` (nằm ở `User`), nhưng `listForEmployerJob` chỉ `include: { jobSeeker: true }`, không
   join `user` → field phone luôn `undefined`, tính năng "Gọi ứng viên" không thể hoạt động dù
   UI đã có nút gọi. Sửa `include` để join thêm `user: { select: { phone: true } }`. Đổi shape
   response: `application.jobSeeker.phone` (chưa từng tồn tại) → `application.jobSeeker.user.phone`.

Cả hai xác nhận bằng `npm run test:e2e` (34/34 pass) sau khi sửa — xem `docs/API.md`.

## Trạng thái từng milestone

| Milestone | Trạng thái | Ghi chú |
|---|---|---|
| M1 Flutter foundation | ✅ | Cấu trúc `core/`+`features/`+`shared/` như trên |
| M2 Authentication | ✅ | OTP thật, secure storage, session reactive |
| M3 Seeker marketplace | ✅ | Search debounce 400ms, filter sheet, job detail, JobCard tối giản |
| M4 Application flow | ✅ | 1-chạm apply, không trùng (unique constraint DB), tabs theo trạng thái, saved jobs (save/unsave wire vào JobCard+JobDetail, sửa ở audit remediation — xem mục dưới) |
| M5 Employer flow | ✅ | Wizard đăng tin 9 bước, quản lý tin theo trạng thái, quản lý ứng viên |
| M6 Notifications | ⚠️ Một phần | Backend FCM đã có thật; mobile CHƯA init Firebase native — xem mục dưới |
| M7 Location | ✅ | `geolocator`, permission không chặn app, fallback chọn khu vực thủ công |
| M8 Testing | ✅ | 56 test (unit + widget) sau audit remediation, `flutter test` pass, `flutter analyze` 0 issue |
| M9 Android build | ⚠️ BLOCKED BY ENVIRONMENT | Xem `docs/BUILD.md` |
| M10 iOS build | ⚠️ BLOCKED BY ENVIRONMENT | Sandbox Linux, không có Xcode — xem `docs/BUILD.md` |
| M11 Docs/CI | ✅ | Tài liệu này + `docs/BUILD.md` + `docs/RELEASE.md` + CI |

### M6 — Push notification: những gì thật, những gì còn thiếu

Backend đã tích hợp `firebase-admin` thật (Phase 2, xem `docs/PLAN.md` §9). Mobile:
`NotificationsService.registerPushToken()` gọi thật `POST /me/push-token` (test bằng MockClient
xác nhận đúng path/body). `PushService` (`shared/services/push_service.dart`) là điểm nối tới
FCM native nhưng **chưa gọi Firebase thật** — không có `google-services.json`/
`GoogleService-Info.plist` vì chưa có Firebase project `viec-nha-trang` (độc lập hoàn toàn với
`pshop-music`, theo §1) trong môi trường này. `pubspec.yaml` cố tình **không** khai báo
`firebase_core`/`firebase_messaging` cho tới khi có project thật — comment trong file giải thích
cách thêm lại (`flutter pub add firebase_core firebase_messaging`).

Việc còn lại (ngoài phạm vi sandbox — cần Firebase Console + tài khoản GCP thật):
1. Tạo Firebase project `viec-nha-trang`.
2. `flutterfire configure` → sinh `firebase_options.dart` + file cấu hình native 2 platform.
3. `Firebase.initializeApp()` trong `main()` trước `runApp()`.
4. Cài lại `firebase_core`/`firebase_messaging`, nối `PushService` với `FirebaseMessaging.instance`.
5. Deep-link từ notification → job/application detail (route đã tồn tại, chỉ cần payload → route).

Màn hình danh sách thông báo (`NotificationsScreen`) đã hoạt động đầy đủ với dữ liệu backend
thật (không phụ thuộc FCM native) — chỉ thiếu bước "nhận push khi app ở background/killed".

## Audit remediation (sau FULL AUDIT lần 1, trước khi merge main)

FULL AUDIT lần 1 phát hiện project ở mức ~60-65% hoàn thành V1, với 5 lỗi Critical và 6 lỗi High.
Toàn bộ đã được sửa và có test thật xác nhận (không đánh dấu DONE khi chưa kiểm chứng):

| # | Lỗi | Sửa | Test |
|---|---|---|---|
| Critical 1 | Không có cách lưu việc (chỉ unsave được) | Wire `SavedJobsService.save/unsave` thật vào `JobCard` (icon bookmark) và `JobDetailScreen` (AppBar action) | `job_card_test.dart`, `home_screen_save_test.dart` (screen-level, không chỉ widget rời) |
| Critical 2 | `AndroidManifest.xml` chính không có quyền nào | Thêm `INTERNET` + `ACCESS_FINE_LOCATION`, không thêm thừa | Xác nhận XML hợp lệ; hành vi thật cần Android build (BLOCKED BY ENVIRONMENT, xem `docs/BUILD.md`) |
| Critical 3 | iOS thiếu `NSLocationWhenInUseUsageDescription` | Thêm key với nội dung tiếng Việt rõ ràng | Xác nhận plist hợp lệ; hành vi thật cần iOS build (BLOCKED BY ENVIRONMENT) |
| Critical 4 | `GET /jobs/:id` không kiểm tra status, `viewCount` tăng cả khi owner tự xem | `OptionalJwtAuthGuard` mới; chỉ ACTIVE mới public, owner/admin xem được non-ACTIVE (404 cho người khác, không phải 403 — tránh lộ tồn tại); không tăng view khi owner xem | `test/job-visibility.e2e-spec.ts` (7 test: ACTIVE/DRAFT/CLOSED/EXPIRED × anonymous/owner/admin/other-employer) |
| Critical 5 | `POST /reviews` bypass được kiểm tra HIRED bằng cách bỏ `applicationId` | `applicationId` bắt buộc; ownership + trạng thái HIRED kiểm tra từ chính application; `employerId`/`jobSeekerId` server tự suy ra, không nhận từ client | `test/reviews.e2e-spec.ts` (6 test: thiếu applicationId/không tồn tại/của người khác/chưa HIRED/thành công/không spoof được employerId) |
| High 6 | `sortBy=salary` sort sau khi đã phân trang ở DB (không có GPS) | Sort ở DB level (`orderBy: salaryMax desc`) trước `take/skip`, kèm `count()` riêng cho `total` | `test/job-search-sort.e2e-spec.ts` (12 job, kiểm tra đúng thứ tự trang 1/2, cả có/không GPS) |
| High 7 | Không có logout phía server, refresh token cũ vẫn dùng được | `POST /auth/logout` revoke refresh token (idempotent, không throw với token rác); thêm `jti` ngẫu nhiên vào refresh JWT (phát hiện khi test: 2 phiên đăng nhập cùng giây trước đây sinh JWT trùng hệt nhau); mobile gọi API logout trước khi xoá session cục bộ (best-effort) | `test/logout.e2e-spec.ts` (5 test), `auth_service_test.dart` |
| High 8 | Toạ độ cơ sở employer luôn hard-code trung tâm Nha Trang | Bỏ hard-code hoàn toàn; employer chọn GPS hiện tại (`geolocator`, cùng pattern non-blocking như seeker) hoặc tự nhập lat/lng; hiển thị xác nhận trước khi lưu; chặn lưu nếu chưa có vị trí. **Không** thêm Google Maps picker tương tác — đặc tả gốc §18/§37 cấm thêm Maps billing/config khi chưa có credentials thật trong môi trường này | `employer_business_setup_screen_test.dart` (3 test) |
| High 9 | `JobFilterSheet` không có filter lương dù có trong đặc tả | Thêm `salaryMax` backend (optional, backward-compatible, cùng mẫu với `startUrgency` ở Phase 3); UI 2 ô nhập Từ/Đến trong filter sheet | Backend: `coverage-gaps.e2e-spec.ts`; Mobile: `job_filter_sheet_test.dart`, `jobs_service_test.dart` |

Test mới thêm khi sửa: backend 34 → 69 test (9 file, tất cả pass ổn định qua nhiều lần chạy lặp
lại); mobile 42 → 56 test. Không dùng mock để che lỗi thật — mọi fix đều có test xác nhận hành vi
đúng, không phải chỉ test cho qua để build pass.

## Bảo mật

- Token: `flutter_secure_storage`, không bao giờ `shared_preferences`/plain file.
- Không log token, OTP, hay PII không cần thiết (`debugPrint` trong `PushService` chỉ log lỗi,
  không log token).
- Không secret nào (API key, service account) nằm trong source mobile — chỉ base URL qua
  `--dart-define`, không phải secret.

## Kiểm thử

Xem `docs/TESTING.md` cho tổng quan toàn dự án. Riêng mobile: 41 test trong 11 file
(`apps/mobile/test/`) — `core/network` (ApiClient, ApiException), `core/auth` (Session),
từng `features/*/data/*_service_test.dart` (Auth, Jobs+Filter, Applications, SavedJobs,
Notifications, Employer), `shared/models/job_test.dart`, và 2 widget test
(`JobCard`, `OnboardingScreen`). Không dùng thêm mocking framework — `http/testing.dart`
`MockClient` đủ cho toàn bộ service layer.
