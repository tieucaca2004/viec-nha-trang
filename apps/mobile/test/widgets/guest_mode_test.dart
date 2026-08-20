import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:viec_nha_trang/core/auth/session.dart';
import 'package:viec_nha_trang/core/network/api_client.dart';
import 'package:viec_nha_trang/features/applications/data/applications_service.dart';
import 'package:viec_nha_trang/features/auth/data/auth_service.dart';
import 'package:viec_nha_trang/features/jobs/data/jobs_service.dart';
import 'package:viec_nha_trang/features/jobs/presentation/home_screen.dart';
import 'package:viec_nha_trang/features/jobs/presentation/job_detail_screen.dart';
import 'package:viec_nha_trang/features/profile/data/job_seeker_profile_service.dart';
import 'package:viec_nha_trang/features/saved_jobs/data/saved_jobs_service.dart';
import '../helpers/in_memory_token_storage.dart';
import '../helpers/json_response.dart';

/// AUTH UX (OTP-FIRST + ZERO-FRICTION ENTRY) - đặc tả Part 12 test 1-8: khách (chưa đăng nhập)
/// duyệt/tìm việc và xem chi tiết KHÔNG cần tài khoản; bấm hành động cần tài khoản (ứng
/// tuyển/lưu việc) mới hỏi xác thực, xác thực xong TỰ ĐỘNG tiếp tục đúng hành động ban đầu -
/// không bị đá về Home, không phải tìm lại job.
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
      ],
      child: MaterialApp(home: child),
    );
  }

  // 1/2/3. Khách mở HomeScreen -> thấy danh sách việc, KHÔNG hiện màn đăng nhập nào.
  testWidgets('1-3. khách xem được danh sách việc làm mà không cần tài khoản', (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/jobs') && request.method == 'GET') {
          return jsonResponse({
            'data': [jobJson],
            'meta': {'total': 1, 'limit': 20, 'offset': 0},
          }, 200);
        }
        if (request.url.path.endsWith('/categories') || request.url.path.endsWith('/areas')) {
          return jsonResponse([], 200);
        }
        // Khách KHÔNG được gọi /applications/me hay /saved-jobs (đặc tả Part 11) - trả 404 nếu bị
        // gọi nhầm để bất kỳ regression nào cũng làm lộ lỗi ngay (thay vì âm thầm 200 rỗng).
        return http.Response('unexpected guest call: ${request.url.path}', 404);
      }),
    );

    await tester.pumpWidget(wrap(api, session, const HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('PHỤC VỤ NHÀ HÀNG'), findsOneWidget);
    expect(session.isLoggedIn, isFalse);
  });

  // 4. Khách mở chi tiết việc làm - vẫn xem được, không lỗi dù /applications/me hay /saved-jobs
  // không được gọi.
  testWidgets('4. khách mở được chi tiết việc làm', (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/jobs/job-1')) {
          return jsonResponse(jobJson, 200);
        }
        return http.Response('unexpected guest call: ${request.url.path}', 404);
      }),
    );

    await tester.pumpWidget(wrap(api, session, const JobDetailScreen(jobId: 'job-1')));
    await tester.pumpAndSettle();

    // Tiêu đề xuất hiện cả ở AppBar và nội dung màn hình (không viết hoa như JobCard).
    expect(find.text('Phục vụ nhà hàng'), findsWidgets);
    expect(find.text('ỨNG TUYỂN 1 CHẠM'), findsOneWidget);
  });

  // 5/6. Khách bấm ỨNG TUYỂN -> hiện lời mời xác thực (KHÔNG gọi /jobs/:id/apply trước khi xác
  // thực) -> OTP đúng -> tự động ứng tuyển tiếp, không cần bấm lại.
  testWidgets('5-6. khách bấm ứng tuyển -> hỏi xác thực -> OTP đúng -> tự động ứng tuyển tiếp', (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    var applyRequested = false;

    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/jobs') && request.method == 'GET') {
          return jsonResponse({
            'data': [jobJson],
            'meta': {'total': 1, 'limit': 20, 'offset': 0},
          }, 200);
        }
        if (request.url.path.endsWith('/categories') || request.url.path.endsWith('/areas')) {
          return jsonResponse([], 200);
        }
        if (request.url.path.endsWith('/auth/otp/request')) {
          return jsonResponse({'expiresInSeconds': 300}, 201);
        }
        if (request.url.path.endsWith('/auth/otp/verify')) {
          return jsonResponse({'accessToken': 'acc-1', 'refreshToken': 'ref-1'}, 201);
        }
        if (request.url.path.endsWith('/me') && request.method == 'GET') {
          return jsonResponse({'id': 'u1', 'roles': ['JOB_SEEKER']}, 200);
        }
        if (request.url.path.endsWith('/jobs/job-1/apply')) {
          applyRequested = true;
          return jsonResponse({'id': 'app-1', 'status': 'NEW'}, 201);
        }
        return http.Response('unexpected call: ${request.url.path}', 404);
      }),
    );

    await tester.pumpWidget(wrap(api, session, const HomeScreen()));
    await tester.pumpAndSettle();

    // Trước khi bấm gì - guest chưa hề gọi apply.
    expect(applyRequested, isFalse);

    await tester.tap(find.text('ỨNG TUYỂN 1 CHẠM'));
    await tester.pumpAndSettle();

    // Lời mời xác thực hiện ra, KHÔNG gọi apply ngay.
    expect(find.text('Để ứng tuyển, bạn cần xác thực số điện thoại.'), findsOneWidget);
    expect(applyRequested, isFalse);

    await tester.tap(find.text('TIẾP TỤC'));
    await tester.pumpAndSettle();

    // Màn xác thực SĐT (contextual, không phải "Đăng nhập" chung chung).
    expect(find.text('Xác thực số điện thoại'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '0912345678');
    await tester.tap(find.text('GỬI MÃ OTP'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('XÁC NHẬN'));
    await tester.pumpAndSettle();

    // Xác thực xong: quay lại đúng HomeScreen, KHÔNG bị đá về đâu khác, và job đã tự ứng tuyển.
    expect(session.isLoggedIn, isTrue);
    expect(applyRequested, isTrue);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Ứng tuyển thành công.'), findsOneWidget);
  });

  // 7/8. Khách bấm Lưu -> hỏi xác thực -> OTP đúng -> tự động lưu tiếp.
  testWidgets('7-8. khách bấm lưu việc -> hỏi xác thực -> OTP đúng -> tự động lưu tiếp', (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    var saveRequested = false;

    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/jobs') && request.method == 'GET') {
          return jsonResponse({
            'data': [jobJson],
            'meta': {'total': 1, 'limit': 20, 'offset': 0},
          }, 200);
        }
        if (request.url.path.endsWith('/categories') || request.url.path.endsWith('/areas')) {
          return jsonResponse([], 200);
        }
        if (request.url.path.endsWith('/auth/otp/request')) {
          return jsonResponse({'expiresInSeconds': 300}, 201);
        }
        if (request.url.path.endsWith('/auth/otp/verify')) {
          return jsonResponse({'accessToken': 'acc-1', 'refreshToken': 'ref-1'}, 201);
        }
        if (request.url.path.endsWith('/me') && request.method == 'GET') {
          return jsonResponse({'id': 'u1', 'roles': ['JOB_SEEKER']}, 200);
        }
        if (request.url.path.endsWith('/saved-jobs/job-1') && request.method == 'POST') {
          saveRequested = true;
          return jsonResponse(null, 201);
        }
        return http.Response('unexpected call: ${request.url.path}', 404);
      }),
    );

    await tester.pumpWidget(wrap(api, session, const HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.bookmark_border));
    await tester.pumpAndSettle();

    expect(find.text('Để lưu việc này, bạn cần xác thực số điện thoại.'), findsOneWidget);
    expect(saveRequested, isFalse);

    await tester.tap(find.text('TIẾP TỤC'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '0912345678');
    await tester.tap(find.text('GỬI MÃ OTP'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('XÁC NHẬN'));
    await tester.pumpAndSettle();

    expect(session.isLoggedIn, isTrue);
    expect(saveRequested, isTrue);
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
  });

  // 9. Phiên đăng nhập hợp lệ sẵn có -> KHÔNG hỏi xác thực, thao tác thẳng.
  testWidgets('9. đã đăng nhập sẵn -> ứng tuyển thẳng, không hỏi xác thực', (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    var applyRequested = false;
    var authPromptShown = false;

    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/jobs') && request.method == 'GET') {
          return jsonResponse({
            'data': [jobJson],
            'meta': {'total': 1, 'limit': 20, 'offset': 0},
          }, 200);
        }
        if (request.url.path.endsWith('/categories') || request.url.path.endsWith('/areas')) {
          return jsonResponse([], 200);
        }
        if (request.url.path.endsWith('/applications/me')) {
          return jsonResponse([], 200);
        }
        if (request.url.path.endsWith('/jobs/job-1/apply')) {
          applyRequested = true;
          return jsonResponse({'id': 'app-1', 'status': 'NEW'}, 201);
        }
        if (request.url.path.contains('otp')) {
          authPromptShown = true;
        }
        return http.Response('unexpected call: ${request.url.path}', 404);
      }),
    );
    await session.setTokens(access: 'fake-access', refresh: 'fake-refresh', roles: ['JOB_SEEKER']);

    await tester.pumpWidget(wrap(api, session, const HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ỨNG TUYỂN 1 CHẠM'));
    await tester.pumpAndSettle();

    expect(find.text('Để ứng tuyển, bạn cần xác thực số điện thoại.'), findsNothing);
    expect(authPromptShown, isFalse);
    expect(applyRequested, isTrue);
  });
}
