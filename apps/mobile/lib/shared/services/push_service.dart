import 'package:flutter/foundation.dart';
import '../../features/notifications/data/notifications_service.dart';

/// Đăng ký device token FCM với backend (đặc tả §15/§6 Phase 3).
///
/// TRẠNG THÁI THẬT (không giả vờ đã production-ready, đặc tả §23/§37):
/// Backend đã có tích hợp FCM thật (xem docs/PLAN.md §9, docs/API.md `/me/push-token`).
/// Mobile CHƯA khởi tạo Firebase native (không có `google-services.json`/`GoogleService-Info.plist`
/// vì chưa tồn tại Firebase project `viec-nha-trang` nào trong môi trường phát triển này -
/// xem docs/ENVIRONMENT.md `FCM_PROJECT_ID`). Gọi [FirebaseMessaging.instance.getToken()] ở đây
/// sẽ throw nếu Firebase chưa init - class này bọc try/catch để KHÔNG làm crash app khi chưa
/// có cấu hình, thay vì giả vờ push đã hoạt động.
///
/// Việc còn lại trước khi push thật chạy được (ghi vào docs/MOBILE.md, không tự làm ở đây vì
/// cần Firebase Console + tài khoản GCP thật, ngoài phạm vi những gì có thể làm trong sandbox):
/// 1. Tạo Firebase project `viec-nha-trang` (độc lập pshop-music).
/// 2. `flutterfire configure` để sinh `firebase_options.dart` + file cấu hình native.
/// 3. Gọi `Firebase.initializeApp()` trong `main()` trước `runApp()`.
/// 4. Xin quyền notification (Android 13+, iOS) qua `FirebaseMessaging.instance.requestPermission()`.
class PushService {
  final NotificationsService notificationsService;
  PushService(this.notificationsService);

  Future<void> registerDeviceTokenIfAvailable() async {
    try {
      // Điểm nối thật khi Firebase đã init:
      // final token = await FirebaseMessaging.instance.getToken();
      // if (token != null) await notificationsService.registerPushToken(token);
      //
      // Chưa gọi native Firebase ở đây vì chưa có cấu hình project thật (xem docstring class).
    } catch (error) {
      debugPrint('PushService: bỏ qua đăng ký push token ($error) - xem docs/MOBILE.md.');
    }
  }
}
