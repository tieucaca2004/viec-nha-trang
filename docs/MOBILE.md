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
| M4 Application flow | ✅ | 1-chạm apply, không trùng (unique constraint DB), tabs theo trạng thái, saved jobs |
| M5 Employer flow | ✅ | Wizard đăng tin 9 bước, quản lý tin theo trạng thái, quản lý ứng viên |
| M6 Notifications | ⚠️ Một phần | Backend FCM đã có thật; mobile CHƯA init Firebase native — xem mục dưới |
| M7 Location | ✅ | `geolocator`, permission không chặn app, fallback chọn khu vực thủ công |
| M8 Testing | ✅ | 41 test (unit + widget), `flutter test` pass, `flutter analyze` 0 issue |
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
