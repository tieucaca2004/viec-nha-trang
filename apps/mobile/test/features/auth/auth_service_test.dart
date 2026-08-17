import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:viec_nha_trang/core/auth/session.dart';
import 'package:viec_nha_trang/core/network/api_client.dart';
import 'package:viec_nha_trang/features/auth/data/auth_service.dart';
import '../../helpers/in_memory_token_storage.dart';
import '../../helpers/json_response.dart';

void main() {
  group('AuthService (đặc tả §5 Phase 3: OTP login, session, role switching)', () {
    test('requestOtp -> verifyOtp stores tokens and roles in Session', () async {
      final session = Session(storage: InMemoryTokenStorage());
      final api = ApiClient(
        session,
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/auth/otp/request')) {
            return jsonResponse({'expiresInSeconds': 300}, 201);
          }
          if (request.url.path.endsWith('/auth/otp/verify')) {
            return jsonResponse({'accessToken': 'access-1', 'refreshToken': 'refresh-1'}, 201);
          }
          if (request.url.path.endsWith('/me')) {
            return jsonResponse({
              'id': 'u1',
              'phone': '0900000003',
              'roles': ['JOB_SEEKER'],
            }, 200);
          }
          throw Exception('unexpected request ${request.url}');
        }),
      );
      final auth = AuthService(api, session);

      final seconds = await auth.requestOtp('0900000003');
      expect(seconds, 300);

      await auth.verifyOtp('0900000003', '123456');
      expect(session.isLoggedIn, isTrue);
      expect(session.accessToken, 'access-1');
      expect(session.roles, ['JOB_SEEKER']);
    });

    test('becomeEmployer adds EMPLOYER role without creating a new account (đặc tả §5 gốc)', () async {
      final session = Session(storage: InMemoryTokenStorage());
      await session.setTokens(access: 'access-1', refresh: 'refresh-1', roles: ['JOB_SEEKER']);

      var patchedRole = '';
      final api = ApiClient(
        session,
        httpClient: MockClient((request) async {
          if (request.method == 'PATCH' && request.url.path.endsWith('/me/roles')) {
            patchedRole = (jsonDecode(request.body) as Map)['role'];
            return jsonResponse(null, 200);
          }
          if (request.url.path.endsWith('/me')) {
            return jsonResponse({
              'id': 'u1',
              'phone': '0900000002',
              'roles': ['JOB_SEEKER', 'EMPLOYER'],
            }, 200);
          }
          throw Exception('unexpected request ${request.method} ${request.url}');
        }),
      );

      await AuthService(api, session).becomeEmployer();

      expect(patchedRole, 'EMPLOYER');
      expect(session.isEmployer, isTrue);
      expect(session.isJobSeeker, isTrue); // vẫn giữ vai trò cũ - 1 tài khoản nhiều vai trò
    });

    test('logout clears session tokens', () async {
      final session = Session(storage: InMemoryTokenStorage());
      final api = ApiClient(session);
      await session.setTokens(access: 'a', refresh: 'b');

      await AuthService(api, session).logout();

      expect(session.isLoggedIn, isFalse);
    });
  });
}
