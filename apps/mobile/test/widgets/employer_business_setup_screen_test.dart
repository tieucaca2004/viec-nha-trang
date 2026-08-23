import 'dart:async';
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
import 'package:viec_nha_trang/features/employer/data/geocoding_service.dart';
import 'package:viec_nha_trang/features/employer/presentation/employer_business_setup_screen.dart';
import 'package:viec_nha_trang/features/jobs/data/jobs_service.dart';
import '../helpers/in_memory_token_storage.dart';
import '../helpers/json_response.dart';

const _geolocatorChannel = MethodChannel('flutter.baseflow.com/geolocator');

/// Regression cho bug thật "VUI LÒNG NHẬP TÊN DOANH NGHIỆP VÀ CHỌN KHU VỰC" (báo cáo từ APK thật):
/// root cause là _filteredAreas trả rỗng khi /areas CHƯA TẢI ĐƯỢC (không phải khi search không
/// khớp) nhưng UI cũ hiển thị nhầm chung 1 thông báo "Không tìm thấy khu vực phù hợp." - xem test
/// "shows a distinct retry message when /areas itself fails to load" bên dưới, chứng minh bằng
/// git stash: test này FAIL trên code cũ (luôn hiện "Không tìm thấy khu vực phù hợp." bất kể lý do).
///
/// UI vị trí cũng đổi hẳn: không còn 2 ô nhập Vĩ độ/Kinh độ - thay bằng tìm địa chỉ (Nominatim,
/// không cần Google API key) + GPS, tự map sang Area đã có sẵn trong DB, có fallback chọn thủ công
/// khi không map được (đặc tả FIX LỖI mục 2-5).
///
/// Form dài hơn viewport mặc định của widget test - nút LƯU HỒ SƠ chỉ được ListView (sliver-based,
/// build lazy theo viewport) build vào tree sau khi cuộn tới, nên dùng [dragUntilVisible] thay vì
/// [ensureVisible] (ensureVisible cần widget đã tồn tại sẵn trong tree để định vị nó).
void main() {
  Widget buildScreen(ApiClient api, {http.Client? geoClient}) {
    return MultiProvider(
      providers: [
        Provider<JobsService>(create: (_) => JobsService(api)),
        Provider<EmployerProfileService>(create: (_) => EmployerProfileService(api)),
        Provider<AuthService>(create: (_) => AuthService(api, api.session)),
        Provider<GeocodingService>.value(value: GeocodingService(client: geoClient ?? MockClient((_) async => http.Response('{}', 200)))),
      ],
      child: const MaterialApp(home: EmployerBusinessSetupScreen()),
    );
  }

  // Cuộn tới nút "TÌM ĐỊA ĐIỂM" (đã tồn tại sẵn trong tree, chỉ ngoài viewport) - sau khi bấm nó,
  // Card kết quả tìm kiếm (ListTile) và dòng "Khu vực đã/chưa được tự động xác định" đều nằm ngay
  // sát bên dưới trong cùng vùng đã cuộn tới, vẫn còn trong viewport+cacheExtent nên KHÔNG cần
  // cuộn thêm để tap/kiểm tra chúng (đã verify bằng test độc lập).
  Future<void> scrollToSearchButton(WidgetTester tester) async {
    await tester.dragUntilVisible(
      find.text('TÌM ĐỊA ĐIỂM'),
      find.byType(ListView),
      const Offset(0, -200),
    );
  }

  Future<void> scrollToSaveButton(WidgetTester tester) async {
    await tester.dragUntilVisible(
      find.text('LƯU HỒ SƠ'),
      find.byType(ListView),
      const Offset(0, -200),
    );
  }

  // http.Response mặc định encode body bằng Latin1 nếu không khai rõ charset (cùng lỗi đã biết ở
  // helpers/json_response.dart) - chuỗi tiếng Việt trong display_name/address (vd "Vĩnh Hải") làm
  // Response constructor ném ArgumentError, MockClient bắt được và trả ra như lỗi mạng, khiến
  // GeocodingService luôn "fail" một cách im lặng. PHẢI set content-type charset=utf-8.
  http.Response nominatimSearchResponse({required String displayName, required double lat, required double lon, Map<String, dynamic>? address}) {
    return http.Response(
      jsonEncode([
        {
          'display_name': displayName,
          'lat': lat.toString(),
          'lon': lon.toString(),
          'address': address ?? {},
        },
      ]),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  MockClient areaBackendClient({List<Map<String, dynamic>>? areas, void Function(Map<String, dynamic>)? onCreateLocation}) {
    return MockClient((request) async {
      if (request.url.path.endsWith('/areas')) {
        return jsonResponse(areas ?? [{'id': 'area-1', 'name': 'Vĩnh Hải'}], 200);
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
        onCreateLocation?.call(jsonDecode(request.body) as Map<String, dynamic>);
        return jsonResponse({'id': 'loc-1'}, 201);
      }
      if (request.url.path.endsWith('/me')) {
        return jsonResponse({'id': 'u1', 'phone': null, 'isPhoneVerified': false}, 200);
      }
      return http.Response('unexpected: ${request.method} ${request.url.path}', 404);
    });
  }

  testWidgets('blocks saving when business name is filled but no location/address has been chosen', (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    final api = ApiClient(session, httpClient: areaBackendClient());

    await tester.pumpWidget(buildScreen(api));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Tên cửa hàng/doanh nghiệp'), 'Quán Test');

    await scrollToSaveButton(tester);
    await tester.tap(find.text('LƯU HỒ SƠ'));
    await tester.pumpAndSettle();

    await scrollToSaveButton(tester);
    expect(find.textContaining('Vui lòng nhập tên doanh nghiệp và xác định địa chỉ'), findsOneWidget);
  });

  // CASE 1 (đặc tả mục 8): tên "37 hong bàng", địa chỉ "37/ hồng bàng", toạ độ thật 12.242013/
  // 109.188444 (từ vị trí GPS thật trên máy tester theo báo cáo bug) - geocode trả về 1 địa chỉ
  // có suburb khớp Area "Vĩnh Hải" đã có sẵn trong DB -> KHÔNG được báo lỗi "chọn khu vực" vì hệ
  // thống tự xác định được, và lưu thành công. Dùng luồng "TÌM ĐỊA ĐIỂM" (không phải nút GPS thật)
  // để test không phụ thuộc giao thức nhị phân Pigeon riêng của plugin geolocator (đã test permission
  // denied/lỗi platform riêng ở 2 test bên dưới) - phần logic auto-map Area từ toạ độ+địa chỉ geocode
  // trả về là NHƯ NHAU dù vào từ GPS hay từ search, vì cả 2 đều gọi chung _applyGeocodingResult().
  testWidgets('CASE 1: real-world bug repro - name/address/coords filled, area auto-mapped from geocode, save succeeds', (tester) async {
    Map<String, dynamic>? sentBody;
    final session = Session(storage: InMemoryTokenStorage());
    final api = ApiClient(session, httpClient: areaBackendClient(onCreateLocation: (b) => sentBody = b));
    final geoClient = MockClient((request) async => nominatimSearchResponse(
          displayName: '37 Hồng Bàng, Vĩnh Hải, Nha Trang, Khánh Hòa, Việt Nam',
          lat: 12.242013,
          lon: 109.188444,
          address: {'suburb': 'Vĩnh Hải', 'city': 'Nha Trang'},
        ));

    await tester.pumpWidget(buildScreen(api, geoClient: geoClient));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Tên cửa hàng/doanh nghiệp'), '37 hong bàng');
    await tester.dragUntilVisible(
      find.widgetWithText(TextField, 'Địa chỉ (vd: 37 Hồng Bàng, Nha Trang)'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.enterText(find.widgetWithText(TextField, 'Địa chỉ (vd: 37 Hồng Bàng, Nha Trang)'), '37/ hồng bàng');
    await scrollToSearchButton(tester);
    await tester.tap(find.text('TÌM ĐỊA ĐIỂM'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();

    // Area đã được tự động chọn từ geocode - không cần thao tác thêm.
    expect(find.textContaining('Khu vực đã được tự động xác định'), findsOneWidget);

    await scrollToSaveButton(tester);
    await tester.tap(find.text('LƯU HỒ SƠ'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Vui lòng nhập tên doanh nghiệp và chọn khu vực'), findsNothing);
    expect(sentBody, isNotNull);
    expect(sentBody!['areaId'], 'area-1');
    expect(sentBody!['latitude'], 12.242013);
    expect(sentBody!['longitude'], 109.188444);
  });

  // CASE 2/6 (đặc tả mục 4/8): Nominatim trả địa chỉ nhưng KHÔNG map được Area nào -> không báo
  // "Không tìm thấy khu vực phù hợp." rồi khoá người dùng, mà cho chọn thủ công, và lưu được sau
  // khi chọn.
  testWidgets('CASE 2/6: address found but no Area match -> manual picker shown, save succeeds after manual pick', (tester) async {
    Map<String, dynamic>? sentBody;
    final session = Session(storage: InMemoryTokenStorage());
    final api = ApiClient(session, httpClient: areaBackendClient(onCreateLocation: (b) => sentBody = b));
    final geoClient = MockClient((request) async => nominatimSearchResponse(
          displayName: '1 Đường Không Xác Định, Việt Nam',
          lat: 12.25,
          lon: 109.2,
          address: {'city': 'Somewhere Else'},
        ));

    await tester.pumpWidget(buildScreen(api, geoClient: geoClient));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Tên cửa hàng/doanh nghiệp'), 'Quán Test');
    await tester.dragUntilVisible(
      find.widgetWithText(TextField, 'Địa chỉ (vd: 37 Hồng Bàng, Nha Trang)'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.enterText(find.widgetWithText(TextField, 'Địa chỉ (vd: 37 Hồng Bàng, Nha Trang)'), '1 đường không xác định');
    await scrollToSearchButton(tester);
    await tester.tap(find.text('TÌM ĐỊA ĐIỂM'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();

    expect(find.textContaining('Khu vực chưa được xác định tự động'), findsOneWidget);

    await scrollToSaveButton(tester);
    await tester.tap(find.text('LƯU HỒ SƠ'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Vui lòng chọn khu vực'), findsOneWidget);

    await tester.dragUntilVisible(
      find.widgetWithText(ChoiceChip, 'Vĩnh Hải'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'Vĩnh Hải'));
    await tester.pumpAndSettle();

    await scrollToSaveButton(tester);
    await tester.tap(find.text('LƯU HỒ SƠ'));
    await tester.pumpAndSettle();

    expect(sentBody, isNotNull);
    expect(sentBody!['areaId'], 'area-1');
  });

  // CASE 3 (đặc tả mục 8): search Area không phân biệt hoa/thường/dấu.
  testWidgets('CASE 3: area search matches regardless of case/diacritics ("vinh hai"/"VINH HAI"/"Vĩnh Hải")', (tester) async {
    final manyAreas = [
      {'id': 'a1', 'name': 'Lộc Thọ'},
      {'id': 'a2', 'name': 'Tân Lập'},
      {'id': 'a3', 'name': 'Phước Tiến'},
      {'id': 'a4', 'name': 'Phước Tân'},
      {'id': 'a5', 'name': 'Phước Long'},
      {'id': 'a6', 'name': 'Phước Hải'},
      {'id': 'a7', 'name': 'Vĩnh Hải'},
      {'id': 'a8', 'name': 'Vĩnh Phước'},
    ];
    final session = Session(storage: InMemoryTokenStorage());
    final api = ApiClient(session, httpClient: areaBackendClient(areas: manyAreas));

    await tester.pumpWidget(buildScreen(api));
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.widgetWithText(TextField, 'Tìm khu vực (vd: Vĩnh Hải, Lộc Thọ)'),
      find.byType(ListView),
      const Offset(0, -200),
    );

    for (final query in ['vinh hai', 'VINH HAI', 'Vĩnh Hải']) {
      await tester.enterText(find.widgetWithText(TextField, 'Tìm khu vực (vd: Vĩnh Hải, Lộc Thọ)'), query);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ChoiceChip, 'Vĩnh Hải'), findsOneWidget, reason: 'query="$query"');
      expect(find.widgetWithText(ChoiceChip, 'Lộc Thọ'), findsNothing, reason: 'query="$query"');
    }
  });

  // CASE 4 (đặc tả mục 3/8): địa danh cũ "Vĩnh Hải" trong response Nominatim phải map đúng về
  // Area "Vĩnh Hải" đã có sẵn - không bịa Area mới.
  testWidgets('CASE 4: old locality name from geocoding address maps to the existing Area with the same name', (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    final api = ApiClient(session, httpClient: areaBackendClient(areas: [
      {'id': 'area-1', 'name': 'Vĩnh Hải'},
      {'id': 'area-2', 'name': 'Lộc Thọ'},
    ]));
    final geoClient = MockClient((request) async => nominatimSearchResponse(
          displayName: 'Vĩnh Hải, Nha Trang, Khánh Hòa, Việt Nam',
          lat: 12.26,
          lon: 109.2,
          address: {'suburb': 'Vĩnh Hải'},
        ));

    await tester.pumpWidget(buildScreen(api, geoClient: geoClient));
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.widgetWithText(TextField, 'Địa chỉ (vd: 37 Hồng Bàng, Nha Trang)'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.enterText(find.widgetWithText(TextField, 'Địa chỉ (vd: 37 Hồng Bàng, Nha Trang)'), 'Vĩnh Hải');
    await scrollToSearchButton(tester);
    await tester.tap(find.text('TÌM ĐỊA ĐIỂM'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.widgetWithText(ChoiceChip, 'Vĩnh Hải'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    final chip = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Vĩnh Hải'));
    expect(chip.selected, isTrue);
  });

  // CASE 5 (đặc tả mục 8): latitude/longitude KHÔNG được xuất hiện trong UI nữa.
  testWidgets('CASE 5: latitude/longitude input fields no longer appear in the UI', (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    final api = ApiClient(session, httpClient: areaBackendClient());

    await tester.pumpWidget(buildScreen(api));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Vĩ độ (latitude)'), findsNothing);
    expect(find.widgetWithText(TextField, 'Kinh độ (longitude)'), findsNothing);
  });

  // Đặc tả TINH CHỈNH GEOCODING mục 2: lỗi geocoding (bất kể loại) KHÔNG được xoá dữ liệu form đã
  // nhập (tên/địa chỉ/SĐT) hay Area đã chọn trước đó từ 1 lần search thành công trước.
  testWidgets('geocoding search error preserves form data and a previously auto-matched area', (tester) async {
    var geoCallCount = 0;
    final session = Session(storage: InMemoryTokenStorage());
    final api = ApiClient(session, httpClient: areaBackendClient());
    final geoClient = MockClient((request) async {
      geoCallCount++;
      if (geoCallCount == 1) {
        return nominatimSearchResponse(
          displayName: 'Vĩnh Hải, Nha Trang',
          lat: 12.26,
          lon: 109.2,
          address: {'suburb': 'Vĩnh Hải'},
        );
      }
      return http.Response('server error', 500);
    });

    await tester.pumpWidget(buildScreen(api, geoClient: geoClient));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Tên cửa hàng/doanh nghiệp'), 'Quán Test');
    await tester.enterText(find.widgetWithText(TextField, 'Số điện thoại cơ sở (không bắt buộc)'), '0900000009');
    await tester.dragUntilVisible(
      find.widgetWithText(TextField, 'Địa chỉ (vd: 37 Hồng Bàng, Nha Trang)'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.enterText(find.widgetWithText(TextField, 'Địa chỉ (vd: 37 Hồng Bàng, Nha Trang)'), 'Vĩnh Hải');

    // Lần search đầu: thành công, tự map Area.
    await scrollToSearchButton(tester);
    await tester.tap(find.text('TÌM ĐỊA ĐIỂM'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.textContaining('Khu vực đã được tự động xác định'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    expect(find.textContaining('Khu vực đã được tự động xác định'), findsOneWidget);

    // Lần search thứ 2 (vd người dùng đổi ý gõ địa chỉ khác rồi tìm lại): server lỗi 500.
    await tester.enterText(find.widgetWithText(TextField, 'Địa chỉ (vd: 37 Hồng Bàng, Nha Trang)'), 'địa chỉ khác');
    await scrollToSearchButton(tester);
    await tester.tap(find.text('TÌM ĐỊA ĐIỂM'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Dịch vụ tìm địa điểm đang gặp lỗi'), findsOneWidget);
    // Area đã tự map từ lần search trước KHÔNG bị xoá chỉ vì lần search sau đó lỗi.
    expect(find.textContaining('Khu vực đã được tự động xác định'), findsOneWidget);

    // Dữ liệu form (tên/SĐT) vẫn còn nguyên - cuộn lại đầu để field được build lại rồi kiểm tra.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 800));
    await tester.pumpAndSettle();
    expect(find.text('Quán Test'), findsOneWidget);
    expect(find.text('0900000009'), findsOneWidget);
  });

  // Đặc tả TINH CHỈNH GEOCODING mục "double tap": bấm liên tiếp nút TÌM ĐỊA ĐIỂM trong lúc request
  // đầu CHƯA xong chỉ được gửi ĐÚNG 1 request tìm kiếm.
  testWidgets('double-tapping TÌM ĐỊA ĐIỂM only sends 1 search request', (tester) async {
    var searchCallCount = 0;
    final searchGate = Completer<void>();
    final session = Session(storage: InMemoryTokenStorage());
    final api = ApiClient(session, httpClient: areaBackendClient());
    final geoClient = MockClient((request) async {
      searchCallCount++;
      await searchGate.future;
      return nominatimSearchResponse(displayName: 'Vĩnh Hải, Nha Trang', lat: 12.26, lon: 109.2, address: {'suburb': 'Vĩnh Hải'});
    });

    await tester.pumpWidget(buildScreen(api, geoClient: geoClient));
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.widgetWithText(TextField, 'Địa chỉ (vd: 37 Hồng Bàng, Nha Trang)'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.enterText(find.widgetWithText(TextField, 'Địa chỉ (vd: 37 Hồng Bàng, Nha Trang)'), 'Vĩnh Hải');
    await scrollToSearchButton(tester);

    // Bấm liên tiếp trong lúc request đầu (bị chặn bởi searchGate) vẫn còn treo - nút TÌM ĐỊA
    // ĐIỂM phải tự khoá (_searching=true) ngay từ lần bấm đầu, không đợi rebuild. Tap theo TYPE
    // (OutlinedButton đầu tiên trong Row = nút TÌM ĐỊA ĐIỂM, đứng trước nút GPS trong widget tree)
    // vì sau lần bấm đầu, text 'TÌM ĐỊA ĐIỂM' biến mất (thay bằng spinner).
    final searchButtonFinder = find.byWidgetPredicate((w) => w is OutlinedButton).first;
    await tester.tap(searchButtonFinder);
    await tester.pump();
    await tester.tap(searchButtonFinder, warnIfMissed: false);
    await tester.pump();
    await tester.tap(searchButtonFinder, warnIfMissed: false);
    await tester.pump();

    expect(searchCallCount, 1, reason: 'nút phải khoá NGAY khi request đầu còn đang treo');
    searchGate.complete();
    await tester.pumpAndSettle();
    expect(searchCallCount, 1);
  });

  // Root cause thật của bug (xem docstring đầu file): /areas thất bại phải hiện thông báo RIÊNG
  // + nút THỬ LẠI, không được gộp chung với "search không khớp".
  testWidgets('shows a distinct retry message when /areas itself fails to load (not "no search match")', (tester) async {
    var areasCallCount = 0;
    final session = Session(storage: InMemoryTokenStorage());
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/areas')) {
          areasCallCount++;
          if (areasCallCount == 1) return http.Response('server error', 500);
          return jsonResponse([
            {'id': 'area-1', 'name': 'Vĩnh Hải'},
          ], 200);
        }
        if (request.url.path.endsWith('/cities')) return jsonResponse([], 200);
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
      find.text('THỬ LẠI'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    // KHÔNG được hiện thông báo sai "Không tìm thấy khu vực phù hợp." khi thực ra là lỗi tải.
    expect(find.text('Không tìm thấy khu vực phù hợp.'), findsNothing);
    expect(find.textContaining('Chưa tải được danh sách khu vực'), findsOneWidget);

    await tester.tap(find.text('THỬ LẠI'));
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.widgetWithText(ChoiceChip, 'Vĩnh Hải'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    expect(find.widgetWithText(ChoiceChip, 'Vĩnh Hải'), findsOneWidget);
  });

  testWidgets('GPS permission denied does not crash and suggests manual address search', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      _geolocatorChannel,
      (call) async {
        if (call.method == 'checkPermission') return 0; // LocationPermission.denied
        if (call.method == 'requestPermission') return 0;
        return null;
      },
    );
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_geolocatorChannel, null));

    final session = Session(storage: InMemoryTokenStorage());
    final api = ApiClient(session, httpClient: areaBackendClient());

    await tester.pumpWidget(buildScreen(api));
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('DÙNG VỊ TRÍ HIỆN TẠI'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.tap(find.text('DÙNG VỊ TRÍ HIỆN TẠI'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Không có quyền vị trí'), findsOneWidget);
  });

  testWidgets('platform GPS failure does not crash and suggests manual address search', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      _geolocatorChannel,
      (call) async => throw PlatformException(code: 'ERROR', message: 'no location provider in test'),
    );
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_geolocatorChannel, null));

    final session = Session(storage: InMemoryTokenStorage());
    final api = ApiClient(session, httpClient: areaBackendClient());

    await tester.pumpWidget(buildScreen(api));
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('DÙNG VỊ TRÍ HIỆN TẠI'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.tap(find.text('DÙNG VỊ TRÍ HIỆN TẠI'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Không lấy được vị trí hiện tại'), findsOneWidget);
  });

  // CASE 7 (đặc tả mục 8): double tap LƯU HỒ SƠ chỉ gửi đúng 1 request tạo cơ sở.
  testWidgets('CASE 7: double-tapping LƯU HỒ SƠ only sends 1 create-location request', (tester) async {
    var createCount = 0;
    final createGate = Completer<void>();
    final session = Session(storage: InMemoryTokenStorage());
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/areas')) {
          return jsonResponse([
            {'id': 'area-1', 'name': 'Vĩnh Hải'},
          ], 200);
        }
        if (request.url.path.endsWith('/cities')) return jsonResponse([], 200);
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
          createCount++;
          await createGate.future;
          return jsonResponse({'id': 'loc-1'}, 201);
        }
        if (request.url.path.endsWith('/me')) {
          return jsonResponse({'id': 'u1', 'phone': null, 'isPhoneVerified': false}, 200);
        }
        return http.Response('unexpected: ${request.method} ${request.url.path}', 404);
      }),
    );
    final geoClient = MockClient((request) async => nominatimSearchResponse(
          displayName: 'Vĩnh Hải, Nha Trang',
          lat: 12.26,
          lon: 109.2,
          address: {'suburb': 'Vĩnh Hải'},
        ));

    await tester.pumpWidget(buildScreen(api, geoClient: geoClient));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Tên cửa hàng/doanh nghiệp'), 'Quán Test');
    await tester.dragUntilVisible(
      find.widgetWithText(TextField, 'Địa chỉ (vd: 37 Hồng Bàng, Nha Trang)'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.enterText(find.widgetWithText(TextField, 'Địa chỉ (vd: 37 Hồng Bàng, Nha Trang)'), 'Vĩnh Hải');
    await scrollToSearchButton(tester);
    await tester.tap(find.text('TÌM ĐỊA ĐIỂM'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();

    await scrollToSaveButton(tester);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    createGate.complete();
    await tester.pumpAndSettle();

    expect(createCount, 1);
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
    expect(find.text('0900000002'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('12 Trần Phú'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    expect(find.text('12 Trần Phú'), findsOneWidget);

    await tester.dragUntilVisible(
      find.textContaining('Đã xác định vị trí cơ sở.'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    expect(find.textContaining('Đã xác định vị trí cơ sở.'), findsOneWidget);
    // Không lộ số toạ độ ra UI ngay cả với cơ sở đã lưu.
    expect(find.textContaining('12.3'), findsNothing);
    expect(find.textContaining('109.15'), findsNothing);
  });
}
