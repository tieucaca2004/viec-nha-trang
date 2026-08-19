import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:viec_nha_trang/core/auth/session.dart';
import 'package:viec_nha_trang/core/network/api_client.dart';
import 'package:viec_nha_trang/features/applications/data/applications_service.dart';
import 'package:viec_nha_trang/features/auth/data/auth_service.dart';
import 'package:viec_nha_trang/features/auth/presentation/email_register_screen.dart';
import 'package:viec_nha_trang/features/auth/presentation/onboarding_screen.dart';
import 'package:viec_nha_trang/features/auth/presentation/phone_login_screen.dart';
import 'package:viec_nha_trang/features/employer/data/employer_jobs_service.dart';
import 'package:viec_nha_trang/features/employer/data/employer_profile_service.dart';
import 'package:viec_nha_trang/features/jobs/data/jobs_service.dart';
import 'package:viec_nha_trang/features/notifications/data/notifications_service.dart';
import 'package:viec_nha_trang/features/profile/data/job_seeker_profile_service.dart';
import 'package:viec_nha_trang/features/saved_jobs/data/saved_jobs_service.dart';
import 'package:viec_nha_trang/shared/widgets/main_nav_scaffold.dart';
import '../helpers/in_memory_token_storage.dart';
import '../helpers/json_response.dart';

/// Bọc OnboardingScreen với Session + toàn bộ service mà MainNavScaffold cần khi đăng nhập,
/// giống pattern đã dùng ở home_screen_save_test.dart - MainNavScaffold dựng cả 5 tab qua
/// IndexedStack cùng lúc, nên cần đủ provider để không throw ProviderNotFoundException.
Widget _wrap(Session session) {
  final api = ApiClient(
    session,
    httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/jobs')) {
        return jsonResponse({
          'data': [],
          'meta': {'total': 0, 'limit': 20, 'offset': 0},
        }, 200);
      }
      if (request.url.path.endsWith('/categories') || request.url.path.endsWith('/areas')) {
        return jsonResponse([], 200);
      }
      if (request.url.path.contains('applications') ||
          request.url.path.contains('saved-jobs') ||
          request.url.path.contains('notifications')) {
        return jsonResponse([], 200);
      }
      // /me (ProfileScreen đọc trạng thái xác minh phone thật, đặc tả §4) - trả dữ liệu tối
      // thiểu hợp lệ, không phải /me/job-seeker-profile hay /me/employer-profile (đã match ở
      // nhánh 404 chung bên dưới vì các path đó không kết thúc bằng "/me").
      if (request.url.path.endsWith('/me')) {
        return jsonResponse({'id': 'u1', 'phone': null, 'isPhoneVerified': false, 'roles': session.roles}, 200);
      }
      // Hồ sơ chưa tạo (404) là trạng thái hợp lệ, các service đều xử lý được (xem
      // JobSeekerProfileService.getJobSeekerProfile).
      return http.Response('not found: ${request.url.path}', 404);
    }),
  );
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<Session>.value(value: session),
      Provider<ApiClient>.value(value: api),
      Provider<AuthService>(create: (_) => AuthService(api, session)),
      Provider<JobsService>(create: (_) => JobsService(api)),
      Provider<ApplicationsService>(create: (_) => ApplicationsService(api)),
      Provider<SavedJobsService>(create: (_) => SavedJobsService(api)),
      Provider<JobSeekerProfileService>(create: (_) => JobSeekerProfileService(api)),
      Provider<EmployerProfileService>(create: (_) => EmployerProfileService(api)),
      Provider<NotificationsService>(create: (_) => NotificationsService(api)),
      Provider<EmployerJobsService>(create: (_) => EmployerJobsService(api)),
    ],
    child: const MaterialApp(home: OnboardingScreen()),
  );
}

void main() {
  group('OnboardingScreen (đặc tả §6 Phase 3, sửa lỗi navigation §1)', () {
    testWidgets('shows logo, slogan, and both role choices', (tester) async {
      final session = Session(storage: InMemoryTokenStorage());
      await tester.pumpWidget(_wrap(session));

      expect(find.text('VIỆC NHA TRANG'), findsOneWidget);
      expect(find.textContaining('Ứng tuyển 1 chạm'), findsOneWidget);
      expect(find.text('TÌM VIỆC'), findsOneWidget);
      expect(find.text('TUYỂN NGƯỜI'), findsOneWidget);
    });

    // Sửa lỗi §1 (phase kế tiếp): chưa đăng nhập giờ đi tới đăng ký bằng EMAIL, không còn qua
    // SMS OTP nữa (SMS OTP chỉ dùng để đăng nhập lại tài khoản cũ, qua liên kết trong màn này).
    testWidgets('chưa đăng nhập: chọn TÌM VIỆC điều hướng tới đăng ký email với intendedRole=JOB_SEEKER',
        (tester) async {
      final session = Session(storage: InMemoryTokenStorage());
      await tester.pumpWidget(_wrap(session));

      await tester.tap(find.text('TÌM VIỆC'));
      await tester.pumpAndSettle();

      final registerScreen = tester.widget<EmailRegisterScreen>(find.byType(EmailRegisterScreen));
      expect(registerScreen.intendedRole, 'JOB_SEEKER');
    });

    testWidgets('chưa đăng nhập: chọn TUYỂN NGƯỜI điều hướng tới đăng ký email với intendedRole=EMPLOYER',
        (tester) async {
      final session = Session(storage: InMemoryTokenStorage());
      await tester.pumpWidget(_wrap(session));

      await tester.tap(find.text('TUYỂN NGƯỜI'));
      await tester.pumpAndSettle();

      final registerScreen = tester.widget<EmailRegisterScreen>(find.byType(EmailRegisterScreen));
      expect(registerScreen.intendedRole, 'EMPLOYER');
    });

    // Sửa lỗi navigation §1: đã đăng nhập rồi quay lại Home (OnboardingScreen luôn là route gốc)
    // thì chọn 1 trong 2 thẻ phải vào THẲNG nav của vai trò đó, không bắt đăng nhập lại.
    testWidgets('đã đăng nhập: chọn TÌM VIỆC vào thẳng MainNavScaffold, không qua màn đăng nhập',
        (tester) async {
      final session = Session(storage: InMemoryTokenStorage());
      await session.setTokens(access: 'fake-access', refresh: 'fake-refresh', roles: ['JOB_SEEKER']);
      await tester.pumpWidget(_wrap(session));

      await tester.tap(find.text('TÌM VIỆC'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(PhoneLoginScreen), findsNothing);
      expect(find.byType(MainNavScaffold), findsOneWidget);
      expect(session.activeRole, 'JOB_SEEKER');
    });

    testWidgets('đã đăng nhập: chọn TUYỂN NGƯỜI vào thẳng MainNavScaffold với activeRole=EMPLOYER',
        (tester) async {
      final session = Session(storage: InMemoryTokenStorage());
      await session.setTokens(access: 'fake-access', refresh: 'fake-refresh', roles: ['JOB_SEEKER', 'EMPLOYER']);
      await tester.pumpWidget(_wrap(session));

      await tester.tap(find.text('TUYỂN NGƯỜI'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(PhoneLoginScreen), findsNothing);
      expect(find.byType(MainNavScaffold), findsOneWidget);
      expect(session.activeRole, 'EMPLOYER');
    });

    // Sửa lỗi navigation §1 (#6: không push chồng Home nhiều lần): OnboardingScreen luôn là
    // route đầu tiên - vào MainNavScaffold rồi bấm back phải quay lại đúng Home này, không tạo
    // thêm bản sao Home mới.
    testWidgets('vào MainNavScaffold rồi back thì quay lại đúng Home (không tạo Home mới)', (tester) async {
      final session = Session(storage: InMemoryTokenStorage());
      await session.setTokens(access: 'fake-access', refresh: 'fake-refresh', roles: ['JOB_SEEKER']);
      await tester.pumpWidget(_wrap(session));

      await tester.tap(find.text('TÌM VIỆC'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(MainNavScaffold), findsOneWidget);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop();
      await tester.pumpAndSettle();

      expect(find.byType(MainNavScaffold), findsNothing);
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.text('TÌM VIỆC'), findsOneWidget);
      expect(find.text('TUYỂN NGƯỜI'), findsOneWidget);
      // Vẫn đăng nhập bình thường - back về Home không làm mất session (#8).
      expect(session.isLoggedIn, isTrue);
    });
  });
}
