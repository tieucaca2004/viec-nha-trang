import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:viec_nha_trang/features/employer/data/geocoding_service.dart';

/// Regression cho TINH CHỈNH GEOCODING mục 1/3: GeocodingService phải phân loại đúng
/// [GeocodingErrorKind] cho từng nguyên nhân lỗi thật (timeout/network/httpError/noResult), thay
/// vì 1 thông báo chung chung như trước - test trực tiếp ở tầng service (không qua widget) để
/// nhanh và không phụ thuộc việc chờ timeout thật 10s.
void main() {
  group('searchAddress()', () {
    test('kind=timeout khi request vượt thời gian chờ', () async {
      final service = GeocodingService(client: MockClient((_) async => throw TimeoutException('mock timeout')));
      await expectLater(
        service.searchAddress('37 Hồng Bàng'),
        throwsA(isA<GeocodingException>().having((e) => e.kind, 'kind', GeocodingErrorKind.timeout)),
      );
    });

    test('kind=network khi lỗi kết nối (không phải timeout, không có response)', () async {
      final service = GeocodingService(client: MockClient((_) async => throw const SocketExceptionLike()));
      await expectLater(
        service.searchAddress('37 Hồng Bàng'),
        throwsA(isA<GeocodingException>().having((e) => e.kind, 'kind', GeocodingErrorKind.network)),
      );
    });

    test('kind=httpError khi server trả status khác 200', () async {
      final service = GeocodingService(client: MockClient((_) async => http.Response('server error', 500)));
      await expectLater(
        service.searchAddress('37 Hồng Bàng'),
        throwsA(isA<GeocodingException>().having((e) => e.kind, 'kind', GeocodingErrorKind.httpError)),
      );
    });

    test('kind=noResult khi request thành công nhưng danh sách rỗng', () async {
      final service = GeocodingService(
        client: MockClient((_) async => http.Response('[]', 200, headers: {'content-type': 'application/json; charset=utf-8'})),
      );
      await expectLater(
        service.searchAddress('địa chỉ không tồn tại xyz'),
        throwsA(isA<GeocodingException>().having((e) => e.kind, 'kind', GeocodingErrorKind.noResult)),
      );
    });

    test('thành công: trả đúng danh sách kết quả với latitude/longitude/addressComponents', () async {
      final service = GeocodingService(
        client: MockClient((_) async => http.Response(
              jsonEncode([
                {
                  'display_name': '37 Hồng Bàng, Vĩnh Hải, Nha Trang',
                  'lat': '12.242013',
                  'lon': '109.188444',
                  'address': {'suburb': 'Vĩnh Hải'},
                },
              ]),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            )),
      );
      final results = await service.searchAddress('37 Hồng Bàng');
      expect(results, hasLength(1));
      expect(results.first.latitude, 12.242013);
      expect(results.first.longitude, 109.188444);
      expect(results.first.addressComponents['suburb'], 'Vĩnh Hải');
    });

    test('query rỗng trả về danh sách rỗng ngay, không gọi network', () async {
      var called = false;
      final service = GeocodingService(client: MockClient((_) async {
        called = true;
        return http.Response('[]', 200);
      }));
      final results = await service.searchAddress('   ');
      expect(results, isEmpty);
      expect(called, isFalse);
    });
  });

  group('reverseGeocode()', () {
    test('kind=timeout khi request vượt thời gian chờ', () async {
      final service = GeocodingService(client: MockClient((_) async => throw TimeoutException('mock timeout')));
      await expectLater(
        service.reverseGeocode(12.24, 109.18),
        throwsA(isA<GeocodingException>().having((e) => e.kind, 'kind', GeocodingErrorKind.timeout)),
      );
    });

    test('kind=network khi lỗi kết nối', () async {
      final service = GeocodingService(client: MockClient((_) async => throw const SocketExceptionLike()));
      await expectLater(
        service.reverseGeocode(12.24, 109.18),
        throwsA(isA<GeocodingException>().having((e) => e.kind, 'kind', GeocodingErrorKind.network)),
      );
    });

    test('kind=httpError khi server trả status khác 200', () async {
      final service = GeocodingService(client: MockClient((_) async => http.Response('server error', 503)));
      await expectLater(
        service.reverseGeocode(12.24, 109.18),
        throwsA(isA<GeocodingException>().having((e) => e.kind, 'kind', GeocodingErrorKind.httpError)),
      );
    });

    test('kind=noResult khi Nominatim không xác định được địa chỉ cho toạ độ này', () async {
      final service = GeocodingService(
        client: MockClient((_) async => http.Response(
              jsonEncode({'error': 'Unable to geocode'}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            )),
      );
      await expectLater(
        service.reverseGeocode(0, 0),
        throwsA(isA<GeocodingException>().having((e) => e.kind, 'kind', GeocodingErrorKind.noResult)),
      );
    });

    test('thành công: trả đúng địa chỉ cho toạ độ hợp lệ', () async {
      final service = GeocodingService(
        client: MockClient((_) async => http.Response(
              jsonEncode({
                'display_name': '37 Hồng Bàng, Vĩnh Hải, Nha Trang',
                'lat': '12.242013',
                'lon': '109.188444',
                'address': {'suburb': 'Vĩnh Hải'},
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            )),
      );
      final result = await service.reverseGeocode(12.242013, 109.188444);
      expect(result.displayName, '37 Hồng Bàng, Vĩnh Hải, Nha Trang');
      expect(result.latitude, 12.242013);
      expect(result.longitude, 109.188444);
      expect(result.addressComponents['suburb'], 'Vĩnh Hải');
    });
  });
}

/// http.ClientException thật cần 1 URI cụ thể - dùng 1 Exception giả lập lỗi kết nối đơn giản
/// (không phải TimeoutException, không phải HTTP response) để test đúng nhánh catch chung
/// (kind=network) mà không phụ thuộc chi tiết implementation của dart:io SocketException.
class SocketExceptionLike implements Exception {
  const SocketExceptionLike();
  @override
  String toString() => 'SocketExceptionLike: Connection refused';
}
