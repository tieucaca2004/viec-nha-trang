import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:viec_nha_trang/core/auth/session.dart';
import 'package:viec_nha_trang/core/network/api_client.dart';
import 'package:viec_nha_trang/features/auth/data/auth_service.dart';
import 'package:viec_nha_trang/features/employer/data/employer_jobs_service.dart';
import 'package:viec_nha_trang/features/employer/data/employer_profile_service.dart';
import 'package:viec_nha_trang/features/employer/data/geocoding_service.dart';
import 'package:viec_nha_trang/features/employer/presentation/post_job_wizard_screen.dart';
import 'package:viec_nha_trang/features/jobs/data/jobs_service.dart';
import '../helpers/in_memory_token_storage.dart';
import '../helpers/json_response.dart';

/// QA toàn bộ wizard đăng tuyển 1/8 -> 8/8 (bước cuối + payload + double submit).
///
/// Bổ sung cho post_job_wizard_location_test.dart (đã khoá riêng bước 5/8 "Địa điểm").
void main() {
  const categoriesJson = [
    {'id': 'cat-1', 'name': 'Phục vụ', 'icon': null},
  ];
  const locationsJson = [
    {'id': 'loc-1', 'name': 'Chi nhánh Vĩnh Hải'},
  ];

  Widget wrap(ApiClient api, Session session) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<Session>.value(value: session),
        Provider<ApiClient>.value(value: api),
        Provider<JobsService>(create: (_) => JobsService(api)),
        Provider<EmployerProfileService>(create: (_) => EmployerProfileService(api)),
        Provider<EmployerJobsService>(create: (_) => EmployerJobsService(api)),
        Provider<AuthService>(create: (_) => AuthService(api, session)),
        Provider<GeocodingService>.value(
          value: GeocodingService(client: MockClient((_) async => http.Response('[]', 200))),
        ),
      ],
      child: const MaterialApp(home: PostJobWizardScreen()),
    );
  }

  Session loggedInSession() {
    final session = Session(storage: InMemoryTokenStorage());
    session.accessToken = 'acc-1';
    session.refreshToken = 'ref-1';
    session.roles = ['JOB_SEEKER', 'EMPLOYER'];
    return session;
  }

  ApiClient apiFor(MockClient client, Session session) => ApiClient(session, httpClient: client);

  MockClient wizardBackend({
    required void Function(Map<String, dynamic> body) onCreateJob,
    Future<void> Function()? createJobGate,
    http.Response Function()? createJobResponse,
  }) {
    return MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/categories')) return jsonResponse(categoriesJson, 200);
      if (path.endsWith('/me/employer-profile/locations')) return jsonResponse(locationsJson, 200);
      if (path.endsWith('/jobs') && request.method == 'POST') {
        onCreateJob(jsonDecode(request.body) as Map<String, dynamic>);
        if (createJobGate != null) await createJobGate();
        return createJobResponse?.call() ?? jsonResponse({'id': 'job-new', 'title': 'Phục vụ'}, 201);
      }
      return http.Response('unexpected: ${request.method} $path', 404);
    });
  }

  Finder nextButton() => find.byType(FilledButton);

  Future<void> tapNext(WidgetTester tester) async {
    await tester.tap(nextButton());
    await tester.pumpAndSettle();
  }

  /// Đi từ bước 1 tới bước 8 với dữ liệu hợp lệ tối thiểu (lương truyền vào để test được nhiều
  /// định dạng nhập khác nhau).
  Future<void> reachFinalStep(
    WidgetTester tester, {
    String salaryMin = '20000',
    String salaryMax = '25000',
  }) async {
    // 1/8 ngành nghề
    await tester.tap(find.text('Phục vụ'));
    await tester.pumpAndSettle();
    await tapNext(tester);
    // 2/8 số lượng (mặc định 1)
    await tapNext(tester);
    // 3/8 lương
    await tester.enterText(find.byType(TextField).at(0), salaryMin);
    await tester.enterText(find.byType(TextField).at(1), salaryMax);
    await tester.pumpAndSettle();
    await tapNext(tester);
    // 4/8 ca làm
    await tester.tap(find.text('Linh hoạt'));
    await tester.pumpAndSettle();
    await tapNext(tester);
    // 5/8 địa điểm (cơ sở duy nhất đã tự chọn)
    await tapNext(tester);
    // 6/8 độ gấp (mặc định NOT_URGENT)
    await tapNext(tester);
    // 7/8 kinh nghiệm (mặc định NOT_REQUIRED)
    await tapNext(tester);
    // 8/8 mô tả
    expect(find.text('Đăng tuyển (8/8)'), findsOneWidget);
  }

  // ---------- 1. Double submit ở bước cuối ----------

  testWidgets('bấm ĐĂNG TIN 2 lần thật nhanh (trước khi kịp rebuild) -> chỉ gửi ĐÚNG 1 POST /jobs',
      (tester) async {
    final session = loggedInSession();
    var createCount = 0;
    final gate = Completer<void>();
    final api = apiFor(
      wizardBackend(
        onCreateJob: (_) => createCount += 1,
        createJobGate: () => gate.future,
      ),
      session,
    );

    await tester.pumpWidget(wrap(api, session));
    await tester.pumpAndSettle();
    await reachFinalStep(tester);

    await tester.enterText(find.byType(TextField).first, 'Cần 2 phục vụ ca tối');
    await tester.pumpAndSettle();

    // Hai lần tap liên tiếp KHÔNG có pump() ở giữa = đúng kịch bản "tap 2 lần cực nhanh" trên máy
    // thật: cả hai đều rơi vào cùng một frame, callback onPressed vẫn là closure cũ (_submitting
    // còn false ở thời điểm build). Nếu _submit() không tự khoá thì sẽ có 2 request tạo job.
    await tester.tap(nextButton());
    await tester.tap(nextButton(), warnIfMissed: false);
    await tester.pump();

    expect(createCount, 1, reason: 'double tap ĐĂNG TIN không được tạo 2 tin tuyển dụng');

    gate.complete();
    await tester.pumpAndSettle();
    expect(createCount, 1);
  });

  // ---------- 2. Lương nhập có dấu phân cách nghìn ----------

  testWidgets('nhập lương "5.000.000" (kiểu VN) -> payload phải là 5000000, KHÔNG được thành 0',
      (tester) async {
    final session = loggedInSession();
    Map<String, dynamic>? sentBody;
    final api = apiFor(wizardBackend(onCreateJob: (b) => sentBody = b), session);

    await tester.pumpWidget(wrap(api, session));
    await tester.pumpAndSettle();
    await reachFinalStep(tester, salaryMin: '5.000.000', salaryMax: '10.000.000');

    await tester.tap(nextButton());
    await tester.pumpAndSettle();

    expect(sentBody, isNotNull);
    expect(sentBody!['salaryMin'], 5000000);
    expect(sentBody!['salaryMax'], 10000000);
  });

  // ---------- 3. Lương min > max ----------

  testWidgets('lương min > max -> TIẾP TỤC bị khoá, không cho sang bước sau', (tester) async {
    final session = loggedInSession();
    final api = apiFor(wizardBackend(onCreateJob: (_) {}), session);

    await tester.pumpWidget(wrap(api, session));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Phục vụ'));
    await tester.pumpAndSettle();
    await tapNext(tester);
    await tapNext(tester);

    await tester.enterText(find.byType(TextField).at(0), '10000000');
    await tester.enterText(find.byType(TextField).at(1), '5000000');
    await tester.pumpAndSettle();

    expect(find.text('Đăng tuyển (3/8)'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(nextButton()).onPressed,
      isNull,
      reason: 'lương tối thiểu lớn hơn lương tối đa là dữ liệu sai, không được cho đi tiếp',
    );
  });

  // ---------- 4. Payload đúng hợp đồng backend ----------

  testWidgets('payload gửi lên POST /jobs khớp đúng CreateJobDto (tên field/enum/kiểu dữ liệu)',
      (tester) async {
    final session = loggedInSession();
    Map<String, dynamic>? sentBody;
    final api = apiFor(wizardBackend(onCreateJob: (b) => sentBody = b), session);

    await tester.pumpWidget(wrap(api, session));
    await tester.pumpAndSettle();
    await reachFinalStep(tester);

    await tester.enterText(find.byType(TextField).first, 'Cần 2 phục vụ ca tối');
    await tester.pumpAndSettle();
    await tester.tap(nextButton());
    await tester.pumpAndSettle();

    expect(sentBody, isNotNull);
    expect(sentBody!['employerLocationId'], 'loc-1');
    expect(sentBody!['categoryId'], 'cat-1');
    expect(sentBody!['title'], 'Phục vụ');
    expect(sentBody!['description'], 'Cần 2 phục vụ ca tối');
    expect(sentBody!['headcount'], 1);
    expect(sentBody!['employmentType'], 'PART_TIME');
    expect(sentBody!['shifts'], ['FLEXIBLE']);
    expect(sentBody!['salaryMin'], 20000);
    expect(sentBody!['salaryMax'], 25000);
    expect(sentBody!['salaryUnit'], 'HOUR');
    expect(sentBody!['startUrgency'], 'NOT_URGENT');
    expect(sentBody!['requiredExperience'], 'NOT_REQUIRED');
    expect(sentBody!['isUrgent'], false);
  });

  // ---------- 5. Submit lỗi -> không mất dữ liệu, cho thử lại ----------

  testWidgets('POST /jobs lỗi 500 -> hiện lỗi, giữ nguyên bước 8 và dữ liệu, cho bấm đăng lại',
      (tester) async {
    final session = loggedInSession();
    var createCount = 0;
    final api = apiFor(
      wizardBackend(
        onCreateJob: (_) => createCount += 1,
        createJobResponse: () => jsonResponse({'message': 'Hệ thống đang bận'}, 500),
      ),
      session,
    );

    await tester.pumpWidget(wrap(api, session));
    await tester.pumpAndSettle();
    await reachFinalStep(tester);

    await tester.enterText(find.byType(TextField).first, 'Cần 2 phục vụ ca tối');
    await tester.pumpAndSettle();
    await tester.tap(nextButton());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(createCount, 1);
    expect(find.text('Đăng tuyển (8/8)'), findsOneWidget);
    expect(find.text('Hệ thống đang bận. Vui lòng thử lại sau.'), findsOneWidget);
    expect(find.text('Cần 2 phục vụ ca tối'), findsOneWidget);

    // Vẫn bấm đăng lại được (nút không bị khoá vĩnh viễn sau lỗi).
    expect(tester.widget<FilledButton>(nextButton()).onPressed, isNotNull);
    await tester.tap(nextButton());
    await tester.pumpAndSettle();
    expect(createCount, 2);
  });

  // ---------- 6. State preservation 1 -> 8 -> back về 1 ----------

  testWidgets('đi hết 1->8 rồi back ngược về 1: mọi dữ liệu đã nhập/chọn còn nguyên', (tester) async {
    final session = loggedInSession();
    final api = apiFor(wizardBackend(onCreateJob: (_) {}), session);

    await tester.pumpWidget(wrap(api, session));
    await tester.pumpAndSettle();
    await reachFinalStep(tester);
    await tester.enterText(find.byType(TextField).first, 'Mô tả test');
    await tester.pumpAndSettle();

    for (var i = 0; i < 7; i++) {
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
    }
    expect(find.text('Đăng tuyển (1/8)'), findsOneWidget);
    expect(
      tester.widget<ChoiceChip>(find.ancestor(of: find.text('Phục vụ'), matching: find.byType(ChoiceChip))).selected,
      isTrue,
    );

    // Tiến lại tới bước 3 kiểm tra lương vẫn còn.
    await tapNext(tester);
    await tapNext(tester);
    expect(find.text('Đăng tuyển (3/8)'), findsOneWidget);
    expect(find.text('20000'), findsOneWidget);
    expect(find.text('25000'), findsOneWidget);

    // Bước 4 ca làm vẫn được chọn.
    await tapNext(tester);
    expect(
      tester.widget<FilterChip>(find.ancestor(of: find.text('Linh hoạt'), matching: find.byType(FilterChip))).selected,
      isTrue,
    );
  });
}
