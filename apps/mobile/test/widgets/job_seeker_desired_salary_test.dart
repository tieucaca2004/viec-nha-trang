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

/// Lương mong muốn của người tìm việc.
///
/// Backend giữ nguyên hợp đồng cũ: desiredSalaryMin/desiredSalaryMax là số nguyên VND (Int?,
/// optional) đi kèm salaryUnit (HOUR/DAY/SHIFT/MONTH). Trước đây mobile hard-code
/// salaryUnit:'HOUR' và bắt nhập thẳng số VND theo giờ, nên không có cách nào khai lương theo
/// tháng. Nay chọn được đơn vị; riêng đơn vị THÁNG thì nhập theo TRIỆU cho dễ đọc
/// (8.5 -> 8.500.000 VND) - phần quy đổi nằm hoàn toàn ở mobile, API/schema không đổi.
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

  /// Bắt body của PUT /me/job-seeker-profile để đối chiếu payload thật gửi lên backend.
  ApiClient apiCapturing(void Function(Map<String, dynamic>) onSave) {
    final session = Session(storage: InMemoryTokenStorage());
    return ApiClient(
      session,
      httpClient: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/categories') || path.endsWith('/areas')) return jsonResponse([], 200);
        if (path.endsWith('/me/job-seeker-profile') && request.method == 'PUT') {
          onSave(jsonDecode(request.body) as Map<String, dynamic>);
          return jsonResponse({'id': 'seeker-1'}, 200);
        }
        return http.Response('unexpected: ${request.method} $path', 404);
      }),
    );
  }

  Finder salaryMinField() => find.byKey(const Key('desiredSalaryMinField'));
  Finder salaryMaxField() => find.byKey(const Key('desiredSalaryMaxField'));
  Finder saveButton() => find.byType(FilledButton);

  /// Chuyển ô lương sang đơn vị Tháng (nhập theo triệu).
  Future<void> selectMonthUnit(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('salaryUnitField')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tháng').last);
    await tester.pumpAndSettle();
  }

  Future<void> enterSalary(WidgetTester tester, String min, String max) async {
    await tester.enterText(salaryMinField(), min);
    await tester.enterText(salaryMaxField(), max);
    await tester.pumpAndSettle();
  }

  // Form là ListView ảo hoá - nút LƯU nằm ngoài viewport nên chưa được build vào tree; phải cuộn
  // tới nơi (dragUntilVisible) chứ không dùng được ensureVisible (cần widget đã tồn tại sẵn).
  Future<void> tapSave(WidgetTester tester) async {
    await tester.dragUntilVisible(saveButton(), find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(saveButton());
    await tester.pumpAndSettle();
  }

  // ---------- 1-3. Nhập theo triệu -> payload VND ----------

  testWidgets('nhập 8 triệu/tháng -> payload desiredSalaryMin = 8000000', (tester) async {
    Map<String, dynamic>? body;
    final api = apiCapturing((b) => body = b);

    await tester.pumpWidget(buildScreen(api, existing: {'fullName': 'Nguyễn Văn A'}));
    await tester.pumpAndSettle();
    await selectMonthUnit(tester);
    await enterSalary(tester, '8', '10');
    await tapSave(tester);

    expect(body, isNotNull);
    expect(body!['desiredSalaryMin'], 8000000);
    expect(body!['desiredSalaryMax'], 10000000);
    expect(body!['salaryUnit'], 'MONTH');
  });

  testWidgets('nhập 8.5 triệu/tháng -> payload = 8500000 (không lệch floating-point)', (tester) async {
    Map<String, dynamic>? body;
    final api = apiCapturing((b) => body = b);

    await tester.pumpWidget(buildScreen(api, existing: {'fullName': 'Nguyễn Văn A'}));
    await tester.pumpAndSettle();
    await selectMonthUnit(tester);
    await enterSalary(tester, '8.5', '12.5');
    await tapSave(tester);

    expect(body!['desiredSalaryMin'], 8500000);
    expect(body!['desiredSalaryMax'], 12500000);
  });

  testWidgets('nhập dấu phẩy thập phân "8,5" -> vẫn hiểu đúng thành 8500000', (tester) async {
    Map<String, dynamic>? body;
    final api = apiCapturing((b) => body = b);

    await tester.pumpWidget(buildScreen(api, existing: {'fullName': 'Nguyễn Văn A'}));
    await tester.pumpAndSettle();
    await selectMonthUnit(tester);
    await enterSalary(tester, '8,5', '12,5');
    await tapSave(tester);

    expect(body!['desiredSalaryMin'], 8500000);
    expect(body!['desiredSalaryMax'], 12500000);
  });

  // ---------- 4. Load ngược từ backend ----------

  testWidgets('mở hồ sơ có desiredSalaryMin=8500000 + salaryUnit=MONTH -> ô nhập hiện "8.5"', (tester) async {
    final api = apiCapturing((_) {});

    await tester.pumpWidget(buildScreen(api, existing: {
      'fullName': 'Nguyễn Văn A',
      'desiredSalaryMin': 8500000,
      'desiredSalaryMax': 12000000,
      'salaryUnit': 'MONTH',
    }));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(salaryMinField()).controller!.text, '8.5');
    // Số tròn không được hiện thừa ".0".
    expect(tester.widget<TextField>(salaryMaxField()).controller!.text, '12');
  });

  testWidgets('hồ sơ cũ lưu theo GIỜ (25000đ/giờ) vẫn hiện đúng số VND, KHÔNG bị chia 1 triệu',
      (tester) async {
    final api = apiCapturing((_) {});

    await tester.pumpWidget(buildScreen(api, existing: {
      'fullName': 'Nguyễn Văn A',
      'desiredSalaryMin': 25000,
      'desiredSalaryMax': 35000,
      'salaryUnit': 'HOUR',
    }));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(salaryMinField()).controller!.text, '25000');
    expect(tester.widget<TextField>(salaryMaxField()).controller!.text, '35000');
  });

  testWidgets('đơn vị GIỜ: nhập 25000 -> payload giữ nguyên 25000 VND, salaryUnit=HOUR', (tester) async {
    Map<String, dynamic>? body;
    final api = apiCapturing((b) => body = b);

    await tester.pumpWidget(buildScreen(api, existing: {'fullName': 'Nguyễn Văn A'}));
    await tester.pumpAndSettle();
    await enterSalary(tester, '25000', '35000');
    await tapSave(tester);

    expect(body!['desiredSalaryMin'], 25000);
    expect(body!['desiredSalaryMax'], 35000);
    expect(body!['salaryUnit'], 'HOUR');
  });

  // ---------- 5-7. Validation ----------

  testWidgets('nhập 0 -> báo lỗi rõ ràng, KHÔNG gửi request', (tester) async {
    var saveCalled = false;
    final api = apiCapturing((_) => saveCalled = true);

    await tester.pumpWidget(buildScreen(api, existing: {'fullName': 'Nguyễn Văn A'}));
    await tester.pumpAndSettle();
    await selectMonthUnit(tester);
    await enterSalary(tester, '0', '10');
    await tapSave(tester);

    expect(saveCalled, isFalse);
    expect(find.textContaining('Lương mong muốn phải lớn hơn 0'), findsOneWidget);
  });

  testWidgets('nhập số âm -> không nhập được dấu trừ, không gửi giá trị âm', (tester) async {
    Map<String, dynamic>? body;
    final api = apiCapturing((b) => body = b);

    await tester.pumpWidget(buildScreen(api, existing: {'fullName': 'Nguyễn Văn A'}));
    await tester.pumpAndSettle();
    await selectMonthUnit(tester);
    await enterSalary(tester, '-5', '10');

    // Dấu trừ bị chặn ngay ở ô nhập -> "-5" thành "5" (kiểm tra TRƯỚC khi lưu, vì lưu thành công
    // sẽ pop màn hình và ô nhập không còn trong tree nữa).
    expect(tester.widget<TextField>(salaryMinField()).controller!.text, '5');

    await tapSave(tester);
    expect(body!['desiredSalaryMin'], 5000000);
    expect(body!['desiredSalaryMin'], greaterThan(0));
  });

  testWidgets('nhập chữ/ký tự lạ -> bị chặn ngay tại ô nhập', (tester) async {
    final api = apiCapturing((_) {});

    await tester.pumpWidget(buildScreen(api, existing: {'fullName': 'Nguyễn Văn A'}));
    await tester.pumpAndSettle();
    await selectMonthUnit(tester);
    await tester.enterText(salaryMinField(), 'abc8.5xyz');
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(salaryMinField()).controller!.text, '8.5');
  });

  testWidgets('lương tối thiểu lớn hơn lương tối đa -> báo lỗi, KHÔNG gửi request', (tester) async {
    var saveCalled = false;
    final api = apiCapturing((_) => saveCalled = true);

    await tester.pumpWidget(buildScreen(api, existing: {'fullName': 'Nguyễn Văn A'}));
    await tester.pumpAndSettle();
    await selectMonthUnit(tester);
    await enterSalary(tester, '15', '8');
    await tapSave(tester);

    expect(saveCalled, isFalse);
    expect(find.textContaining('không được lớn hơn'), findsOneWidget);
  });

  testWidgets('nhập giá trị cực lớn (nhầm tay) -> báo lỗi, KHÔNG gửi request', (tester) async {
    var saveCalled = false;
    final api = apiCapturing((_) => saveCalled = true);

    await tester.pumpWidget(buildScreen(api, existing: {'fullName': 'Nguyễn Văn A'}));
    await tester.pumpAndSettle();
    await selectMonthUnit(tester);
    // 999999 triệu/tháng = gần 1000 tỷ - chắc chắn là nhập nhầm.
    await enterSalary(tester, '999999', '999999');
    await tapSave(tester);

    expect(saveCalled, isFalse);
    expect(find.textContaining('quá lớn'), findsOneWidget);
  });

  // ---------- 8. Optional ----------

  testWidgets('backend trả null + để trống -> không crash, không gửi lương, các field khác vẫn lưu',
      (tester) async {
    Map<String, dynamic>? body;
    final api = apiCapturing((b) => body = b);

    await tester.pumpWidget(buildScreen(api, existing: {
      'fullName': 'Nguyễn Văn A',
      'desiredSalaryMin': null,
      'desiredSalaryMax': null,
      'salaryUnit': null,
    }));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tester.widget<TextField>(salaryMinField()).controller!.text, '');

    await tapSave(tester);

    expect(body, isNotNull, reason: 'để trống lương vẫn phải lưu được hồ sơ (trường optional)');
    expect(body!['desiredSalaryMin'], isNull);
    expect(body!['desiredSalaryMax'], isNull);
    expect(body!['fullName'], 'Nguyễn Văn A');
  });

  // ---------- 9. Regression: các field khác không đổi ----------

  testWidgets('regression: các field khác của hồ sơ vẫn được gửi đúng như cũ', (tester) async {
    Map<String, dynamic>? body;
    final api = apiCapturing((b) => body = b);

    await tester.pumpWidget(buildScreen(api, existing: {
      'fullName': 'Nguyễn Văn A',
      'experienceLevel': 'ONE_TO_3_YEARS',
      'dateOfBirth': '2000-05-15T00:00:00.000Z',
    }));
    await tester.pumpAndSettle();
    await enterSalary(tester, '25000', '35000');
    await tapSave(tester);

    expect(body!['fullName'], 'Nguyễn Văn A');
    expect(body!['experienceLevel'], 'ONE_TO_3_YEARS');
    expect(body!['shiftPreferences'], ['FLEXIBLE']);
    expect(body!['dateOfBirth'], '2000-05-15');
  });
}
