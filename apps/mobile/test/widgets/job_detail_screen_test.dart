import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:viec_nha_trang/core/auth/session.dart';
import 'package:viec_nha_trang/core/network/api_client.dart';
import 'package:viec_nha_trang/features/applications/data/applications_service.dart';
import 'package:viec_nha_trang/features/jobs/data/jobs_service.dart';
import 'package:viec_nha_trang/features/jobs/presentation/job_detail_screen.dart';
import 'package:viec_nha_trang/features/profile/data/job_seeker_profile_service.dart';
import 'package:viec_nha_trang/features/saved_jobs/data/saved_jobs_service.dart';
import '../helpers/in_memory_token_storage.dart';
import '../helpers/json_response.dart';

/// Phần F (JOB DETAIL) của phase QA Job Seeker: salary phải hiển thị đúng job.salaryMin/
/// salaryMax/job.salaryUnit - KHÔNG hard-code tháng hoặc giờ.
void main() {
  Widget wrap(ApiClient api, Session session) {
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

  Session guestSession() => Session(storage: InMemoryTokenStorage());

  ApiClient apiFor(Map<String, dynamic> jobJson) {
    final session = guestSession();
    return ApiClient(
      session,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/jobs/job-1')) return jsonResponse(jobJson, 200);
        return http.Response('unexpected: ${request.url.path}', 404);
      }),
    );
  }

  // Bug thật phát hiện khi audit: JobDetailScreen hiển thị lương bằng
  // '${job['salaryMin']}–${job['salaryMax']}đ' thay vì dùng Job.salaryLabel (đã có sẵn, đúng, và
  // đang được JobCard ở Home dùng) - không có đơn vị (/giờ, /tháng, /ngày, /ca), không có dấu
  // phân cách hàng nghìn. Người dùng thấy "25000–35000đ" ở trang chi tiết nhưng thấy
  // "25.000–35.000đ/giờ" đúng định dạng ở thẻ Home cho CÙNG 1 tin - không nhất quán, và với tin
  // lương tháng (vd 8000000-12000000) sẽ hiện "8000000–12000000đ" trông như 8 triệu đồng chứ
  // không phải 8 triệu/tháng.
  testWidgets('lương HIỂN THỊ đúng đơn vị /giờ, có dấu phân cách hàng nghìn (khớp JobCard)', (tester) async {
    final api = apiFor(const {
      'id': 'job-1',
      'title': 'Phục vụ nhà hàng',
      'employer': {'id': 'e1', 'businessName': 'Quán Test', 'verificationLevel': 'UNVERIFIED'},
      'salaryMin': 25000,
      'salaryMax': 35000,
      'salaryUnit': 'HOUR',
      'employmentType': 'PART_TIME',
      'status': 'ACTIVE',
    });

    await tester.pumpWidget(wrap(api, guestSession()));
    await tester.pumpAndSettle();

    expect(find.text('25.000–35.000đ/giờ'), findsOneWidget);
    expect(find.text('25000–35000đ'), findsNothing);
  });

  testWidgets('lương theo THÁNG hiển thị đúng "/tháng" - không hiểu nhầm thành đơn vị khác', (tester) async {
    final api = apiFor(const {
      'id': 'job-1',
      'title': 'Kế toán',
      'employer': {'id': 'e1', 'businessName': 'Công ty Test', 'verificationLevel': 'UNVERIFIED'},
      'salaryMin': 8000000,
      'salaryMax': 12000000,
      'salaryUnit': 'MONTH',
      'employmentType': 'FULL_TIME',
      'status': 'ACTIVE',
    });

    await tester.pumpWidget(wrap(api, guestSession()));
    await tester.pumpAndSettle();

    expect(find.text('8.000.000–12.000.000đ/tháng'), findsOneWidget);
  });

  testWidgets('lương theo CA hiển thị đúng "/ca"', (tester) async {
    final api = apiFor(const {
      'id': 'job-1',
      'title': 'Phục vụ sự kiện',
      'employer': {'id': 'e1', 'businessName': 'Quán Test', 'verificationLevel': 'UNVERIFIED'},
      'salaryMin': 150000,
      'salaryMax': 200000,
      'salaryUnit': 'SHIFT',
      'employmentType': 'SHIFT_BASED',
      'status': 'ACTIVE',
    });

    await tester.pumpWidget(wrap(api, guestSession()));
    await tester.pumpAndSettle();

    expect(find.text('150.000–200.000đ/ca'), findsOneWidget);
  });

  // Phần F còn lại: load lỗi -> retry, job không tồn tại -> không crash.
  testWidgets('GET /jobs/:id lỗi 500 -> hiện lỗi + retry, không crash', (tester) async {
    final session = guestSession();
    var callCount = 0;
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        callCount++;
        if (callCount == 1) return http.Response('server error', 500);
        return jsonResponse(const {
          'id': 'job-1',
          'title': 'Phục vụ nhà hàng',
          'employer': {'id': 'e1', 'businessName': 'Quán Test', 'verificationLevel': 'UNVERIFIED'},
          'salaryMin': 20000,
          'salaryMax': 25000,
          'salaryUnit': 'HOUR',
          'employmentType': 'PART_TIME',
          'status': 'ACTIVE',
        }, 200);
      }),
    );

    await tester.pumpWidget(wrap(api, session));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('GET /jobs/:id trả 404 (job không tồn tại) -> hiện lỗi, không crash', (tester) async {
    final session = guestSession();
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async => http.Response(
            '{"message":"Không tìm thấy tin tuyển dụng."}',
            404,
            headers: {'content-type': 'application/json; charset=utf-8'},
          )),
    );

    await tester.pumpWidget(wrap(api, session));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // ApiException.userMessage không hiển thị message thô từ backend cho lỗi 404 - luôn dùng
    // thông báo chung "Không tìm thấy dữ liệu." (xem api_exception.dart).
    expect(find.text('Không tìm thấy dữ liệu.'), findsOneWidget);
  });
}
