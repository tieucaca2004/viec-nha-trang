import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:viec_nha_trang/core/auth/session.dart';
import 'package:viec_nha_trang/core/network/api_client.dart';
import 'package:viec_nha_trang/core/network/api_exception.dart';
import 'package:viec_nha_trang/features/employer/data/employer_jobs_service.dart';
import 'package:viec_nha_trang/features/employer/data/employer_profile_service.dart';
import 'package:viec_nha_trang/features/employer/presentation/post_job_wizard_screen.dart';
import 'package:viec_nha_trang/features/jobs/data/jobs_service.dart';
import 'package:viec_nha_trang/features/profile/data/job_seeker_profile_service.dart';
import 'package:viec_nha_trang/features/profile/presentation/job_seeker_profile_form_screen.dart';
import '../helpers/in_memory_token_storage.dart';
import '../helpers/json_response.dart';

/// Regression cho bug thật trên Beta: "Đăng tuyển (1/8) - Bạn cần tuyển vị trí nào?" hiện ra
/// nhưng BÊN DƯỚI TRỐNG TRƠN và nút TIẾP TỤC bị mờ, dù GET /categories trả về dữ liệu hợp lệ.
///
/// Nguyên nhân: categories và locations được await TUẦN TỰ trong cùng 1 try/catch, setState chỉ
/// chạy sau CẢ HAI - chỉ cần locations lỗi là categories đã tải được cũng bị vứt đi.
/// Cùng lớp lỗi ở màn hồ sơ người tìm việc (categories + areas).
void main() {
  const categoriesJson = [
    {'id': 'cat-1', 'name': 'Phục vụ', 'icon': null},
    {'id': 'cat-2', 'name': 'Phụ bếp', 'icon': null},
  ];

  Widget wrap(ApiClient api, Session session, Widget child) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<Session>.value(value: session),
        Provider<ApiClient>.value(value: api),
        Provider<JobsService>(create: (_) => JobsService(api)),
        Provider<EmployerProfileService>(create: (_) => EmployerProfileService(api)),
        Provider<EmployerJobsService>(create: (_) => EmployerJobsService(api)),
        Provider<JobSeekerProfileService>(create: (_) => JobSeekerProfileService(api)),
      ],
      child: MaterialApp(home: child),
    );
  }

  Session loggedInSession() {
    final session = Session(storage: InMemoryTokenStorage());
    session.accessToken = 'acc-1';
    session.refreshToken = 'ref-1';
    session.roles = ['JOB_SEEKER', 'EMPLOYER'];
    return session;
  }

  // ---------- M/N/Q. PostJobWizard bước 1 ----------

  testWidgets('M/N. bước 1 hiện danh sách ngành nghề; chọn xong TIẾP TỤC được bật', (tester) async {
    final session = loggedInSession();
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/categories')) return jsonResponse(categoriesJson, 200);
        if (request.url.path.endsWith('/me/employer-profile/locations')) return jsonResponse([], 200);
        return http.Response('unexpected: ${request.url.path}', 404);
      }),
    );

    await tester.pumpWidget(wrap(api, session, const PostJobWizardScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Bạn cần tuyển vị trí nào?'), findsOneWidget);
    expect(find.text('Phục vụ'), findsOneWidget);
    expect(find.text('Phụ bếp'), findsOneWidget);

    // Chưa chọn -> TIẾP TỤC disabled.
    FilledButton nextButton() => tester.widget<FilledButton>(
          find.ancestor(of: find.text('TIẾP TỤC'), matching: find.byType(FilledButton)),
        );
    expect(nextButton().onPressed, isNull);

    await tester.tap(find.text('Phục vụ'));
    await tester.pumpAndSettle();

    expect(nextButton().onPressed, isNotNull);
  });

  // Đây chính là kịch bản gây blank screen trên Beta: nhà tuyển dụng MỚI chưa có cơ sở nào nên
  // locations lỗi, nhưng categories vẫn phải hiển thị bình thường.
  testWidgets('M. locations lỗi vẫn KHÔNG làm mất danh sách ngành nghề (bug blank screen)', (tester) async {
    final session = loggedInSession();
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/categories')) return jsonResponse(categoriesJson, 200);
        if (request.url.path.endsWith('/me/employer-profile/locations')) {
          return jsonResponse({'message': 'Chưa có hồ sơ nhà tuyển dụng.'}, 404);
        }
        return http.Response('unexpected: ${request.url.path}', 404);
      }),
    );

    await tester.pumpWidget(wrap(api, session, const PostJobWizardScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Phục vụ'), findsOneWidget);
    expect(find.text('Phụ bếp'), findsOneWidget);
    expect(find.text('THỬ LẠI'), findsNothing);
  });

  testWidgets('Q. ngành nghề đã chọn được giữ khi đi tiếp rồi quay lại bước 1', (tester) async {
    final session = loggedInSession();
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/categories')) return jsonResponse(categoriesJson, 200);
        if (request.url.path.endsWith('/me/employer-profile/locations')) return jsonResponse([], 200);
        return http.Response('unexpected: ${request.url.path}', 404);
      }),
    );

    await tester.pumpWidget(wrap(api, session, const PostJobWizardScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Phụ bếp'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TIẾP TỤC'));
    await tester.pumpAndSettle();
    expect(find.text('Đăng tuyển (2/8)'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('Đăng tuyển (1/8)'), findsOneWidget);
    final chip = tester.widget<ChoiceChip>(
      find.ancestor(of: find.text('Phụ bếp'), matching: find.byType(ChoiceChip)),
    );
    expect(chip.selected, isTrue);
  });

  // ---------- O. Trạng thái đang tải ----------

  testWidgets('O. đang tải categories -> hiện loading rõ ràng, KHÔNG blank', (tester) async {
    final session = loggedInSession();
    final categoriesGate = Completer<void>();
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/categories')) {
          await categoriesGate.future; // giữ request treo để quan sát trạng thái loading
          return jsonResponse(categoriesJson, 200);
        }
        if (request.url.path.endsWith('/me/employer-profile/locations')) return jsonResponse([], 200);
        return http.Response('unexpected: ${request.url.path}', 404);
      }),
    );

    await tester.pumpWidget(wrap(api, session, const PostJobWizardScreen()));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    categoriesGate.complete();
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Phục vụ'), findsOneWidget);
  });

  // ---------- P. Lỗi API -> error + retry, không blank ----------

  testWidgets('P. categories lỗi -> hiện lỗi + THỬ LẠI, bấm lại tải thành công', (tester) async {
    final session = loggedInSession();
    var categoriesCalls = 0;
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/categories')) {
          categoriesCalls += 1;
          if (categoriesCalls == 1) return jsonResponse({'message': 'Hệ thống đang bận'}, 500);
          return jsonResponse(categoriesJson, 200);
        }
        if (request.url.path.endsWith('/me/employer-profile/locations')) return jsonResponse([], 200);
        return http.Response('unexpected: ${request.url.path}', 404);
      }),
    );

    await tester.pumpWidget(wrap(api, session, const PostJobWizardScreen()));
    await tester.pumpAndSettle();

    // KHÔNG được trắng trơn: phải có thông báo lỗi và nút thử lại.
    expect(find.text('THỬ LẠI'), findsOneWidget);
    expect(find.textContaining('Hệ thống đang bận'), findsOneWidget);

    await tester.tap(find.text('THỬ LẠI'));
    await tester.pumpAndSettle();

    expect(find.text('Phục vụ'), findsOneWidget);
    expect(find.text('THỬ LẠI'), findsNothing);
  });

  // ---------- R/S/T/U. Màn hồ sơ người tìm việc dùng CHUNG nguồn categories ----------

  testWidgets('R/S. hồ sơ người tìm việc hiện ngành nghề từ cùng GET /categories', (tester) async {
    final session = loggedInSession();
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/categories')) return jsonResponse(categoriesJson, 200);
        if (request.url.path.endsWith('/areas')) return jsonResponse([], 200);
        return http.Response('unexpected: ${request.url.path}', 404);
      }),
    );

    await tester.pumpWidget(wrap(api, session, const JobSeekerProfileFormScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    expect(find.text('Phục vụ').hitTestable(), findsOneWidget);
  });

  testWidgets('U. hồ sơ: /areas lỗi vẫn KHÔNG làm mất danh sách ngành nghề', (tester) async {
    final session = loggedInSession();
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/categories')) return jsonResponse(categoriesJson, 200);
        if (request.url.path.endsWith('/areas')) return jsonResponse({'message': 'Hệ thống đang bận'}, 500);
        return http.Response('unexpected: ${request.url.path}', 404);
      }),
    );

    await tester.pumpWidget(wrap(api, session, const JobSeekerProfileFormScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    expect(find.text('Phục vụ').hitTestable(), findsOneWidget);
  });

  // ---------- T. Hồ sơ đã có -> preselect đúng ----------

  testWidgets('T. hồ sơ đã có ngành nghề -> preselect đúng giá trị cũ', (tester) async {
    final session = loggedInSession();
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/categories')) return jsonResponse(categoriesJson, 200);
        if (request.url.path.endsWith('/areas')) return jsonResponse([], 200);
        return http.Response('unexpected: ${request.url.path}', 404);
      }),
    );

    await tester.pumpWidget(wrap(
      api,
      session,
      const JobSeekerProfileFormScreen(existing: {'fullName': 'Nguyễn Văn A', 'desiredCategoryId': 'cat-2'}),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Phụ bếp'), findsOneWidget);
  });

  // ---------- K. Thông báo throttle chính xác theo Retry-After ----------

  test('K. 429 kèm Retry-After -> báo đúng số giây phải chờ, không nói chung chung', () {
    final withHeader = ApiException(429, 'ThrottlerException: Too Many Requests', retryAfterSeconds: 43);
    expect(withHeader.userMessage, 'Bạn đã yêu cầu quá nhiều lần. Vui lòng chờ 43 giây rồi thử lại.');

    final withoutHeader = ApiException(429, 'ThrottlerException: Too Many Requests');
    expect(withoutHeader.userMessage, 'Bạn thao tác quá nhanh. Vui lòng thử lại sau ít phút.');
  });
}
