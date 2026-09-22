import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:viec_nha_trang/core/auth/session.dart';
import 'package:viec_nha_trang/core/network/api_client.dart';
import 'package:viec_nha_trang/features/applications/data/applications_service.dart';
import 'package:viec_nha_trang/features/applications/presentation/applications_screen.dart';
import 'package:viec_nha_trang/features/reviews/data/reviews_service.dart';
import '../helpers/in_memory_token_storage.dart';
import '../helpers/json_response.dart';

/// Phase Reviews (đặc tả mục 23): CTA đánh giá employer trên ApplicationsScreen, chỉ hiện khi
/// đơn ứng tuyển đã HIRED và chưa được đánh giá. Contract khớp
/// apps/backend/src/reviews/reviews.module.ts (đọc trực tiếp từ source, không đoán field).
void main() {
  Map<String, dynamic> buildApplication({required String id, required String status, String employerId = 'e1'}) => {
        'id': id,
        'status': status,
        'job': {
          'id': 'job-1',
          'title': 'Phục vụ nhà hàng',
          'employer': {'id': employerId, 'businessName': 'Quán Test', 'verificationLevel': 'UNVERIFIED'},
          'salaryMin': 20000,
          'salaryMax': 25000,
          'salaryUnit': 'HOUR',
          'employmentType': 'PART_TIME',
          'status': 'ACTIVE',
        },
      };

  Future<void> pumpScreen(
    WidgetTester tester, {
    required List<dynamic> applications,
    List<dynamic> existingReviews = const [],
    FutureOr<http.Response> Function(http.Request request)? onPostReview,
  }) async {
    final session = Session(storage: InMemoryTokenStorage());
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/applications/me')) {
          return jsonResponse(applications, 200);
        }
        if (request.url.path.endsWith('/reviews') && request.method == 'GET') {
          return jsonResponse(existingReviews, 200);
        }
        if (request.url.path.endsWith('/reviews') && request.method == 'POST') {
          if (onPostReview != null) return onPostReview(request);
          return jsonResponse({'id': 'review-1'}, 201);
        }
        return http.Response('not found: ${request.url.path}', 404);
      }),
    );
    await session.setTokens(access: 'fake-access', refresh: 'fake-refresh', roles: ['JOB_SEEKER']);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<Session>.value(value: session),
        Provider<ApiClient>(create: (_) => api),
        Provider<ApplicationsService>(create: (_) => ApplicationsService(api)),
        Provider<ReviewsService>(create: (_) => ReviewsService(api)),
      ],
      child: const MaterialApp(home: ApplicationsScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('đơn chưa HIRED thì không hiện CTA đánh giá', (tester) async {
    await pumpScreen(tester, applications: [buildApplication(id: 'a1', status: 'NEW')]);

    // Tab mặc định là "Mới" - đơn a1 hiện ở đây, không có nút ĐÁNH GIÁ.
    expect(find.text('ĐÁNH GIÁ'), findsNothing);
  });

  testWidgets('đơn HIRED và chưa đánh giá thì hiện CTA đánh giá', (tester) async {
    await pumpScreen(tester, applications: [buildApplication(id: 'a1', status: 'HIRED')]);
    await tester.tap(find.text('Đã nhận'));
    await tester.pumpAndSettle();

    expect(find.text('ĐÁNH GIÁ'), findsOneWidget);
    expect(find.text('Đã đánh giá'), findsNothing);
  });

  testWidgets('đơn HIRED đã có review (applicationId trùng) thì hiện "Đã đánh giá", không hiện CTA', (tester) async {
    await pumpScreen(
      tester,
      applications: [buildApplication(id: 'a1', status: 'HIRED')],
      existingReviews: [
        {'id': 'r1', 'applicationId': 'a1', 'rating': 5},
      ],
    );
    await tester.tap(find.text('Đã nhận'));
    await tester.pumpAndSettle();

    expect(find.text('Đã đánh giá'), findsOneWidget);
    expect(find.text('ĐÁNH GIÁ'), findsNothing);
  });

  testWidgets('gửi đánh giá thành công: chọn sao, bấm GỬI, gọi đúng POST /reviews rồi chuyển sang "Đã đánh giá"',
      (tester) async {
    Map<String, dynamic>? sentBody;
    await pumpScreen(
      tester,
      applications: [buildApplication(id: 'a1', status: 'HIRED')],
      onPostReview: (request) {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return jsonResponse({'id': 'review-1'}, 201);
      },
    );
    await tester.tap(find.text('Đã nhận'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ĐÁNH GIÁ'));
    await tester.pumpAndSettle();

    // Chọn 4 sao (icon star_border thứ 4 trong dialog).
    await tester.tap(find.byIcon(Icons.star_border).at(3));
    await tester.pump();

    await tester.tap(find.text('GỬI'));
    await tester.pumpAndSettle();

    expect(sentBody, isNotNull);
    expect(sentBody!['reviewerType'], 'JOB_SEEKER');
    expect(sentBody!['applicationId'], 'a1');
    expect(sentBody!['rating'], 4);
    expect(sentBody!.containsKey('employerId'), isFalse, reason: 'employerId phải do backend tự suy ra, client không gửi');
    expect(sentBody!.containsKey('jobSeekerId'), isFalse);

    expect(find.text('Đã đánh giá'), findsOneWidget);
    expect(find.text('ĐÁNH GIÁ'), findsNothing);
  });

  testWidgets('validation: nút GỬI bị disable khi chưa chọn sao (rating=0)', (tester) async {
    await pumpScreen(tester, applications: [buildApplication(id: 'a1', status: 'HIRED')]);
    await tester.tap(find.text('Đã nhận'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ĐÁNH GIÁ'));
    await tester.pumpAndSettle();

    final submitButton = tester.widget<TextButton>(find.widgetWithText(TextButton, 'GỬI'));
    expect(submitButton.onPressed, isNull);
  });

  testWidgets('lỗi API khi gửi đánh giá: hiện thông báo lỗi, không chuyển sang "Đã đánh giá", vẫn cho thử lại',
      (tester) async {
    await pumpScreen(
      tester,
      applications: [buildApplication(id: 'a1', status: 'HIRED')],
      onPostReview: (_) => jsonResponse({'message': 'Application is not eligible for review yet.'}, 400),
    );
    await tester.tap(find.text('Đã nhận'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ĐÁNH GIÁ'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.star_border).first);
    await tester.pump();
    await tester.tap(find.text('GỬI'));
    await tester.pumpAndSettle();

    expect(find.text('Đã đánh giá'), findsNothing);
    expect(find.text('ĐÁNH GIÁ'), findsOneWidget);
  });

  testWidgets('double-tap nút ĐÁNH GIÁ chỉ mở đúng 1 dialog / gửi đúng 1 request (chặn double-submit)',
      (tester) async {
    var postCount = 0;
    final gate = Completer<void>();
    await pumpScreen(
      tester,
      applications: [buildApplication(id: 'a1', status: 'HIRED')],
      onPostReview: (_) async {
        postCount += 1;
        await gate.future;
        return jsonResponse({'id': 'review-1'}, 201);
      },
    );
    await tester.tap(find.text('Đã nhận'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ĐÁNH GIÁ'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.star_border).first);
    await tester.pump();

    final submitButton = find.text('GỬI');
    await tester.tap(submitButton);
    await tester.pump();
    // Dialog đã đóng ngay sau lần bấm đầu (Navigator.pop trả về input) - không còn nút GỬI để bấm
    // lần 2, nhưng request đang treo ở gate. Xác nhận vẫn chỉ có đúng 1 request đã gửi.
    expect(postCount, 1);

    gate.complete();
    await tester.pumpAndSettle();
    expect(postCount, 1);
  });
}
