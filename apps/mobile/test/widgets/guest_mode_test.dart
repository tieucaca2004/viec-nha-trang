import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:viec_nha_trang/core/auth/session.dart';
import 'package:viec_nha_trang/core/network/api_client.dart';
import 'package:viec_nha_trang/features/applications/data/applications_service.dart';
import 'package:viec_nha_trang/features/auth/data/auth_service.dart';
import 'package:viec_nha_trang/features/auth/presentation/auth_gate_screen.dart';
import 'package:viec_nha_trang/features/auth/presentation/email_register_screen.dart';
import 'package:viec_nha_trang/features/auth/presentation/login_screen.dart';
import 'package:viec_nha_trang/features/auth/presentation/onboarding_screen.dart';
import 'package:viec_nha_trang/features/auth/presentation/phone_login_screen.dart';
import 'package:viec_nha_trang/features/employer/data/employer_jobs_service.dart';
import 'package:viec_nha_trang/features/employer/data/employer_profile_service.dart';
import 'package:viec_nha_trang/features/employer/presentation/employer_entry_screen.dart';
import 'package:viec_nha_trang/features/employer/presentation/post_job_wizard_screen.dart';
import 'package:viec_nha_trang/features/jobs/data/jobs_service.dart';
import 'package:viec_nha_trang/features/jobs/presentation/home_screen.dart';
import 'package:viec_nha_trang/features/jobs/presentation/job_detail_screen.dart';
import 'package:viec_nha_trang/features/notifications/data/notifications_service.dart';
import 'package:viec_nha_trang/features/profile/data/job_seeker_profile_service.dart';
import 'package:viec_nha_trang/features/saved_jobs/data/saved_jobs_service.dart';
import 'package:viec_nha_trang/shared/widgets/main_nav_scaffold.dart';
import '../helpers/in_memory_token_storage.dart';
import '../helpers/json_response.dart';

/// AUTH UX - OTP-first + Guest Browse. Khoá đúng các quy tắc sản phẩm:
/// - Mở app KHÔNG bao giờ hiện Login/Register; khách duyệt/tìm/xem việc ngay.
/// - Hành động cần tài khoản (ứng tuyển/lưu việc/đăng tin) mới hỏi, và hỏi bằng LỰA CHỌN
///   Đăng nhập / Đăng ký - KHÔNG nhảy thẳng vào "Xác thực số điện thoại" (bug thật đã sửa).
/// - Đăng ký = EMAIL + EMAIL OTP.
/// - Xác thực xong quay lại ĐÚNG hành động ban đầu, không về Home.
void main() {
  const jobJson = {
    'id': 'job-1',
    'title': 'Phục vụ nhà hàng',
    'employer': {'id': 'e1', 'businessName': 'Quán Test', 'verificationLevel': 'UNVERIFIED'},
    'salaryMin': 20000,
    'salaryMax': 25000,
    'salaryUnit': 'HOUR',
    'employmentType': 'PART_TIME',
    'status': 'ACTIVE',
  };

  Widget wrap(ApiClient api, Session session, Widget child) {
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
      child: MaterialApp(home: child),
    );
  }

  /// Handler dùng chung: danh sách việc công khai + bộ endpoint EMAIL OTP (đăng ký/đăng nhập).
  /// Mọi path không khai báo -> 404 để bất kỳ request thừa nào của khách cũng lộ ra ngay.
  MockClient buildClient({
    void Function(String path)? onCall,
    Map<String, http.Response> extra = const {},
  }) {
    return MockClient((request) async {
      final path = request.url.path;
      onCall?.call('${request.method} $path');

      for (final entry in extra.entries) {
        if (path.endsWith(entry.key)) return entry.value;
      }
      if (path.endsWith('/jobs') && request.method == 'GET') {
        return jsonResponse({
          'data': [jobJson],
          'meta': {'total': 1, 'limit': 20, 'offset': 0},
        }, 200);
      }
      if (path.endsWith('/jobs/job-1')) return jsonResponse(jobJson, 200);
      if (path.endsWith('/categories') || path.endsWith('/areas') || path.endsWith('/cities')) {
        return jsonResponse([], 200);
      }
      // Đăng ký + đăng nhập đều đi qua EMAIL OTP, nhưng qua 2 route/throttle bucket RIÊNG (xem
      // otp_cooldown.dart) - EmailRegisterScreen gọi register/email/*, LoginScreen gọi login/email/*.
      if (path.endsWith('/auth/register/email/request')) return jsonResponse({'expiresInSeconds': 600}, 201);
      if (path.endsWith('/auth/register/email/verify')) {
        return jsonResponse({'accessToken': 'acc-1', 'refreshToken': 'ref-1'}, 201);
      }
      if (path.endsWith('/auth/login/email/request')) return jsonResponse({'expiresInSeconds': 600}, 201);
      if (path.endsWith('/auth/login/email/verify')) {
        return jsonResponse({'accessToken': 'acc-1', 'refreshToken': 'ref-1'}, 201);
      }
      if (path.endsWith('/auth/otp/request')) return jsonResponse({'expiresInSeconds': 300}, 201);
      if (path.endsWith('/auth/otp/verify')) {
        return jsonResponse({'accessToken': 'acc-1', 'refreshToken': 'ref-1'}, 201);
      }
      if (path.endsWith('/me') && request.method == 'GET') {
        return jsonResponse({'id': 'u1', 'phone': null, 'isPhoneVerified': false, 'roles': ['JOB_SEEKER']}, 200);
      }
      return http.Response('unexpected call: $path', 404);
    });
  }

  /// Đi hết luồng ĐĂNG KÝ bằng email từ màn AuthGateScreen đang hiển thị.
  Future<void> registerWithEmail(WidgetTester tester) async {
    await tester.tap(find.text('ĐĂNG KÝ TÀI KHOẢN MỚI'));
    await tester.pumpAndSettle();
    expect(find.byType(EmailRegisterScreen), findsOneWidget);

    await tester.enterText(
      find.descendant(of: find.byType(EmailRegisterScreen), matching: find.byType(TextField)),
      'nguoidung@example.test',
    );
    await tester.tap(find.text('GỬI MÃ XÁC MINH'));
    await tester.pumpAndSettle();

    // EMAIL OTP - không phải SĐT.
    expect(find.textContaining('nguoidung@example.test'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('XÁC NHẬN'));
    await tester.pumpAndSettle();
  }

  // ---------- A. Khởi động không có phiên -> Guest Browse ----------

  testWidgets('A. mở app khi chưa đăng nhập -> Guest Browse, KHÔNG hiện Login/Register', (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    await tester.pumpWidget(wrap(ApiClient(session, httpClient: buildClient()), session, const OnboardingScreen()));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(EmailRegisterScreen), findsNothing);
    expect(find.byType(PhoneLoginScreen), findsNothing);
    expect(find.text('TÌM VIỆC'), findsOneWidget);

    await tester.tap(find.text('TÌM VIỆC'));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('PHỤC VỤ NHÀ HÀNG'), findsOneWidget);
    expect(session.isLoggedIn, isFalse);
  });

  // ---------- B. Khởi động có phiên hợp lệ -> vào thẳng app ----------

  testWidgets('B. mở app khi đã có phiên hợp lệ -> vào thẳng app, KHÔNG hiện Login/Register', (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    await session.setTokens(access: 'acc-1', refresh: 'ref-1', roles: ['JOB_SEEKER']);
    final api = ApiClient(
      session,
      httpClient: buildClient(extra: {
        '/applications/me': jsonResponse([], 200),
        '/saved-jobs': jsonResponse([], 200),
        '/notifications': jsonResponse([], 200),
        '/me/job-seeker-profile': jsonResponse(null, 404),
        '/me/employer-profile': jsonResponse(null, 404),
      }),
    );

    await tester.pumpWidget(wrap(api, session, const OnboardingScreen()));
    await tester.tap(find.text('TÌM VIỆC'));
    await tester.pumpAndSettle();

    expect(find.byType(MainNavScaffold), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(EmailRegisterScreen), findsNothing);
  });

  // ---------- C. Khách -> Tuyển người -> Đăng tin ngay ----------

  testWidgets('C. khách bấm ĐĂNG TIN NGAY -> hiện lựa chọn Đăng nhập/Đăng ký, KHÔNG phải màn OTP SĐT',
      (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    await tester.pumpWidget(wrap(ApiClient(session, httpClient: buildClient()), session, const EmployerEntryScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ĐĂNG TIN NGAY'));
    await tester.pumpAndSettle();

    // Bug thật đã sửa: trước đây bước này nhảy thẳng sang "Xác thực số điện thoại".
    expect(find.byType(AuthGateScreen), findsOneWidget);
    expect(find.byType(PhoneLoginScreen), findsNothing);
    expect(find.text('Xác thực số điện thoại'), findsNothing);
    expect(find.text('Số điện thoại'), findsNothing);

    expect(find.text('Để đăng tin tuyển dụng, bạn cần đăng nhập hoặc tạo tài khoản.'), findsOneWidget);
    expect(find.text('ĐĂNG KÝ TÀI KHOẢN MỚI'), findsOneWidget);
    expect(find.text('TÔI ĐÃ CÓ TÀI KHOẢN'), findsOneWidget);
  });

  testWidgets('C+D. khách -> ĐĂNG TIN NGAY -> đăng ký email OTP -> vào THẲNG wizard đăng tin', (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    final api = ApiClient(
      session,
      httpClient: buildClient(extra: {
        '/me/roles': jsonResponse({'roles': ['JOB_SEEKER', 'EMPLOYER']}, 200),
        '/me/employer-profile/locations': jsonResponse([], 200),
      }),
    );

    await tester.pumpWidget(wrap(api, session, const EmployerEntryScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ĐĂNG TIN NGAY'));
    await tester.pumpAndSettle();

    await registerWithEmail(tester);

    expect(session.isLoggedIn, isTrue);
    expect(session.activeRole, 'EMPLOYER');
    // Tiếp tục ĐÚNG việc vừa bấm - không bị đá về Home/nav rồi phải tìm lại nút đăng tin.
    expect(find.byType(PostJobWizardScreen), findsOneWidget);
  });

  // ---------- E. Khách -> Ứng tuyển ----------

  testWidgets('E. khách bấm ứng tuyển -> Đăng ký email OTP -> quay lại đúng job và ứng tuyển tiếp', (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    var applyRequested = false;

    final api = ApiClient(
      session,
      httpClient: buildClient(
        onCall: (call) {
          if (call.contains('/jobs/job-1/apply')) applyRequested = true;
        },
        extra: {'/jobs/job-1/apply': jsonResponse({'id': 'app-1', 'status': 'NEW'}, 201)},
      ),
    );

    await tester.pumpWidget(wrap(api, session, const HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ỨNG TUYỂN 1 CHẠM'));
    await tester.pumpAndSettle();

    expect(find.text('Để ứng tuyển, bạn cần đăng nhập hoặc tạo tài khoản.'), findsOneWidget);
    expect(applyRequested, isFalse);

    await registerWithEmail(tester);

    expect(session.isLoggedIn, isTrue);
    expect(applyRequested, isTrue);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Ứng tuyển thành công.'), findsOneWidget);
  });

  // ---------- F. Khách -> Lưu việc ----------

  testWidgets('F. khách bấm lưu việc -> Đăng ký email OTP -> quay lại đúng job và lưu tiếp', (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    var saveRequested = false;

    final api = ApiClient(
      session,
      httpClient: buildClient(
        onCall: (call) {
          if (call.startsWith('POST') && call.contains('/saved-jobs/job-1')) saveRequested = true;
        },
        extra: {'/saved-jobs/job-1': jsonResponse(null, 201)},
      ),
    );

    await tester.pumpWidget(wrap(api, session, const HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.bookmark_border));
    await tester.pumpAndSettle();

    expect(find.text('Để lưu việc này, bạn cần đăng nhập hoặc tạo tài khoản.'), findsOneWidget);
    expect(saveRequested, isFalse);

    await registerWithEmail(tester);

    expect(session.isLoggedIn, isTrue);
    expect(saveRequested, isTrue);
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
  });

  // ---------- G. Người dùng đã có tài khoản -> Đăng nhập ----------

  testWidgets('G. khách chọn "TÔI ĐÃ CÓ TÀI KHOẢN" -> đăng nhập bằng email OTP -> tiếp tục hành động', (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    var applyRequested = false;

    final api = ApiClient(
      session,
      httpClient: buildClient(
        onCall: (call) {
          if (call.contains('/jobs/job-1/apply')) applyRequested = true;
        },
        extra: {'/jobs/job-1/apply': jsonResponse({'id': 'app-1', 'status': 'NEW'}, 201)},
      ),
    );

    await tester.pumpWidget(wrap(api, session, const HomeScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ỨNG TUYỂN 1 CHẠM'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('TÔI ĐÃ CÓ TÀI KHOẢN'));
    await tester.pumpAndSettle();

    // Màn Đăng nhập THẬT, dùng email OTP (kiến trúc OTP-first, không mật khẩu).
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('GỬI MÃ ĐĂNG NHẬP'), findsOneWidget);
    expect(find.text('Mật khẩu'), findsNothing);

    await tester.enterText(
      find.descendant(of: find.byType(LoginScreen), matching: find.byType(TextField)),
      'nguoicu@example.test',
    );
    await tester.tap(find.text('GỬI MÃ ĐĂNG NHẬP'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('XÁC NHẬN'));
    await tester.pumpAndSettle();

    expect(session.isLoggedIn, isTrue);
    expect(applyRequested, isTrue);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('G2. màn Đăng nhập vẫn giữ lối đăng nhập bằng SĐT cho tài khoản cũ', (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    await tester.pumpWidget(wrap(ApiClient(session, httpClient: buildClient()), session, const LoginScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tài khoản cũ tạo bằng số điện thoại? Đăng nhập bằng SĐT'));
    await tester.pumpAndSettle();

    expect(find.byType(PhoneLoginScreen), findsOneWidget);
  });

  // ---------- H. Phiên hết hạn ----------

  testWidgets('H. phiên hết hạn (refresh cũng hỏng) -> về guest, app không crash, vẫn duyệt việc được',
      (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    await session.setTokens(access: 'expired', refresh: 'expired', roles: ['JOB_SEEKER']);

    final api = ApiClient(
      session,
      httpClient: buildClient(extra: {
        '/applications/me': jsonResponse({'message': 'hết hạn'}, 401),
        '/saved-jobs': jsonResponse({'message': 'hết hạn'}, 401),
        '/auth/refresh': jsonResponse({'message': 'hết hạn'}, 401),
      }),
    );

    await tester.pumpWidget(wrap(api, session, const HomeScreen()));
    await tester.pumpAndSettle();

    // ApiClient tự thu hồi phiên hỏng -> guest; danh sách việc công khai vẫn hiển thị bình thường.
    expect(session.isLoggedIn, isFalse);
    expect(find.text('PHỤC VỤ NHÀ HÀNG'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ---------- Khách xem chi tiết việc ----------

  testWidgets('khách mở được chi tiết việc làm mà không cần tài khoản', (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    await tester.pumpWidget(wrap(ApiClient(session, httpClient: buildClient()), session, const JobDetailScreen(jobId: 'job-1')));
    await tester.pumpAndSettle();

    expect(find.text('Phục vụ nhà hàng'), findsWidgets);
    expect(find.text('ỨNG TUYỂN 1 CHẠM'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });

  // ---------- Đã đăng nhập: không hỏi xác thực ----------

  testWidgets('đã đăng nhập sẵn -> ứng tuyển thẳng, KHÔNG hỏi đăng nhập/đăng ký', (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    await session.setTokens(access: 'acc-1', refresh: 'ref-1', roles: ['JOB_SEEKER']);
    var applyRequested = false;

    final api = ApiClient(
      session,
      httpClient: buildClient(
        onCall: (call) {
          if (call.contains('/jobs/job-1/apply')) applyRequested = true;
        },
        extra: {
          '/jobs/job-1/apply': jsonResponse({'id': 'app-1', 'status': 'NEW'}, 201),
          '/applications/me': jsonResponse([], 200),
          '/saved-jobs': jsonResponse([], 200),
        },
      ),
    );

    await tester.pumpWidget(wrap(api, session, const HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ỨNG TUYỂN 1 CHẠM'));
    await tester.pumpAndSettle();

    expect(find.byType(AuthGateScreen), findsNothing);
    expect(applyRequested, isTrue);
  });
}
