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

### ⚠️ BLOCKED BY ENVIRONMENT trong sandbox — nhưng chạy được trên CI thật, và CI thật phát hiện 1 lỗi thật (Android build, M9)

Trong sandbox này (`flutter build apk --debug`) vẫn thất bại vì lý do y hệt Phase 3:
`[!] No Android SDK found` — `flutter doctor -v` xác nhận, network policy sandbox chặn
`dl.google.com` (xác nhận qua `$HTTPS_PROXY/__agentproxy/status`). Không đổi so với Phase 3.

**Cập nhật quan trọng (audit remediation, xác nhận qua GitHub Actions thật ngày 2026-08-17,
run [32045998356](https://github.com/tieucaca2004/viec-nha-trang/actions/runs/32045998356))**:
CI's `ubuntu-latest` runner CÓ Android SDK thật (khác sandbox) — `flutter analyze` và
`flutter test` (56/56) đều PASS thật trên CI, nhưng `flutter build apk --debug` **FAIL thật**,
không phải vì thiếu SDK:

```
A problem occurred evaluating project ':geolocator_android'.
> Could not get unknown property 'flutter' for extension 'android' of type LibraryExtension.
...
> compileSdkVersion is not specified. Please add it to build.gradle
```

**Nguyên nhân xác nhận (không phải đoán)**: đây là bug thật của `geolocator_android 4.6.2`
(kéo theo bởi `geolocator ^13.x` trong `pubspec.yaml`) — `android/build.gradle` của chính
package đó (trong `.pub-cache`, không phải code của project này) đọc `flutter.compileSdkVersion`
theo cách không tương thích với cơ chế nạp Flutter Gradle Plugin hiện tại. Đã thử fix thật: bản
`geolocator_android 5.0.3` sửa đúng lỗi này, nhưng nó chỉ đến kèm `geolocator ^14.0.0`, và
changelog của `geolocator 14.0.0` ghi rõ **BREAKING CHANGE: yêu cầu Flutter SDK ≥3.29** — thử
override trực tiếp `dependency_overrides: geolocator_android: ^5.0.3` (giữ `geolocator ^13.x`)
thì `flutter pub get` qua được, nhưng `flutter test` fail biên dịch thật vì package đó dùng API
`Color.toARGB32()` chỉ có ở Flutter ≥3.27, dự án đang pin Flutter 3.24.5 → xác nhận yêu cầu nâng
Flutter SDK là có thật, không tránh được bằng version pin nhỏ hơn.

**Quyết định**: KHÔNG nâng Flutter SDK trong lần sửa lỗi này — đó là thay đổi toolchain lớn
(ảnh hưởng CI, cấu hình local, khả năng tương thích các package khác), ngoài phạm vi yêu cầu sửa
Critical/High của audit này, và cần được duyệt riêng. Đã revert override, `pubspec.yaml`/
`pubspec.lock` giữ nguyên như trước.

**Xác nhận rõ: đây không phải lỗi trong code của project này.** `android/app/build.gradle` (do
`flutter create` sinh, thuộc project này) cấu hình đúng chuẩn (`compileSdk = flutter.compileSdkVersion`
— xem file). Lỗi nằm hoàn toàn trong package bên thứ ba `geolocator_android` ở `.pub-cache`.

**Fix thật đã áp dụng (không phải workaround/mock)**: pin `geolocator_android` xuống bản `4.6.1`
(bản ngay trước khi regression Gradle xuất hiện) qua `dependency_overrides` trong `pubspec.yaml`,
giữ nguyên `geolocator: ^13.0.1` và Flutter 3.24.5 — không nâng Flutter SDK, không đổi kiến trúc,
không gỡ geolocator hay tính năng GPS. Xác nhận qua diff trực tiếp Gradle file của 2 bản:

- `geolocator_android 4.6.1`: `android/build.gradle` hard-code `compileSdk 34` / `minSdkVersion 16`
  — không phụ thuộc extension `flutter` — build được với cơ chế nạp Flutter Gradle Plugin hiện tại.
- `geolocator_android 4.6.2` (bản mặc định `geolocator ^13.0.1` resolve tới): đổi sang tham chiếu
  động `flutter.compileSdkVersion` / `flutter.minSdkVersion` — đây là dòng gây lỗi thật.
- `geolocator_android 5.0.0`: `android/build.gradle` giống hệt byte-for-byte với `4.6.2` (đã diff
  trực tiếp) — xác nhận bump lên bản kế tiếp KHÔNG sửa được lỗi này.
- `geolocator_android 5.0.3` (bản có sửa Gradle thật): chỉ đi kèm `geolocator ^14.0.0`, và
  changelog `geolocator 14.0.0` yêu cầu Flutter SDK ≥3.29 (`Color.toARGB32()`) — không tương
  thích an toàn với Flutter 3.24.5 đang pin, đã xác nhận lại bằng thử nghiệm override trực tiếp
  (biên dịch fail thật).

Tương thích: `compileSdk 34` / `minSdkVersion 16` (hard-code trong `geolocator_android 4.6.1`)
tương thích hoàn toàn với `compileSdk 34` / `minSdk 21` của project (minSdk của plugin thấp hơn
minSdk của app luôn hợp lệ). Không có breaking change Dart/API giữa 4.6.1 và 4.6.2 (chỉ khác file
Gradle) — `flutter analyze` (0 lỗi) và `flutter test` (56/56) xác nhận không ảnh hưởng code Dart.

Xác nhận qua GitHub Actions run thật sau khi áp dụng fix — xem link run mới nhất trong lịch sử
commit của nhánh (`git log`), không lặp lại số run cụ thể ở đây vì file này không tự cập nhật theo
mỗi lần CI chạy lại.

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
(flutter analyze + flutter test + `flutter build apk --debug` làm smoke test debug build, chạy
thật trên `ubuntu-latest` vì runner đó có sẵn Android SDK thật, khác sandbox này). CI không build
release/signed APK hay iOS — xem `docs/RELEASE.md` cho phần còn thiếu trước khi phát hành thật.
