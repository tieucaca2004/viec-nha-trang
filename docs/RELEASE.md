# RELEASE — VIỆC NHA TRANG (mobile)

Checklist thật cho việc đưa app lên Google Play / App Store. Đây là danh sách yêu cầu, **không**
phải xác nhận đã sẵn sàng phát hành — phần lớn mục dưới đây chưa làm, ghi rõ trạng thái từng
mục thay vì overclaim.

## Trạng thái tổng quan

App **chưa sẵn sàng phát hành**. Lý do chính: chưa build ra binary thật (BLOCKED BY ENVIRONMENT,
xem `docs/BUILD.md`), chưa có tài khoản developer Google Play/App Store, chưa có Firebase
project thật cho push notification, chưa có asset store (icon, screenshot) chính thức.

## Trước khi build release

- [ ] **App icon** — chưa có, hiện dùng icon mặc định Flutter (`flutter create`). Cần bộ icon
      thật (1024×1024 gốc + các size Android/iOS) trước khi nộp store.
- [ ] **App name/bundle ID** — hiện `com.viecnhatrang.viec_nha_trang` (đặt khi `flutter create`
      ở Phase 3, org `com.viecnhatrang`). Xác nhận lại với chủ sản phẩm trước khi khoá vĩnh viễn
      (đổi bundle ID sau khi publish rất tốn công).
- [ ] **Splash screen** — dùng mặc định Flutter, chưa có màn hình khởi động theo brand thật.
- [ ] **Signing key (Android)** — chưa tạo keystore release. **Không bao giờ** commit file
      `.jks`/`.keystore` hay mật khẩu vào repo — lưu ở nơi an toàn ngoài git (CI secret/1Password),
      xem `docs/SECURITY.md`.
- [ ] **Signing certificate (iOS)** — chưa có Apple Developer account/certificate/provisioning
      profile. Cũng không bao giờ commit vào repo.
- [ ] **Firebase project `viec-nha-trang`** — chưa tạo (độc lập hoàn toàn `pshop-music`, §1).
      Cần trước khi push notification hoạt động thật trên thiết bị (xem `docs/MOBILE.md` M6).
- [ ] **`API_BASE_URL` production** — chưa có domain production thật cho backend (xem
      `docs/DEPLOYMENT.md`); build release phải truyền đúng qua `--dart-define`, không hard-code.

## Store listing

- [ ] Mô tả ứng dụng (tiếng Việt, theo đúng định vị: "không phải mạng xã hội" — §37).
- [ ] Screenshot thật trên thiết bị/emulator (chưa chụp được — cần Android SDK/máy thật, xem
      `docs/BUILD.md`).
- [ ] **Privacy Policy** — bắt buộc với cả 2 store, đặc biệt vì app thu thập vị trí (GPS) và số
      điện thoại. Chưa soạn — cần trước khi nộp, không thể bỏ qua ở cả Google Play lẫn App Store.
- [ ] **Data safety form (Google Play)** / **App Privacy (App Store)** — khai đúng dữ liệu thật
      thu thập: số điện thoại (auth), vị trí GPS (tìm việc gần), không thu thập gì hơn mức cần.
- [ ] Category, content rating, target audience.

## Kiểm tra kỹ thuật trước khi nộp

- [ ] `flutter build appbundle --release` (Android) chạy thành công, test trên thiết bị thật.
- [ ] `flutter build ios --release` chạy thành công, test qua TestFlight.
- [ ] Xin quyền runtime đúng lúc, đúng lý do hiển thị cho người dùng (vị trí — đã có flow không
      chặn app khi từ chối, xem `docs/MOBILE.md` M7; notification — cần khi tích hợp FCM native).
- [ ] Kiểm tra deep link (notification → job/application detail) hoạt động khi app ở
      background/killed — phụ thuộc Firebase init thật, hiện chưa test được (xem M6).
- [ ] Test OTP thật với SMS provider thật (`SMS_PROVIDER` hiện là `console` ở dev — production
      cần provider SMS thật, xem `docs/ENVIRONMENT.md`, chưa implement — xem `docs/ROADMAP.md`).

## Không bao giờ

- Commit signing key/certificate/provisioning profile vào repo.
- Hard-code `API_BASE_URL` production vào source thay vì `--dart-define`.
- Publish với `SMS_PROVIDER=console` (OTP log ra log thay vì gửi SMS thật) — chỉ dùng dev/test.
- Claim "sẵn sàng phát hành" khi chưa build ra binary thật trên thiết bị thật (xem `docs/BUILD.md`).
