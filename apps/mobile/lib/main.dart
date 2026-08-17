import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/api_client.dart';
import 'core/session.dart';
import 'services/applications_service.dart';
import 'services/auth_service.dart';
import 'services/employer_jobs_service.dart';
import 'services/jobs_service.dart';
import 'services/notifications_service.dart';
import 'services/profile_service.dart';
import 'screens/auth/phone_login_screen.dart';
import 'widgets/main_nav_scaffold.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = Session();
  await session.restore();
  runApp(VietNhaTrangApp(session: session));
}

/// VIỆC NHA TRANG - ứng dụng tuyển dụng/tìm việc khu vực Nha Trang (đặc tả mục 1).
/// Kiến trúc chia rõ mobile/backend/database (docs/ARCHITECTURE.md); màn hình này
/// chỉ chịu trách nhiệm wiring dependency injection (Provider) và điều hướng gốc.
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
        ProxyProvider<ApiClient, ProfileService>(update: (_, api, __) => ProfileService(api)),
        ProxyProvider<ApiClient, NotificationsService>(update: (_, api, __) => NotificationsService(api)),
        ProxyProvider<ApiClient, EmployerJobsService>(update: (_, api, __) => EmployerJobsService(api)),
      ],
      child: MaterialApp(
        title: 'Việc Nha Trang',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF0F9D58),
          useMaterial3: true,
          textTheme: const TextTheme().apply(fontSizeFactor: 1.05),
        ),
        home: session.isLoggedIn ? const MainNavScaffold() : const PhoneLoginScreen(),
      ),
    );
  }
}
