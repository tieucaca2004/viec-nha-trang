import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:viec_nha_trang/core/auth/session.dart';
import 'package:viec_nha_trang/core/network/api_client.dart';
import 'package:viec_nha_trang/features/auth/data/auth_service.dart';
import 'package:viec_nha_trang/features/employer/data/employer_profile_service.dart';
import 'package:viec_nha_trang/features/employer/presentation/employer_business_setup_screen.dart';
import 'package:viec_nha_trang/features/jobs/data/jobs_service.dart';
import '../helpers/in_memory_token_storage.dart';
import '../helpers/json_response.dart';

const _geolocatorChannel = MethodChannel('flutter.baseflow.com/geolocator');

/// Sửa lỗi High #8 (FULL AUDIT): trước đây employer location luôn lưu toạ độ trung tâm Nha
/// Trang hard-code. Test này chứng minh: (1) không thể lưu khi chưa có vị trí thật, (2) nhập
/// toạ độ thủ công thật thì lưu thành công VÀ gửi đúng giá trị đó lên API (không phải giá trị
/// hard-code cũ 12.2388/109.1967).
///
/// Form dài hơn viewport mặc định của widget test - nút LƯU HỒ SƠ chỉ được ListView (sliver-based,
/// build lazy theo viewport) build vào tree sau khi cuộn tới, nên dùng [dragUntilVisible] thay vì
/// [ensureVisible] (ensureVisible cần widget đã tồn tại sẵn trong tree để định vị nó).
void main() {
  Widget buildScreen(ApiClient api) {
    return MultiProvider(
      providers: [
        Provider<JobsService>(create: (_) => JobsService(api)),
        Provider<EmployerProfileService>(create: (_) => EmployerProfileService(api)),
        Provider<AuthService>(create: (_) => AuthService(api, api.session)),
      ],
      child: const MaterialApp(home: EmployerBusinessSetupScreen()),
    );
  }

  Future<void> scrollToSaveButton(WidgetTester tester) async {
    await tester.dragUntilVisible(
      find.text('LƯU HỒ SƠ'),
      find.byType(ListView),
      const Offset(0, -200),
    );
  }

  testWidgets('blocks saving when business name/area are filled but no location has been set', (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/areas')) {
          return jsonResponse([
            {'id': 'area-1', 'name': 'Vĩnh Hải'},
          ], 200);
        }
        if (request.url.path.endsWith('/cities')) {
          return jsonResponse([
            {'id': 'city-1', 'name': 'Nha Trang'},
          ], 200);
        }
        // Chưa có hồ sơ/cơ sở nào - đúng hành vi backend thật (employers.service.ts: 404 khi chưa
        // có EmployerProfile; locations trả [] rỗng thay vì 404, xem listMyLocations()).
        if (request.url.path.endsWith('/me/employer-profile') && request.method == 'GET') {
          return http.Response('not found', 404);
        }
        if (request.url.path.endsWith('/me/employer-profile/locations') && request.method == 'GET') {
          return jsonResponse([], 200);
        }
        if (request.url.path.endsWith('/me')) {
          return jsonResponse({'id': 'u1', 'phone': null, 'isPhoneVerified': false}, 200);
        }
        return http.Response('unexpected: ${request.url.path}', 404);
      }),
    );

    await tester.pumpWidget(buildScreen(api));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Tên cửa hàng/doanh nghiệp'), 'Quán Test');
    // Card trạng thái xác minh SĐT (đặc tả §4) đẩy Dropdown "Khu vực" ra khỏi viewport mặc định -
    // cuộn tới trước khi tap (cùng pattern dragUntilVisible dùng cho các control khác trong file).
    await tester.dragUntilVisible(
      find.byType(DropdownButtonFormField<String>),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vĩnh Hải').last);
    await tester.pumpAndSettle();

    await scrollToSaveButton(tester);
    await tester.tap(find.text('LƯU HỒ SƠ'));
    await tester.pumpAndSettle();

    await scrollToSaveButton(tester);
    expect(find.textContaining('Vui lòng xác định vị trí'), findsOneWidget);
  });

  testWidgets('saves with manually-entered coordinates, sending the real values (not the old hard-coded Nha Trang center)', (tester) async {
    Map<String, dynamic>? sentLocationBody;

    final session = Session(storage: InMemoryTokenStorage());
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/areas')) {
          return jsonResponse([
            {'id': 'area-1', 'name': 'Vĩnh Hải'},
          ], 200);
        }
        if (request.url.path.endsWith('/cities')) {
          return jsonResponse([
            {'id': 'city-1', 'name': 'Nha Trang'},
          ], 200);
        }
        if (request.url.path.endsWith('/me/employer-profile') && request.method == 'GET') {
          return http.Response('not found', 404);
        }
        if (request.url.path.endsWith('/me/employer-profile/locations') && request.method == 'GET') {
          return jsonResponse([], 200);
        }
        if (request.url.path.endsWith('/me/employer-profile') && request.method == 'PUT') {
          return jsonResponse({'id': 'emp-1', 'businessName': 'Quán Test'}, 200);
        }
        if (request.url.path.endsWith('/me/employer-profile/locations') && request.method == 'POST') {
          sentLocationBody = jsonDecode(request.body) as Map<String, dynamic>;
          return jsonResponse({'id': 'loc-1'}, 201);
        }
        if (request.url.path.endsWith('/me')) {
          return jsonResponse({'id': 'u1', 'phone': null, 'isPhoneVerified': false}, 200);
        }
        return http.Response('unexpected: ${request.method} ${request.url.path}', 404);
      }),
    );

    await tester.pumpWidget(buildScreen(api));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Tên cửa hàng/doanh nghiệp'), 'Quán Test');
    await tester.enterText(find.widgetWithText(TextField, 'Địa chỉ'), '12 Trần Phú');
    // Card trạng thái xác minh SĐT (đặc tả §4) đẩy Dropdown "Khu vực" ra khỏi viewport mặc định -
    // cuộn tới trước khi tap.
    await tester.dragUntilVisible(
      find.byType(DropdownButtonFormField<String>),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vĩnh Hải').last);
    await tester.pumpAndSettle();

    // Toạ độ THẬT do employer tự nhập - khác hẳn giá trị hard-code cũ 12.2388/109.1967.
    await tester.dragUntilVisible(
      find.widgetWithText(TextField, 'Vĩ độ (latitude)'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.enterText(find.widgetWithText(TextField, 'Vĩ độ (latitude)'), '12.300000');
    await tester.enterText(find.widgetWithText(TextField, 'Kinh độ (longitude)'), '109.150000');
    await tester.pumpAndSettle();

    expect(find.textContaining('Vị trí đã chọn: 12.300000, 109.150000'), findsOneWidget);

    await scrollToSaveButton(tester);
    await tester.tap(find.text('LƯU HỒ SƠ'));
    await tester.pumpAndSettle();

    expect(sentLocationBody, isNotNull);
    expect(sentLocationBody!['latitude'], 12.3);
    expect(sentLocationBody!['longitude'], 109.15);
    // Không còn gửi toạ độ trung tâm Nha Trang hard-code cũ.
    expect(sentLocationBody!['latitude'], isNot(12.2388));
    expect(sentLocationBody!['longitude'], isNot(109.1967));
  });

  testWidgets('tapping the GPS button does not crash when the platform location call fails', (tester) async {
    // Giả lập platform channel geolocator trả lỗi (giống thiết bị chưa cấp quyền/không có GPS
    // provider) thay vì để channel treo vô hạn trong môi trường widget test không có plugin thật.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      _geolocatorChannel,
      (call) async => throw PlatformException(code: 'ERROR', message: 'no location provider in test'),
    );
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_geolocatorChannel, null));

    final session = Session(storage: InMemoryTokenStorage());
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/areas') || request.url.path.endsWith('/cities')) {
          return jsonResponse([], 200);
        }
        if (request.url.path.endsWith('/me/employer-profile') && request.method == 'GET') {
          return http.Response('not found', 404);
        }
        if (request.url.path.endsWith('/me/employer-profile/locations') && request.method == 'GET') {
          return jsonResponse([], 200);
        }
        if (request.url.path.endsWith('/me')) {
          return jsonResponse({'id': 'u1', 'phone': null, 'isPhoneVerified': false}, 200);
        }
        return http.Response('unexpected: ${request.url.path}', 404);
      }),
    );

    await tester.pumpWidget(buildScreen(api));
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('DÙNG VỊ TRÍ GPS HIỆN TẠI'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.tap(find.text('DÙNG VỊ TRÍ GPS HIỆN TẠI'));
    await tester.pumpAndSettle();

    // Không throw ra ngoài, không crash - đúng nguyên tắc §22 không chặn app, chỉ báo lỗi rõ ràng.
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Không lấy được vị trí GPS'), findsOneWidget);
  });

  // Sửa lỗi §3 (mục 3 của yêu cầu UX): trước đây mở lại màn này luôn trống trơn dù đã lưu hồ sơ -
  // giờ phải hiển thị đúng dữ liệu thật đã lưu, và khoá phần vị trí (backend chưa có API cập
  // nhật cơ sở theo id, tránh tạo bản ghi trùng lặp khi lưu lại).
  testWidgets('mở lại màn hình hiển thị đúng dữ liệu doanh nghiệp/cơ sở đã lưu, khoá phần vị trí', (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/areas')) {
          return jsonResponse([
            {'id': 'area-1', 'name': 'Vĩnh Hải'},
          ], 200);
        }
        if (request.url.path.endsWith('/cities')) {
          return jsonResponse([
            {'id': 'city-1', 'name': 'Nha Trang'},
          ], 200);
        }
        if (request.url.path.endsWith('/me/employer-profile') && request.method == 'GET') {
          return jsonResponse({
            'id': 'emp-1',
            'businessName': 'Quán Test Đã Lưu',
            'description': 'Mô tả thật đã lưu trước đó',
          }, 200);
        }
        if (request.url.path.endsWith('/me/employer-profile/locations') && request.method == 'GET') {
          return jsonResponse([
            {
              'id': 'loc-1',
              'name': 'Chi nhánh Vĩnh Hải',
              'address': '12 Trần Phú',
              'cityId': 'city-1',
              'areaId': 'area-1',
              'latitude': 12.3,
              'longitude': 109.15,
              'phone': '0900000002',
            },
          ], 200);
        }
        if (request.url.path.endsWith('/me')) {
          return jsonResponse({'id': 'u1', 'phone': null, 'isPhoneVerified': false}, 200);
        }
        return http.Response('unexpected: ${request.method} ${request.url.path}', 404);
      }),
    );

    await tester.pumpWidget(buildScreen(api));
    await tester.pumpAndSettle();

    expect(find.text('Quán Test Đã Lưu'), findsOneWidget);
    expect(find.text('Mô tả thật đã lưu trước đó'), findsOneWidget);
    expect(find.text('Chi nhánh Vĩnh Hải'), findsOneWidget);
    expect(find.text('12 Trần Phú'), findsOneWidget);
    expect(find.text('0900000002'), findsOneWidget);

    // Phần vị trí bị khoá (đã có cơ sở) - GPS button không nhấn được. Kiểm tra trạng thái nút
    // NGAY khi nó còn nằm trong tree (ListView sliver-based sẽ un-build nút này nếu cuộn tiếp
    // xuống dưới để tới dòng "Vị trí đã chọn:"), rồi mới cuộn tiếp để kiểm tra dòng toạ độ.
    await tester.dragUntilVisible(
      find.text('DÙNG VỊ TRÍ GPS HIỆN TẠI'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    // find.byType(OutlinedButton) khớp theo runtimeType chính xác - OutlinedButton.icon() tạo ra
    // subclass riêng (_OutlinedButtonWithIcon) nên không khớp; dùng byWidgetPredicate với `is`.
    final gpsButton = tester.widget<OutlinedButton>(
      find.byWidgetPredicate((w) => w is OutlinedButton),
    );
    expect(gpsButton.onPressed, isNull);

    await tester.dragUntilVisible(
      find.textContaining('Vị trí đã chọn:'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    expect(find.textContaining('Vị trí đã chọn: 12.300000, 109.150000'), findsOneWidget);
  });
}
