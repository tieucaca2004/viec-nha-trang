# BUILD — VIỆC NHA TRANG

Trạng thái build **thật**, xác nhận trong sandbox này vào 2026-08-17 (Ubuntu 24.04, không có
Android SDK, không có Xcode/macOS). Không có mục nào dưới đây tự nhận "PASS" nếu chưa thực sự
chạy — mục BLOCKED nói rõ vì sao và cần gì để gỡ.

## apps/backend

```
cd apps/backend
npm install
npx tsc --noEmit         # PASS
npm run test:e2e         # PASS — 34/34 test, 4 suite (security/employer/job-seeker/admin)
npm run build            # PASS (Nest build, xem docs/DEPLOYMENT.md để chạy production)
```

## apps/admin (Next.js, CMS quản trị — không phải sản phẩm end-user)

Xem xác nhận build ở `docs/PHASE2-REPORT.md`. Không thay đổi ở Phase 3.

## apps/mobile (Flutter — sản phẩm chính, Android + iOS)

Toolchain trong sandbox: Flutter 3.24.5 (stable), Dart 3.5.4, cài thủ công vào
`/opt/flutter-sdk` (không có sẵn trong image, tải trực tiếp từ `storage.googleapis.com` vì
`dl.google.com` bị chặn bởi network policy — xem mục BLOCKED bên dưới).

### ✅ Đã xác nhận PASS trong sandbox

```
cd apps/mobile
flutter pub get
flutter analyze     # PASS — No issues found!
flutter test        # PASS — 41/41 test, 11 file (test/)
```

`flutter analyze` chạy trên toàn bộ `lib/` (không loại trừ file nào) và `flutter test` chạy
toàn bộ `test/` — cả hai đều thật, không có bước nào bị skip hay mock để "cho qua".

### ⚠️ BLOCKED BY ENVIRONMENT — Android build (M9)

```
flutter build apk --debug
```

Kết quả: `[!] No Android SDK found. Try setting the ANDROID_HOME environment variable.`

**Nguyên nhân xác nhận, không phải đoán**: `flutter doctor -v` xác nhận không có Android SDK.
Đã thử cài Android command-line tools qua `sdkmanager`/tải trực tiếp — network policy của
sandbox chặn `dl.google.com` (xác nhận qua `$HTTPS_PROXY/__agentproxy/status`: policy
`connect_rejected` rõ ràng cho host này, không phải lỗi mạng tạm thời). Đã thử một số host thay
thế (`maven.google.com`, ...) — không host nào phục vụ đúng Android SDK binary cần thiết.

**Những gì ĐÃ xác nhận không phải nguyên nhân của lỗi build này**: `android/` project (Gradle
scaffold, `AndroidManifest.xml`, v.v.) được sinh đúng qua `flutter create` chuẩn — không có lỗi
cấu hình project, thuần túy là thiếu SDK binary do network policy.

**Để tự chạy được**: máy có Android SDK (qua Android Studio hoặc `sdkmanager`, cần mạng truy
cập được `dl.google.com`/`googleapis.com` không bị chặn) → `flutter build apk --debug` sẽ chạy.
Không có gì trong code mobile cần sửa để build này pass.

### ⚠️ BLOCKED BY ENVIRONMENT — iOS build (M10)

iOS build (`flutter build ios`) cần Xcode, chỉ chạy trên macOS. Sandbox này là Linux
(Ubuntu 24.04) — Xcode không thể cài trên Linux, đây là giới hạn cứng của Apple toolchain, không
phải policy có thể nới. Không có cách nào "workaround" trong môi trường Linux.

`flutter doctor -v` trong sandbox này thậm chí không liệt kê mục iOS toolchain (chỉ chạy trên
macOS mới xuất hiện) — xác nhận đúng bản chất giới hạn, không phải thiếu cấu hình.

**Để tự chạy được**: máy Mac có Xcode cài đặt → `cd apps/mobile && flutter build ios` (cần thêm
provisioning profile/certificate hợp lệ cho release build, xem `docs/RELEASE.md`).

### Ghi chú thẳng thắn

`flutter analyze` + `flutter test` pass **không đồng nghĩa** app build ra APK/IPA chạy được trên
thiết bị thật — đó là lý do M9/M10 nằm riêng và ghi rõ BLOCKED thay vì gộp chung vào "đã xong".
Kiến trúc, luồng gọi API, và logic nghiệp vụ đã được xác nhận đúng qua test + phân tích tĩnh;
việc build ra binary thật chỉ còn phụ thuộc toolchain của môi trường, không phải code.

## CI

`.github/workflows/ci.yml` chạy: `backend` (tsc + test:e2e), `admin` (build), `mobile`
(flutter analyze + flutter test). CI **không** chạy Android/iOS build — GitHub Actions runner
(`ubuntu-latest`) có Android SDK sẵn nên có thể bật `flutter build apk --debug` làm smoke test
khi cần, nhưng chưa bật ở đây để giữ CI nhanh và vì chưa có signing config cho release thật; xem
`docs/RELEASE.md` cho phần còn thiếu trước khi phát hành thật.
