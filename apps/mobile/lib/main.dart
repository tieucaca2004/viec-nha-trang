import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/auth/session.dart';
import 'core/network/api_client.dart';
import 'core/theme/app_theme.dart';
import 'features/applications/data/applications_service.dart';
import 'features/auth/data/auth_service.dart';
import 'features/auth/presentation/onboarding_screen.dart';
import 'features/employer/data/employer_jobs_service.dart';
import 'features/employer/data/employer_profile_service.dart';
import 'features/employer/data/geocoding_service.dart';
import 'features/jobs/data/jobs_service.dart';
import 'features/notifications/data/notifications_service.dart';
import 'features/profile/data/job_seeker_profile_service.dart';
import 'features/saved_jobs/data/saved_jobs_service.dart';
import 'shared/services/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = Session();
  // restore() CHỈ đọc local storage (không gọi network) - app phải mở được và cho duyệt việc
  // ngay cả khi backend chậm/không khả dụng (đặc tả AUTH UX Part 5/11: guest browsing không phụ
  // thuộc /me).
  await session.restore();
  runApp(VietNhaTrangApp(session: session));

  // Đặc tả Part 5 case C/D: nếu có access token lưu sẵn, âm thầm xác thực lại NGAY (không await,
  // không chặn runApp/UI) bằng đúng hạ tầng refresh-on-401 đã có sẵn trong ApiClient - access
  // token còn hạn thì GET /me thành công, hết hạn thì ApiClient tự refresh bằng refresh token rồi
  // thử lại; refresh cũng hỏng thì ApiClient tự session.logout() (xoá token cục bộ, chuyển về
  // guest) - KHÔNG hiện lỗi báo động, người dùng vẫn duyệt việc bình thường. Không tạo ApiClient
  // mới cho vòng đời sau đó (chỉ dùng 1 lần ở đây) - provider tree trong VietNhaTrangApp vẫn là
  // nguồn ApiClient DUY NHẤT cho mọi widget khác.
  if (session.accessToken != null) {
    AuthService(ApiClient(session), session).refreshMe().catchError((_) {
      // Lỗi (network/refresh token cũng hỏng) đã được ApiClient/Session xử lý an toàn ở trên -
      // không cần làm gì thêm ở đây, không hiện lỗi cho người dùng lúc khởi động app.
    });
  }
}

/// VIỆC NHA TRANG - ứng dụng tuyển dụng/tìm việc khu vực Nha Trang (đặc tả Phase 3).
/// Kiến trúc: core/ (config, network, storage, auth, theme) + features/<domain>/{data,presentation}
/// + shared/ (widgets, models dùng chung nhiều feature) - đúng cấu trúc đề xuất §2 Phase 3.
/// State management: `provider` (ChangeNotifier) - giữ nguyên convention đã có từ trước thay vì
/// đổi sang Riverpod, đúng điều khoản "hoặc giải pháp tương đương nếu repo đã có convention khác"
/// ở §3 Phase 3. Chi tiết quyết định: xem docs/MOBILE.md.
class VietNhaTrangApp extends StatelessWidget {
  final Session session;
  const VietNhaTrangApp({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: session),
        Provider(create: (_) => ApiClient(session)),
        ProxyProvider<ApiClient, AuthService>(update: (_, api, __) => AuthService(api, session)),
        ProxyProvider<ApiClient, JobsService>(update: (_, api, __) => JobsService(api)),
        ProxyProvider<ApiClient, ApplicationsService>(update: (_, api, __) => ApplicationsService(api)),
        ProxyProvider<ApiClient, SavedJobsService>(update: (_, api, __) => SavedJobsService(api)),
        ProxyProvider<ApiClient, JobSeekerProfileService>(update: (_, api, __) => JobSeekerProfileService(api)),
        ProxyProvider<ApiClient, EmployerProfileService>(update: (_, api, __) => EmployerProfileService(api)),
        Provider<GeocodingService>(create: (_) => GeocodingService()),
        ProxyProvider<ApiClient, NotificationsService>(update: (_, api, __) => NotificationsService(api)),
        ProxyProvider<ApiClient, EmployerJobsService>(update: (_, api, __) => EmployerJobsService(api)),
        ProxyProvider<NotificationsService, PushService>(update: (_, svc, __) => PushService(svc)),
      ],
      child: MaterialApp(
        title: 'Việc Nha Trang',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        // Home (2 thẻ TÌM VIỆC/TUYỂN NGƯỜI) LUÔN là route gốc/đầu tiên của app - kể cả khi đã
        // đăng nhập - để mọi màn hình bên trong luôn có đường quay lại đúng 1 Home duy nhất
        // (không tạo route Home mới, không đẩy chồng Home nhiều lần). Trước đây `home:` đổi hẳn
        // sang MainNavScaffold khi đã đăng nhập nên Home biến mất hoàn toàn khỏi navigator stack.
        home: const OnboardingScreen(),
      ),
    );
  }
}
