import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:viec_nha_trang/core/auth/session.dart';
import 'package:viec_nha_trang/core/network/api_client.dart';
import 'package:viec_nha_trang/features/applications/data/applications_service.dart';
import 'package:viec_nha_trang/features/jobs/data/jobs_service.dart';
import 'package:viec_nha_trang/features/jobs/presentation/home_screen.dart';
import 'package:viec_nha_trang/features/jobs/presentation/job_detail_screen.dart';
import 'package:viec_nha_trang/features/profile/data/job_seeker_profile_service.dart';
import 'package:viec_nha_trang/features/saved_jobs/data/saved_jobs_service.dart';
import '../helpers/in_memory_token_storage.dart';
import '../helpers/json_response.dart';

/// Audit toàn bộ flow "TÌM VIỆC" (job seeker) 1/8 → 8/8: KHÔNG có wizard nhiều bước nào cho
/// job seeker trong source (chỉ Employer PostJobWizardScreen có 8 bước) - luồng thật là
/// HomeScreen (search/filter) -> JobDetailScreen (ứng tuyển/lưu) -> hồ sơ/đơn ứng tuyển. Suite
/// này khoá lại 2 bug thật tìm thấy khi audit lại đúng class lỗi "một API phụ fail làm mất dữ
/// liệu của API khác" mà project đã sửa ở PostJobWizardScreen/JobSeekerProfileFormScreen nhưng
/// còn sót ở 2 chỗ khác.
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
  const categoriesJson = [
    {'id': 'cat-1', 'name': 'Phục vụ', 'icon': null},
  ];
  Widget wrapHome(ApiClient api, Session session) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<Session>.value(value: session),
        Provider<ApiClient>.value(value: api),
        Provider<JobsService>(create: (_) => JobsService(api)),
        Provider<ApplicationsService>(create: (_) => ApplicationsService(api)),
        Provider<SavedJobsService>(create: (_) => SavedJobsService(api)),
      ],
      child: const MaterialApp(home: HomeScreen()),
    );
  }

  Widget wrapDetail(ApiClient api, Session session) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<Session>.value(value: session),
        Provider<ApiClient>.value(value: api),
        Provider<JobsService>(create: (_) => JobsService(api)),
        Provider<ApplicationsService>(create: (_) => ApplicationsService(api)),
        Provider<SavedJobsService>(create: (_) => SavedJobsService(api)),
        Provider<JobSeekerProfileService>(create: (_) => JobSeekerProfileService(api)),
      ],
      child: const MaterialApp(home: JobDetailScreen(jobId: 'job-1')),
    );
  }

  // ---------- HomeScreen bộ lọc: categories/areas phải độc lập ----------

  testWidgets(
      'HomeScreen: /areas lỗi (500) KHÔNG làm mất categories đã tải được cho bộ lọc (cùng lớp lỗi PostJobWizard)',
      (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/jobs') && request.method == 'GET') {
          return jsonResponse({
            'data': [jobJson],
            'meta': {'total': 1, 'limit': 20, 'offset': 0},
          }, 200);
        }
        if (path.endsWith('/categories')) return jsonResponse(categoriesJson, 200);
        if (path.endsWith('/areas')) return jsonResponse({'message': 'Hệ thống đang bận'}, 500);
        return http.Response('unexpected: $path', 404);
      }),
    );

    await tester.pumpWidget(wrapHome(api, session));
    await tester.pumpAndSettle();

    // Mở bộ lọc: danh mục (categories) vẫn phải có trong sheet dù /areas lỗi.
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();

    expect(find.text('Phục vụ'), findsWidgets, reason: 'categories phải hiển thị dù /areas lỗi (bug đã sửa)');
  });

  // ---------- JobDetailScreen ỨNG TUYỂN: lỗi khi kiểm tra hồ sơ không được im lặng ----------

  testWidgets(
      'JobDetailScreen: getJobSeekerProfile() lỗi 500 khi bấm ỨNG TUYỂN -> hiện thông báo lỗi, KHÔNG im lặng',
      (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    await session.setTokens(access: 'fake-access', refresh: 'fake-refresh', roles: ['JOB_SEEKER']);
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/jobs/job-1')) return jsonResponse(jobJson, 200);
        if (path.endsWith('/applications/me')) return jsonResponse([], 200);
        if (path.endsWith('/saved-jobs') && request.method == 'GET') return jsonResponse([], 200);
        if (path.endsWith('/me/job-seeker-profile')) {
          return jsonResponse({'message': 'Hệ thống đang bận'}, 500);
        }
        return http.Response('unexpected: $path', 404);
      }),
    );

    await tester.pumpWidget(wrapDetail(api, session));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ỨNG TUYỂN 1 CHẠM'));
    await tester.pumpAndSettle();

    // Trước khi sửa: bấm xong không có gì xảy ra (không loading, không thông báo, không dialog
    // xác nhận ứng tuyển). Sau khi sửa: phải thấy SnackBar báo lỗi rõ ràng.
    expect(find.text('Hệ thống đang bận. Vui lòng thử lại sau.'), findsOneWidget);
    // Không được vô tình mở dialog xác nhận ứng tuyển khi chưa biết hồ sơ có đủ điều kiện không.
    expect(find.text('Bạn muốn ứng tuyển công việc này?'), findsNothing);
  });

  testWidgets('JobDetailScreen: getJobSeekerProfile() 404 (chưa có hồ sơ) vẫn dẫn tới màn hoàn thiện hồ sơ như cũ',
      (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    await session.setTokens(access: 'fake-access', refresh: 'fake-refresh', roles: ['JOB_SEEKER']);
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/jobs/job-1')) return jsonResponse(jobJson, 200);
        if (path.endsWith('/applications/me')) return jsonResponse([], 200);
        if (path.endsWith('/saved-jobs') && request.method == 'GET') return jsonResponse([], 200);
        if (path.endsWith('/me/job-seeker-profile')) {
          return jsonResponse({'message': 'Not Found'}, 404);
        }
        return http.Response('unexpected: $path', 404);
      }),
    );

    await tester.pumpWidget(wrapDetail(api, session));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ỨNG TUYỂN 1 CHẠM'));
    await tester.pumpAndSettle();

    expect(find.text('Hoàn thiện hồ sơ để ứng tuyển'), findsOneWidget);
  });

  // ---------- Phần G/D (phase QA Job Seeker): double-tap ỨNG TUYỂN chỉ gửi 1 POST ----------

  testWidgets('JobDetailScreen: double-tap ỨNG TUYỂN 1 CHẠM chỉ gửi ĐÚNG 1 POST /jobs/:id/apply', (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    await session.setTokens(access: 'fake-access', refresh: 'fake-refresh', roles: ['JOB_SEEKER']);
    var applyCallCount = 0;
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/jobs/job-1')) return jsonResponse(jobJson, 200);
        if (path.endsWith('/applications/me')) return jsonResponse([], 200);
        if (path.endsWith('/saved-jobs') && request.method == 'GET') return jsonResponse([], 200);
        if (path.endsWith('/me/job-seeker-profile')) return jsonResponse({'fullName': 'Nguyễn Văn A'}, 200);
        if (path.endsWith('/jobs/job-1/apply') && request.method == 'POST') {
          applyCallCount += 1;
          return jsonResponse({'id': 'app-1', 'status': 'NEW', 'job': jobJson}, 201);
        }
        return http.Response('unexpected: ${request.method} $path', 404);
      }),
    );

    await tester.pumpWidget(wrapDetail(api, session));
    await tester.pumpAndSettle();

    // Bấm 2 lần liên tiếp KHÔNG chờ profile fetch xong ở giữa - _applying chỉ được set true SAU
    // khi getJobSeekerProfile() trả về và qua dialog xác nhận, nên nếu không có chốt chặn ở đầu
    // _apply(), 2 lần bấm gần nhau đều lọt qua và mỗi lần đều tự mở dialog xác nhận riêng.
    await tester.tap(find.text('ỨNG TUYỂN 1 CHẠM'));
    await tester.tap(find.text('ỨNG TUYỂN 1 CHẠM'), warnIfMissed: false);
    await tester.pumpAndSettle();

    // Xác nhận dialog (có thể có 1 hoặc nhiều dialog xếp chồng tuỳ bug có tồn tại hay không) -
    // bấm ỨNG TUYỂN trên dialog đang hiện tới khi không còn dialog nào.
    while (find.text('Bạn muốn ứng tuyển công việc này?').evaluate().isNotEmpty) {
      await tester.tap(find.widgetWithText(FilledButton, 'ỨNG TUYỂN').last);
      await tester.pumpAndSettle();
    }

    expect(applyCallCount, 1, reason: 'double-tap không được gửi 2 request ứng tuyển');
  });
}
