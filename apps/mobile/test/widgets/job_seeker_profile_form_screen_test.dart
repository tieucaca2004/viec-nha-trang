import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:viec_nha_trang/core/auth/session.dart';
import 'package:viec_nha_trang/core/network/api_client.dart';
import 'package:viec_nha_trang/features/jobs/data/jobs_service.dart';
import 'package:viec_nha_trang/features/profile/data/job_seeker_profile_service.dart';
import 'package:viec_nha_trang/features/profile/presentation/job_seeker_profile_form_screen.dart';
import '../helpers/in_memory_token_storage.dart';
import '../helpers/json_response.dart';

/// Đặc tả §2 (ngày sinh) phase kế tiếp: date picker, hiển thị DD/MM/YYYY, đọc/lưu qua
/// PUT /me/job-seeker-profile, không cho chọn ngày tương lai, xử lý null/optional đúng.
void main() {
  Widget buildScreen(ApiClient api, {Map<String, dynamic>? existing}) {
    return MultiProvider(
      providers: [
        Provider<JobsService>(create: (_) => JobsService(api)),
        Provider<JobSeekerProfileService>(create: (_) => JobSeekerProfileService(api)),
      ],
      child: MaterialApp(home: JobSeekerProfileFormScreen(existing: existing)),
    );
  }

  ApiClient buildApiWithBody(Future<http.Response> Function(http.Request) handler) {
    final session = Session(storage: InMemoryTokenStorage());
    return ApiClient(session, httpClient: MockClient(handler));
  }

  testWidgets('hiển thị ngày sinh đã lưu dạng DD/MM/YYYY khi mở lại hồ sơ', (tester) async {
    final api = buildApiWithBody((request) async {
      if (request.url.path.endsWith('/categories') || request.url.path.endsWith('/areas')) {
        return jsonResponse([], 200);
      }
      return http.Response('unexpected: ${request.url.path}', 404);
    });

    await tester.pumpWidget(buildScreen(api, existing: {
      'fullName': 'Nguyễn Văn A',
      'dateOfBirth': '2000-05-15T00:00:00.000Z',
    }));
    await tester.pumpAndSettle();

    expect(find.text('15/05/2000'), findsOneWidget);
  });

  testWidgets('chưa có ngày sinh thì hiển thị "Chưa chọn", không tự bịa giá trị', (tester) async {
    final api = buildApiWithBody((request) async {
      if (request.url.path.endsWith('/categories') || request.url.path.endsWith('/areas')) {
        return jsonResponse([], 200);
      }
      return http.Response('unexpected: ${request.url.path}', 404);
    });

    await tester.pumpWidget(buildScreen(api, existing: {'fullName': 'Nguyễn Văn B'}));
    await tester.pumpAndSettle();

    expect(find.text('Chưa chọn'), findsOneWidget);
  });

  testWidgets('chọn ngày sinh qua date picker rồi hiển thị đúng định dạng DD/MM/YYYY', (tester) async {
    final api = buildApiWithBody((request) async {
      if (request.url.path.endsWith('/categories') || request.url.path.endsWith('/areas')) {
        return jsonResponse([], 200);
      }
      return http.Response('unexpected: ${request.url.path}', 404);
    });

    await tester.pumpWidget(buildScreen(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dobField')));
    await tester.pumpAndSettle();

    // Chuyển sang chế độ nhập ngày bằng bàn phím để chọn ngày xác định mà không phụ thuộc vào
    // việc ngày đó có hiển thị sẵn trên lưới tháng hiện tại.
    await tester.tap(find.byTooltip('Switch to input'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '01/01/2000');
    await tester.pumpAndSettle();

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('01/01/2000'), findsOneWidget);
  });

  testWidgets('lưu hồ sơ gửi đúng dateOfBirth (YYYY-MM-DD) lên PUT /me/job-seeker-profile', (tester) async {
    Map<String, dynamic>? sentBody;
    final api = buildApiWithBody((request) async {
      if (request.url.path.endsWith('/categories') || request.url.path.endsWith('/areas')) {
        return jsonResponse([], 200);
      }
      if (request.url.path.endsWith('/me/job-seeker-profile') && request.method == 'PUT') {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return jsonResponse(null, 200);
      }
      return http.Response('unexpected: ${request.method} ${request.url.path}', 404);
    });

    await tester.pumpWidget(buildScreen(api, existing: {
      'fullName': 'Nguyễn Văn C',
      'dateOfBirth': '1995-03-20T00:00:00.000Z',
    }));
    await tester.pumpAndSettle();

    await tester.tap(find.text('LƯU HỒ SƠ'));
    await tester.pumpAndSettle();

    expect(sentBody, isNotNull);
    expect(sentBody!['dateOfBirth'], '1995-03-20');
  });

  testWidgets('chưa chọn ngày sinh thì KHÔNG gửi key dateOfBirth (không đè null lên dữ liệu đã lưu)',
      (tester) async {
    Map<String, dynamic>? sentBody;
    final api = buildApiWithBody((request) async {
      if (request.url.path.endsWith('/categories') || request.url.path.endsWith('/areas')) {
        return jsonResponse([], 200);
      }
      if (request.url.path.endsWith('/me/job-seeker-profile') && request.method == 'PUT') {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return jsonResponse(null, 200);
      }
      return http.Response('unexpected: ${request.method} ${request.url.path}', 404);
    });

    await tester.pumpWidget(buildScreen(api, existing: {'fullName': 'Nguyễn Văn D'}));
    await tester.pumpAndSettle();

    await tester.tap(find.text('LƯU HỒ SƠ'));
    await tester.pumpAndSettle();

    expect(sentBody, isNotNull);
    expect(sentBody!.containsKey('dateOfBirth'), isFalse);
  });

  testWidgets('date picker không cho điều hướng sang tháng tương lai (không chọn được ngày tương lai)',
      (tester) async {
    final now = DateTime.now();
    final api = buildApiWithBody((request) async {
      if (request.url.path.endsWith('/categories') || request.url.path.endsWith('/areas')) {
        return jsonResponse([], 200);
      }
      return http.Response('unexpected: ${request.url.path}', 404);
    });

    // Ngày sinh đã lưu nằm trong tháng hiện tại - date picker mở đúng ngay tháng chứa lastDate
    // (hôm nay), nên nút "tháng sau" phải bị vô hiệu hoá (onPressed null) - bằng chứng
    // showDatePicker được gọi với lastDate = hôm nay, không cho chọn ngày tương lai.
    final currentMonthDob = DateTime(now.year, now.month, 1).toIso8601String();
    await tester.pumpWidget(buildScreen(api, existing: {'fullName': 'Nguyễn Văn E', 'dateOfBirth': currentMonthDob}));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dobField')));
    await tester.pumpAndSettle();

    final nextMonthButton = tester.widget<IconButton>(
      find.ancestor(of: find.byIcon(Icons.chevron_right), matching: find.byType(IconButton)),
    );
    expect(nextMonthButton.onPressed, isNull);
  });
}
