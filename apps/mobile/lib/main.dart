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
import 'features/jobs/data/jobs_service.dart';
import 'features/notifications/data/notifications_service.dart';
import 'features/profile/data/job_seeker_profile_service.dart';
import 'features/saved_jobs/data/saved_jobs_service.dart';
import 'shared/services/push_service.dart';
import 'shared/widgets/main_nav_scaffold.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = Session();
  await session.restore();
  runApp(VietNhaTrangApp(session: session));
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
        ProxyProvider<ApiClient, NotificationsService>(update: (_, api, __) => NotificationsService(api)),
        ProxyProvider<ApiClient, EmployerJobsService>(update: (_, api, __) => EmployerJobsService(api)),
        ProxyProvider<NotificationsService, PushService>(update: (_, svc, __) => PushService(svc)),
      ],
      child: MaterialApp(
        title: 'Việc Nha Trang',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: Consumer<Session>(
          builder: (context, session, _) => session.isLoggedIn ? const MainNavScaffold() : const OnboardingScreen(),
        ),
      ),
    );
  }
}
