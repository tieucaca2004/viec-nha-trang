import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:viec_nha_trang/core/auth/session.dart';
import 'package:viec_nha_trang/core/network/api_client.dart';
import 'package:viec_nha_trang/core/network/api_exception.dart';
import 'package:viec_nha_trang/features/applications/data/applications_service.dart';
import 'package:viec_nha_trang/features/jobs/data/jobs_service.dart';
import 'package:viec_nha_trang/features/jobs/presentation/job_detail_screen.dart';
import 'package:viec_nha_trang/features/profile/data/job_seeker_profile_service.dart';
import 'package:viec_nha_trang/features/reports/data/reports_service.dart';
import 'package:viec_nha_trang/features/saved_jobs/data/saved_jobs_service.dart';
import '../helpers/in_memory_token_storage.dart';
import '../helpers/json_response.dart';

/// Phase Reports (đặc tả mục 22): báo cáo tin tuyển dụng từ JobDetailScreen. Contract khớp
/// CreateReportDto ở apps/backend/src/reports/reports.module.ts.
void main() {
  const jobJson = {
    'id': 'job-1',
    'title': 'Phục vụ nhà hàng',
    'employer': {'id': 'e1', 'businessName': 'Quán Test', 'verificationLevel': 'UNVERIFIED'},
    'salaryMin': 25000,
    'salaryMax': 30000,
    'salaryUnit': 'HOUR',
    'employmentType': 'PART_TIME',
    'headcount': 1,
    'status': 'ACTIVE',
  };

  final submitButton = find.widgetWithText(FilledButton, 'GỬI BÁO CÁO');

  Future<void> pumpDetail(
    WidgetTester tester, {
    bool loggedIn = true,
    List<String>? requests,
    Future<http.Response> Function(http.Request request)? onReport,
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final session = Session(storage: InMemoryTokenStorage());
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        requests?.add('${request.method} ${request.url.path}');
        final path = request.url.path;
        if (path.endsWith('/jobs/job-1')) return jsonResponse(jobJson, 200);
        if (path.endsWith('/applications/me')) return jsonResponse([], 200);
        if (path.endsWith('/saved-jobs')) return jsonResponse([], 200);
        if (path.endsWith('/reports') && request.method == 'POST') {
          if (onReport != null) return onReport(request);
          return jsonResponse({'id': 'report-1', 'status': 'OPEN'}, 201);
        }
        return http.Response('not found: $path', 404);
      }),
    );
    if (loggedIn) {
      await session.setTokens(access: 'fake-access', refresh: 'fake-refresh', roles: ['JOB_SEEKER']);
    }
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<Session>.value(value: session),
        Provider<ApiClient>.value(value: api),
        Provider<JobsService>(create: (_) => JobsService(api)),
        Provider<ApplicationsService>(create: (_) => ApplicationsService(api)),
        Provider<SavedJobsService>(create: (_) => SavedJobsService(api)),
        Provider<JobSeekerProfileService>(create: (_) => JobSeekerProfileService(api)),
        Provider<ReportsService>(create: (_) => ReportsService(api)),
      ],
      child: const MaterialApp(home: JobDetailScreen(jobId: 'job-1')),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> openReportDialog(WidgetTester tester) async {
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Báo cáo tin'));
    await tester.pumpAndSettle();
  }

  testWidgets('người đã đăng nhập thấy mục "Báo cáo tin" trong menu của JobDetailScreen', (tester) async {
    await pumpDetail(tester);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();

    expect(find.text('Báo cáo tin'), findsOneWidget);
  });

  testWidgets('mở dialog báo cáo hiện đủ 9 lý do theo đúng enum ReportReason của backend', (tester) async {
    await pumpDetail(tester);
    await openReportDialog(tester);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(ReportsService.jobReasonLabels.keys, [
      'FAKE_JOB',
      'SCAM',
      'WRONG_SALARY',
      'WRONG_LOCATION',
      'MISMATCHED_DESCRIPTION',
      'CHARGES_FEE_FROM_CANDIDATE',
      'INAPPROPRIATE_CONTENT',
      'SPAM',
      'OTHER',
    ]);
    for (final label in ReportsService.jobReasonLabels.values) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byType(RadioListTile<String>), findsNWidgets(9));
  });

  testWidgets('nút GỬI BÁO CÁO bị khoá khi chưa chọn lý do, mở khi đã chọn', (tester) async {
    await pumpDetail(tester);
    await openReportDialog(tester);

    expect(tester.widget<FilledButton>(submitButton).onPressed, isNull);

    await tester.tap(find.text('Tin rác / spam'));
    await tester.pump();

    expect(tester.widget<FilledButton>(submitButton).onPressed, isNotNull);
  });

  testWidgets('gửi thành công: POST đúng payload JOB + jobId + reason + note, đóng dialog, báo thành công',
      (tester) async {
    Map<String, dynamic>? sentBody;
    await pumpDetail(tester, onReport: (request) async {
      sentBody = jsonDecode(request.body) as Map<String, dynamic>;
      return jsonResponse({'id': 'report-1', 'status': 'OPEN'}, 201);
    });
    await openReportDialog(tester);

    await tester.tap(find.text('Có dấu hiệu lừa đảo'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '  Bắt đóng tiền cọc trước  ');
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    expect(sentBody, {
      'targetType': 'JOB',
      'jobId': 'job-1',
      'reason': 'SCAM',
      'note': 'Bắt đóng tiền cọc trước',
    });
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Đã gửi báo cáo. Cảm ơn bạn đã giúp giữ an toàn cho cộng đồng.'), findsOneWidget);
  });

  testWidgets('không nhập ghi chú thì payload không có key note', (tester) async {
    Map<String, dynamic>? sentBody;
    await pumpDetail(tester, onReport: (request) async {
      sentBody = jsonDecode(request.body) as Map<String, dynamic>;
      return jsonResponse({'id': 'report-1'}, 201);
    });
    await openReportDialog(tester);

    await tester.tap(find.text('Tin tuyển dụng giả'));
    await tester.pump();
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    expect(sentBody, {'targetType': 'JOB', 'jobId': 'job-1', 'reason': 'FAKE_JOB'});
  });

  testWidgets('lỗi API: dialog vẫn mở, hiện userMessage, giữ lý do đã chọn, thử lại được và thành công',
      (tester) async {
    var attempts = 0;
    await pumpDetail(tester, onReport: (_) async {
      attempts += 1;
      if (attempts == 1) return jsonResponse({'message': 'boom'}, 500);
      return jsonResponse({'id': 'report-1'}, 201);
    });
    await openReportDialog(tester);

    await tester.tap(find.text('Sai địa điểm làm việc'));
    await tester.pump();
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    expect(attempts, 1);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(ApiException(500, 'boom').userMessage), findsOneWidget);
    expect(find.text('Đã gửi báo cáo. Cảm ơn bạn đã giúp giữ an toàn cho cộng đồng.'), findsNothing);
    expect(tester.widget<FilledButton>(submitButton).onPressed, isNotNull,
        reason: 'lý do đã chọn phải được giữ để thử lại');

    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Đã gửi báo cáo. Cảm ơn bạn đã giúp giữ an toàn cho cộng đồng.'), findsOneWidget);
  });

  testWidgets('double-tap GỬI BÁO CÁO trong lúc POST đang treo chỉ gửi ĐÚNG 1 request', (tester) async {
    var postCount = 0;
    final gate = Completer<void>();
    await pumpDetail(tester, onReport: (_) async {
      postCount += 1;
      await gate.future;
      return jsonResponse({'id': 'report-1'}, 201);
    });
    await openReportDialog(tester);

    await tester.tap(find.text('Tin rác / spam'));
    await tester.pump();

    await tester.tap(submitButton);
    await tester.tap(submitButton, warnIfMissed: false);
    await tester.pump();

    expect(postCount, 1, reason: 'double-tap không được gửi 2 POST /reports');
    final pendingButton = tester.widget<FilledButton>(
      find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)),
    );
    expect(pendingButton.onPressed, isNull, reason: 'nút gửi phải bị khoá trong lúc chờ');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)),
        warnIfMissed: false);
    await tester.pump();
    expect(postCount, 1);

    gate.complete();
    await tester.pumpAndSettle();
    expect(postCount, 1);
    expect(find.byType(AlertDialog), findsNothing);
  });

  group('không cho đóng dialog khi POST đang treo', () {
    const successText = 'Đã gửi báo cáo. Cảm ơn bạn đã giúp giữ an toàn cho cộng đồng.';
    final pendingSubmit = find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton));

    Future<void> tapOutsideDialog(WidgetTester tester) async {
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
    }

    Future<void> pressSystemBack(WidgetTester tester) async {
      await tester.binding.handlePopRoute();
      await tester.pump();
    }

    testWidgets('chạm ra ngoài lúc đang gửi: dialog vẫn mở, vẫn loading, 1 POST; xong thì đóng + báo thành công',
        (tester) async {
      var postCount = 0;
      final gate = Completer<void>();
      await pumpDetail(tester, onReport: (_) async {
        postCount += 1;
        await gate.future;
        return jsonResponse({'id': 'report-1'}, 201);
      });
      await openReportDialog(tester);
      await tester.tap(find.text('Tin rác / spam'));
      await tester.pump();
      await tester.tap(submitButton);
      await tester.pump();

      await tapOutsideDialog(tester);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.widget<FilledButton>(pendingSubmit).onPressed, isNull);
      expect(postCount, 1);

      gate.complete();
      await tester.pumpAndSettle();

      expect(postCount, 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(successText), findsOneWidget);
    });

    testWidgets('nút Back hệ thống lúc đang gửi: dialog vẫn mở, 1 POST; xong thì đóng + báo thành công',
        (tester) async {
      var postCount = 0;
      final gate = Completer<void>();
      await pumpDetail(tester, onReport: (_) async {
        postCount += 1;
        await gate.future;
        return jsonResponse({'id': 'report-1'}, 201);
      });
      await openReportDialog(tester);
      await tester.tap(find.text('Tin rác / spam'));
      await tester.pump();
      await tester.tap(submitButton);
      await tester.pump();

      await pressSystemBack(tester);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(JobDetailScreen), findsOneWidget, reason: 'Back không được pop luôn JobDetailScreen');
      expect(postCount, 1);

      gate.complete();
      await tester.pumpAndSettle();

      expect(postCount, 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(successText), findsOneWidget);
    });

    testWidgets('POST lỗi sau khi đã thử đóng dialog: dialog vẫn mở, hiện lỗi, gửi lại được', (tester) async {
      var postCount = 0;
      final gate = Completer<void>();
      await pumpDetail(tester, onReport: (_) async {
        postCount += 1;
        if (postCount == 1) {
          await gate.future;
          return jsonResponse({'message': 'boom'}, 500);
        }
        return jsonResponse({'id': 'report-1'}, 201);
      });
      await openReportDialog(tester);
      await tester.tap(find.text('Tin rác / spam'));
      await tester.pump();
      await tester.tap(submitButton);
      await tester.pump();

      await tapOutsideDialog(tester);
      await pressSystemBack(tester);
      gate.complete();
      await tester.pumpAndSettle();

      expect(postCount, 1);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(ApiException(500, 'boom').userMessage), findsOneWidget);
      expect(find.text(successText), findsNothing);

      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      expect(postCount, 2);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(successText), findsOneWidget);
    });

    testWidgets('khi KHÔNG đang gửi: chạm ra ngoài và nút Back vẫn đóng dialog bình thường, không gửi POST',
        (tester) async {
      final requests = <String>[];
      await pumpDetail(tester, requests: requests);

      await openReportDialog(tester);
      await tester.tap(find.text('Tin rác / spam'));
      await tester.pump();
      await tapOutsideDialog(tester);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      await openReportDialog(tester);
      await pressSystemBack(tester);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(JobDetailScreen), findsOneWidget);

      expect(requests.where((r) => r.contains('/reports')), isEmpty);
      expect(find.text(successText), findsNothing);
    });
  });

  testWidgets('khách chưa đăng nhập không thấy mục báo cáo và không có POST /reports nào', (tester) async {
    final requests = <String>[];
    await pumpDetail(tester, loggedIn: false, requests: requests);

    expect(find.text('Phục vụ nhà hàng'), findsWidgets, reason: 'khách vẫn xem được chi tiết tin');
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(find.text('Báo cáo tin'), findsNothing);
    expect(requests.where((r) => r.contains('/reports')), isEmpty);
  });
}
