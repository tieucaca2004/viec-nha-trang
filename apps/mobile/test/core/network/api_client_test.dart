import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:viec_nha_trang/core/auth/session.dart';
import 'package:viec_nha_trang/core/network/api_client.dart';
import 'package:viec_nha_trang/core/network/api_exception.dart';
import '../../helpers/in_memory_token_storage.dart';
import '../../helpers/json_response.dart';

void main() {
  group('ApiClient', () {
    late Session session;

    setUp(() async {
      session = Session(storage: InMemoryTokenStorage());
      await session.setTokens(access: 'old-access', refresh: 'valid-refresh');
    });

    test('attaches Bearer token and returns decoded JSON on success', () async {
      final client = ApiClient(
        session,
        httpClient: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer old-access');
          return jsonResponse({'ok': true}, 200);
        }),
      );

      final result = await client.get('/me');
      expect(result['ok'], true);
    });

    test('auto-refreshes on 401 and retries the original request once (đặc tả §4)', () async {
      var callCount = 0;
      final client = ApiClient(
        session,
        httpClient: MockClient((request) async {
          callCount++;
          if (request.url.path.endsWith('/auth/refresh')) {
            return jsonResponse({'accessToken': 'new-access', 'refreshToken': 'new-refresh'}, 200);
          }
          if (request.headers['Authorization'] == 'Bearer old-access') {
            return jsonResponse({'message': 'Unauthorized'}, 401);
          }
          expect(request.headers['Authorization'], 'Bearer new-access');
          return jsonResponse({'data': []}, 200);
        }),
      );

      final result = await client.get('/jobs');
      expect(result['data'], isEmpty);
      expect(session.accessToken, 'new-access');
      expect(callCount, 3); // request gốc (401) -> refresh -> retry
    });

    test('logs out when refresh token is also invalid, surfacing a friendly 401 message', () async {
      final client = ApiClient(
        session,
        httpClient: MockClient((request) async {
          return jsonResponse({'message': 'Unauthorized'}, 401);
        }),
      );

      await expectLater(client.get('/me'), throwsA(isA<ApiException>()));
      expect(session.isLoggedIn, isFalse);
    });

    test('maps a connection failure to ApiException.network (đặc tả §26)', () async {
      final client = ApiClient(
        session,
        httpClient: MockClient((request) async {
          throw http.ClientException('Connection refused');
        }),
      );

      try {
        await client.get('/jobs');
        fail('should have thrown');
      } on ApiException catch (e) {
        expect(e.isNetwork, isTrue);
      }
    });

    test('drops null query params instead of sending literal "null" (đặc tả §9 pagination/query)', () async {
      final client = ApiClient(
        session,
        httpClient: MockClient((request) async {
          expect(request.url.queryParameters.containsKey('categoryId'), isFalse);
          expect(request.url.queryParameters['keyword'], 'phục vụ');
          return jsonResponse({'data': []}, 200);
        }),
      );

      await client.get('/jobs', query: {'keyword': 'phục vụ', 'categoryId': null});
    });
  });
}
