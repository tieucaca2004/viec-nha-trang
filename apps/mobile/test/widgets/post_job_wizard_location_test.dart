import 'dart:async';
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
import 'package:viec_nha_trang/features/employer/presentation/employer_business_setup_screen.dart';
import 'package:viec_nha_trang/features/employer/presentation/post_job_wizard_screen.dart';
import 'package:viec_nha_trang/features/jobs/data/jobs_service.dart';
import '../helpers/in_memory_token_storage.dart';
import '../helpers/json_response.dart';

/// Bug thật trên Beta: nhà tuyển dụng MỚI (chưa có cơ sở nào) mở "Đăng tuyển" tới bước 5/8
/// ("Địa điểm") thì bị DEAD-END - chỉ thấy dòng "Bạn chưa có cơ sở nào. Hãy tạo hồ sơ cơ sở
/// trước khi đăng tin." mà KHÔNG có bất kỳ nút/đường dẫn nào để thực sự tạo cơ sở, nút TIẾP TỤC
/// mãi mãi bị mờ. Suite này khoá lại luồng đã sửa: bước 5 phải có nút "+ TẠO CƠ SỞ" mở đúng màn
/// EmployerBusinessSetupScreen (form tạo cơ sở đã có sẵn trong project, dùng đúng
/// addEmployerLocation()/POST /me/employer-profile/locations hiện có - không tạo API/màn hình mới,
/// không hard-code location giả), tạo xong quay lại đúng bước 5, danh sách cơ sở được nạp lại,
/// cơ sở mới tự động được chọn, và dữ liệu các bước 1-4 KHÔNG bị mất.
void main() {
  const categoriesJson = [
    {'id': 'cat-1', 'name': 'Phục vụ', 'icon': null},
  ];
  const areasJson = [
    {'id': 'area-1', 'name': 'Vĩnh Hải'},
  ];
  const citiesJson = [
    {'id': 'city-1', 'name': 'Nha Trang', 'slug': 'nha-trang'},
  ];
  const meJson = {
    'id': 'u1',
    'phone': '0900000000',
    'isPhoneVerified': true,
    'roles': ['JOB_SEEKER', 'EMPLOYER'],
  };

  Widget wrap(ApiClient api, Session session, Widget child) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<Session>.value(value: session),
        Provider<ApiClient>.value(value: api),
        Provider<JobsService>(create: (_) => JobsService(api)),
        Provider<EmployerProfileService>(create: (_) => EmployerProfileService(api)),
        Provider<EmployerJobsService>(create: (_) => EmployerJobsService(api)),
        Provider<AuthService>(create: (_) => AuthService(api, session)),
        Provider<GeocodingService>.value(
          value: GeocodingService(
            // http.Response mặc định encode Latin1 nếu không khai rõ charset - chuỗi tiếng Việt
            // ("Vĩnh Hải") làm constructor ném ArgumentError, MockClient bắt được rồi trả ra như
            // lỗi mạng, khiến geocode luôn "fail" âm thầm. PHẢI set content-type charset=utf-8.
            client: MockClient((request) async => http.Response(
                  '[{"display_name":"12 Trần Phú, Vĩnh Hải, Nha Trang","lat":"12.25","lon":"109.19","address":{"suburb":"Vĩnh Hải"}}]',
                  200,
                  headers: {'content-type': 'application/json; charset=utf-8'},
                )),
          ),
        ),
      ],
      child: MaterialApp(home: child),
    );
  }

  // find.byType(ListView) đơn thuần khớp NHIỀU ListView vì route wizard bên dưới vẫn còn trong
  // tree (chỉ offstage) - scope vào đúng ListView bên trong EmployerBusinessSetupScreen. Cuộn tới
  // "TÌM ĐỊA ĐIỂM" (đã tồn tại sẵn, chỉ ngoài viewport) - Card kết quả (ListTile) hiện ngay bên
  // dưới, vẫn còn trong viewport+cacheExtent nên không cần cuộn thêm để tap nó.
  Finder employerListView() => find.descendant(of: find.byType(EmployerBusinessSetupScreen), matching: find.byType(ListView));

  Future<void> scrollToSearchButton(WidgetTester tester) async {
    await tester.dragUntilVisible(
      find.text('TÌM ĐỊA ĐIỂM'),
      employerListView(),
      const Offset(0, -200),
    );
  }

  Session loggedInSession() {
    final session = Session(storage: InMemoryTokenStorage());
    session.accessToken = 'acc-1';
    session.refreshToken = 'ref-1';
    session.roles = ['JOB_SEEKER', 'EMPLOYER'];
    return session;
  }

  Future<void> reachLocationStep(WidgetTester tester) async {
    // Bước 1: chọn ngành nghề.
    expect(find.text('Bạn cần tuyển vị trí nào?'), findsOneWidget);
    await tester.tap(find.text('Phục vụ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TIẾP TỤC'));
    await tester.pumpAndSettle();
    // Bước 2: số lượng - mặc định 1, TIẾP TỤC sẵn enable.
    await tester.tap(find.text('TIẾP TỤC'));
    await tester.pumpAndSettle();
    // Bước 3: lương.
    final salaryFields = find.byType(TextField);
    await tester.enterText(salaryFields.at(0), '20000');
    await tester.enterText(salaryFields.at(1), '25000');
    await tester.pumpAndSettle();
    await tester.tap(find.text('TIẾP TỤC'));
    await tester.pumpAndSettle();
    // Bước 4: ca làm - chọn ít nhất 1.
    await tester.tap(find.text('Linh hoạt'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TIẾP TỤC'));
    await tester.pumpAndSettle();
    // Bước 5: Địa điểm.
    expect(find.text('Đăng tuyển (5/8)'), findsOneWidget);
  }

  // ---------- A. Employer ĐÃ có location ----------

  testWidgets('A. employer đã có cơ sở -> bước 5 hiện danh sách, chọn được, TIẾP TỤC enable', (tester) async {
    final session = loggedInSession();
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/categories')) return jsonResponse(categoriesJson, 200);
        if (path.endsWith('/me/employer-profile/locations')) {
          return jsonResponse([
            {'id': 'loc-1', 'name': 'Chi nhánh Vĩnh Hải'},
          ], 200);
        }
        return http.Response('unexpected: $path', 404);
      }),
    );

    await tester.pumpWidget(wrap(api, session, const PostJobWizardScreen()));
    await tester.pumpAndSettle();
    await reachLocationStep(tester);

    expect(find.text('Bạn chưa có cơ sở nào.'), findsNothing);
    expect(find.text('Chi nhánh Vĩnh Hải'), findsOneWidget);

    FilledButton nextButton() => tester.widget<FilledButton>(
          find.ancestor(of: find.text('TIẾP TỤC'), matching: find.byType(FilledButton)),
        );
    // Location đầu tiên được tự động chọn khi tải danh sách (_loadOptions).
    expect(nextButton().onPressed, isNotNull);
  });

  // ---------- B. Employer CHƯA có location -> không dead-end ----------

  testWidgets('B. employer chưa có cơ sở -> KHÔNG dead-end, hiện nút "+ TẠO CƠ SỞ"', (tester) async {
    final session = loggedInSession();
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/categories')) return jsonResponse(categoriesJson, 200);
        if (path.endsWith('/me/employer-profile/locations')) return jsonResponse([], 200);
        return http.Response('unexpected: $path', 404);
      }),
    );

    await tester.pumpWidget(wrap(api, session, const PostJobWizardScreen()));
    await tester.pumpAndSettle();
    await reachLocationStep(tester);

    expect(find.text('Bạn chưa có cơ sở nào.'), findsOneWidget);
    expect(find.text('+ TẠO CƠ SỞ'), findsOneWidget);

    FilledButton nextButton() => tester.widget<FilledButton>(
          find.ancestor(of: find.text('TIẾP TỤC'), matching: find.byType(FilledButton)),
        );
    expect(nextButton().onPressed, isNull, reason: 'chưa chọn cơ sở nào thì TIẾP TỤC vẫn phải disabled');
  });

  // ---------- C/F. Tạo cơ sở thành công: quay lại bước 5, location mới xuất hiện+được chọn, dữ liệu bước 1-4 còn nguyên ----------

  testWidgets('C/F. tạo cơ sở thành công -> quay lại bước 5, cơ sở mới được chọn, TIẾP TỤC enable, dữ liệu bước 1 còn nguyên',
      (tester) async {
    final session = loggedInSession();
    var locationsCallCount = 0;
    var createCallCount = 0;
    var createdLocation = false;
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/categories')) return jsonResponse(categoriesJson, 200);
        if (path.endsWith('/areas')) return jsonResponse(areasJson, 200);
        if (path.endsWith('/cities')) return jsonResponse(citiesJson, 200);
        if (path.endsWith('/me') && request.method == 'GET') return jsonResponse(meJson, 200);
        if (path.endsWith('/me/employer-profile') && request.method == 'GET') {
          return jsonResponse({'message': 'Chưa có hồ sơ nhà tuyển dụng.'}, 404);
        }
        if (path.endsWith('/me/employer-profile') && request.method == 'PUT') {
          return jsonResponse({'businessName': 'Quán Test'}, 200);
        }
        if (path.endsWith('/me/employer-profile/locations') && request.method == 'GET') {
          locationsCallCount += 1;
          if (!createdLocation) return jsonResponse([], 200);
          return jsonResponse([
            {'id': 'loc-new', 'name': 'Quán Test'},
          ], 200);
        }
        if (path.endsWith('/me/employer-profile/locations') && request.method == 'POST') {
          createCallCount += 1;
          createdLocation = true;
          return jsonResponse({'id': 'loc-new', 'name': 'Quán Test'}, 201);
        }
        return http.Response('unexpected: $path', 404);
      }),
    );

    await tester.pumpWidget(wrap(api, session, const PostJobWizardScreen()));
    await tester.pumpAndSettle();
    await reachLocationStep(tester);

    await tester.tap(find.text('+ TẠO CƠ SỞ'));
    await tester.pumpAndSettle();
    expect(find.byType(EmployerBusinessSetupScreen), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Tên cửa hàng/doanh nghiệp'), 'Quán Test');
    await tester.enterText(find.widgetWithText(TextField, 'Địa chỉ (vd: 37 Hồng Bàng, Nha Trang)'), '12 Trần Phú');
    await scrollToSearchButton(tester);
    await tester.tap(find.text('TÌM ĐỊA ĐIỂM'));
    await tester.pumpAndSettle();
    // Nominatim mock trả suburb "Vĩnh Hải" - tự map đúng Area duy nhất trong areasJson, không cần
    // tự bấm chip nữa.
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(find.text('LƯU HỒ SƠ'), employerListView(), const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('LƯU HỒ SƠ'));
    await tester.pumpAndSettle();

    // Quay đúng về bước 5/8 (push, không phải điều hướng lại từ đầu wizard).
    expect(find.byType(EmployerBusinessSetupScreen), findsNothing);
    expect(find.text('Đăng tuyển (5/8)'), findsOneWidget);
    expect(createCallCount, 1);
    expect(locationsCallCount, greaterThanOrEqualTo(2), reason: 'phải nạp lại danh sách sau khi tạo');

    expect(find.text('Bạn chưa có cơ sở nào.'), findsNothing);
    expect(find.text('Quán Test'), findsOneWidget);

    final chip = tester.widget<ChoiceChip>(
      find.ancestor(of: find.text('Quán Test'), matching: find.byType(ChoiceChip)),
    );
    expect(chip.selected, isTrue, reason: 'cơ sở vừa tạo phải tự động được chọn');

    FilledButton nextButton() => tester.widget<FilledButton>(
          find.ancestor(of: find.text('TIẾP TỤC'), matching: find.byType(FilledButton)),
        );
    expect(nextButton().onPressed, isNotNull);

    // F. Dữ liệu bước 1 (ngành nghề) không bị mất - quay lại tận bước 1 kiểm tra lựa chọn cũ.
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
    }
    expect(find.text('Đăng tuyển (1/8)'), findsOneWidget);
    final categoryChip = tester.widget<ChoiceChip>(
      find.ancestor(of: find.text('Phục vụ'), matching: find.byType(ChoiceChip)),
    );
    expect(categoryChip.selected, isTrue);
  });

  // ---------- D. Tạo cơ sở lỗi -> không crash, vẫn ở form, có retry ----------

  testWidgets('D. tạo cơ sở lỗi 500 -> hiện lỗi, KHÔNG crash, vẫn ở form để thử lại', (tester) async {
    final session = loggedInSession();
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/categories')) return jsonResponse(categoriesJson, 200);
        if (path.endsWith('/areas')) return jsonResponse(areasJson, 200);
        if (path.endsWith('/cities')) return jsonResponse(citiesJson, 200);
        if (path.endsWith('/me') && request.method == 'GET') return jsonResponse(meJson, 200);
        if (path.endsWith('/me/employer-profile') && request.method == 'GET') {
          return jsonResponse({'message': 'Chưa có hồ sơ nhà tuyển dụng.'}, 404);
        }
        if (path.endsWith('/me/employer-profile') && request.method == 'PUT') {
          return jsonResponse({'businessName': 'Quán Test'}, 200);
        }
        if (path.endsWith('/me/employer-profile/locations') && request.method == 'GET') return jsonResponse([], 200);
        if (path.endsWith('/me/employer-profile/locations') && request.method == 'POST') {
          return jsonResponse({'message': 'Hệ thống đang bận'}, 500);
        }
        return http.Response('unexpected: $path', 404);
      }),
    );

    await tester.pumpWidget(wrap(api, session, const PostJobWizardScreen()));
    await tester.pumpAndSettle();
    await reachLocationStep(tester);

    await tester.tap(find.text('+ TẠO CƠ SỞ'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Tên cửa hàng/doanh nghiệp'), 'Quán Test');
    await tester.enterText(find.widgetWithText(TextField, 'Địa chỉ (vd: 37 Hồng Bàng, Nha Trang)'), '12 Trần Phú');
    await scrollToSearchButton(tester);
    await tester.tap(find.text('TÌM ĐỊA ĐIỂM'));
    await tester.pumpAndSettle();
    // Nominatim mock trả suburb "Vĩnh Hải" - tự map đúng Area duy nhất trong areasJson, không cần
    // tự bấm chip nữa.
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(find.text('LƯU HỒ SƠ'), employerListView(), const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('LƯU HỒ SƠ'));
    await tester.pumpAndSettle();

    // Không crash, vẫn ở form (chưa pop), thấy thông báo lỗi để thử lại - dữ liệu đã nhập còn nguyên.
    expect(find.byType(EmployerBusinessSetupScreen), findsOneWidget);
    expect(find.text('Hệ thống đang bận. Vui lòng thử lại sau.'), findsOneWidget);
    // Form là ListView ảo hoá (sliver) - cuộn lại đầu để field tên doanh nghiệp được build lại rồi
    // mới kiểm tra giá trị còn nguyên (không bị mất khi tạo cơ sở lỗi).
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(find.text('Quán Test'), findsOneWidget);
  });

  // ---------- E. Double submit không tạo trùng lặp ----------

  testWidgets('E. bấm LƯU HỒ SƠ nhiều lần liên tiếp trong lúc request đầu CHƯA xong -> chỉ gửi ĐÚNG 1 request tạo cơ sở',
      (tester) async {
    final session = loggedInSession();
    var createCallCount = 0;
    // Cổng chặn response tạo cơ sở - giữ request ĐẦU TIÊN đang treo để mô phỏng đúng tình huống
    // double-submit thật: người dùng bấm nhiều lần trong lúc mạng còn đang xử lý, không phải chỉ
    // 2 lệnh gọi tình cờ lọt qua nhau giữa các microtask của test.
    final createGate = Completer<void>();
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/categories')) return jsonResponse(categoriesJson, 200);
        if (path.endsWith('/areas')) return jsonResponse(areasJson, 200);
        if (path.endsWith('/cities')) return jsonResponse(citiesJson, 200);
        if (path.endsWith('/me') && request.method == 'GET') return jsonResponse(meJson, 200);
        if (path.endsWith('/me/employer-profile') && request.method == 'GET') {
          return jsonResponse({'message': 'Chưa có hồ sơ nhà tuyển dụng.'}, 404);
        }
        if (path.endsWith('/me/employer-profile') && request.method == 'PUT') {
          return jsonResponse({'businessName': 'Quán Test'}, 200);
        }
        if (path.endsWith('/me/employer-profile/locations') && request.method == 'GET') return jsonResponse([], 200);
        if (path.endsWith('/me/employer-profile/locations') && request.method == 'POST') {
          createCallCount += 1;
          await createGate.future;
          return jsonResponse({'id': 'loc-new', 'name': 'Quán Test'}, 201);
        }
        return http.Response('unexpected: $path', 404);
      }),
    );

    await tester.pumpWidget(wrap(api, session, const PostJobWizardScreen()));
    await tester.pumpAndSettle();
    await reachLocationStep(tester);

    await tester.tap(find.text('+ TẠO CƠ SỞ'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Tên cửa hàng/doanh nghiệp'), 'Quán Test');
    await tester.enterText(find.widgetWithText(TextField, 'Địa chỉ (vd: 37 Hồng Bàng, Nha Trang)'), '12 Trần Phú');
    await scrollToSearchButton(tester);
    await tester.tap(find.text('TÌM ĐỊA ĐIỂM'));
    await tester.pumpAndSettle();
    // Nominatim mock trả suburb "Vĩnh Hải" - tự map đúng Area duy nhất trong areasJson, không cần
    // tự bấm chip nữa.
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(find.text('LƯU HỒ SƠ'), employerListView(), const Offset(0, -200));
    await tester.pumpAndSettle();
    // Bấm liên tiếp nhiều lần trong lúc request tạo cơ sở đầu tiên vẫn đang treo (createGate chưa
    // mở) - đúng kịch bản double-submit thật. Bấm theo TYPE (không theo text 'LƯU HỒ SƠ') vì ngay
    // sau lần bấm đầu, nút chuyển sang hiện spinner (_saving=true) nên text đó biến mất - nhưng
    // đó chính xác là hành vi ĐÚNG cần khoá lại: nút không còn nhận tap thêm nữa.
    final saveButton = find.byType(FilledButton);
    await tester.tap(saveButton);
    await tester.pump();
    await tester.tap(saveButton, warnIfMissed: false);
    await tester.pump();
    await tester.tap(saveButton, warnIfMissed: false);
    await tester.pump();

    expect(createCallCount, 1, reason: 'nút phải khoá NGAY khi request đầu còn đang treo, không đợi rebuild');

    createGate.complete();
    await tester.pumpAndSettle();

    expect(createCallCount, 1);
  });
}
