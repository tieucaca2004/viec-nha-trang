import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
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

    test('logout calls POST /auth/logout with the refresh token THEN clears session tokens (đặc tả sửa lỗi High #7)', () async {
      final session = Session(storage: InMemoryTokenStorage());
      String? calledPath;
      Map<String, dynamic>? sentBody;
      final api = ApiClient(
        session,
        httpClient: MockClient((request) async {
          calledPath = request.url.path;
          sentBody = jsonDecode(request.body);
          return jsonResponse({'success': true}, 201);
        }),
      );
      await session.setTokens(access: 'a', refresh: 'b');

      await AuthService(api, session).logout();

      expect(calledPath, endsWith('/auth/logout'));
      expect(sentBody!['refreshToken'], 'b');
      expect(session.isLoggedIn, isFalse);
      expect(session.refreshToken, isNull);
    });

    test('logout still clears session tokens locally even if the API call fails (best-effort, no network block)', () async {
      final session = Session(storage: InMemoryTokenStorage());
      final api = ApiClient(
        session,
        httpClient: MockClient((request) async => http.Response('offline', 500)),
      );
      await session.setTokens(access: 'a', refresh: 'b');

      await AuthService(api, session).logout();

      expect(session.isLoggedIn, isFalse);
    });
  });

  group('AuthService - đăng ký bằng email (đặc tả §1 phase kế tiếp)', () {
    test('requestEmailVerification -> verifyEmailAndRegister stores tokens and roles in Session', () async {
      final session = Session(storage: InMemoryTokenStorage());
      final api = ApiClient(
        session,
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/auth/register/email/request')) {
            return jsonResponse({'expiresInSeconds': 600}, 201);
          }
          if (request.url.path.endsWith('/auth/register/email/verify')) {
            return jsonResponse({'accessToken': 'access-email-1', 'refreshToken': 'refresh-email-1'}, 201);
          }
          if (request.url.path.endsWith('/me')) {
            return jsonResponse({
              'id': 'u2',
              'email': 'a@example.com',
              'isEmailVerified': true,
              'roles': ['JOB_SEEKER'],
            }, 200);
          }
          throw Exception('unexpected request ${request.url}');
        }),
      );
      final auth = AuthService(api, session);

      final seconds = await auth.requestEmailVerification('a@example.com');
      expect(seconds, 600);

      await auth.verifyEmailAndRegister('a@example.com', '123456');
      expect(session.isLoggedIn, isTrue);
      expect(session.accessToken, 'access-email-1');
      expect(session.roles, ['JOB_SEEKER']);
    });
  });

  group('AuthService - xác minh số điện thoại cho tài khoản đã đăng nhập (đặc tả §3)', () {
    test('requestPhoneLink -> verifyPhoneLink calls the right endpoints and refreshes /me', () async {
      final session = Session(storage: InMemoryTokenStorage());
      await session.setTokens(access: 'a', refresh: 'b', roles: ['JOB_SEEKER']);

      final calledPaths = <String>[];
      final api = ApiClient(
        session,
        httpClient: MockClient((request) async {
          calledPaths.add(request.url.path);
          if (request.url.path.endsWith('/auth/phone/link/request')) {
            return jsonResponse({'expiresInSeconds': 300}, 201);
          }
          if (request.url.path.endsWith('/auth/phone/link/verify')) {
            return jsonResponse({'phone': '0930000001', 'isPhoneVerified': true}, 201);
          }
          if (request.url.path.endsWith('/me')) {
            return jsonResponse({
              'id': 'u3',
              'phone': '0930000001',
              'isPhoneVerified': true,
              'roles': ['JOB_SEEKER'],
            }, 200);
          }
          throw Exception('unexpected request ${request.url}');
        }),
      );
      final auth = AuthService(api, session);

      final seconds = await auth.requestPhoneLink('0930000001');
      expect(seconds, 300);

      await auth.verifyPhoneLink('0930000001', '123456');
      expect(calledPaths.any((p) => p.endsWith('/auth/phone/link/verify')), isTrue);
      expect(calledPaths.any((p) => p.endsWith('/me')), isTrue);
    });

    test('getMe trả về đầy đủ phone/isPhoneVerified/email/isEmailVerified thật từ backend', () async {
      final session = Session(storage: InMemoryTokenStorage());
      await session.setTokens(access: 'a', refresh: 'b');
      final api = ApiClient(
        session,
        httpClient: MockClient((request) async => jsonResponse({
              'id': 'u4',
              'phone': '0930000002',
              'isPhoneVerified': false,
              'email': 'b@example.com',
              'isEmailVerified': true,
            }, 200)),
      );

      final me = await AuthService(api, session).getMe();
      expect(me['phone'], '0930000002');
      expect(me['isPhoneVerified'], isFalse);
      expect(me['isEmailVerified'], isTrue);
    });
  });
}
