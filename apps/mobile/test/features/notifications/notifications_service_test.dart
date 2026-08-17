import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:viec_nha_trang/core/auth/session.dart';
import 'package:viec_nha_trang/core/network/api_client.dart';
import 'package:viec_nha_trang/features/notifications/data/notifications_service.dart';
import '../../helpers/in_memory_token_storage.dart';
import '../../helpers/json_response.dart';

void main() {
  group('NotificationsService (đặc tả §15 Phase 3)', () {
    test('list() parses notifications with read state', () async {
      final session = Session(storage: InMemoryTokenStorage());
      final api = ApiClient(
        session,
        httpClient: MockClient((request) async {
          return jsonResponse([
            {'id': 'n1', 'title': 'Có việc mới phù hợp', 'body': 'Xem ngay', 'readAt': null},
          ], 200);
        }),
      );

      final items = await NotificationsService(api).list();
      expect(items, hasLength(1));
      expect(items.first['readAt'], isNull);
    });

    test('markRead() PATCHes the notification', () async {
      final session = Session(storage: InMemoryTokenStorage());
      String? path;
      final api = ApiClient(
        session,
        httpClient: MockClient((request) async {
          path = request.url.path;
          return jsonResponse(null, 200);
        }),
      );

      await NotificationsService(api).markRead('n1');
      expect(path, endsWith('/notifications/n1/read'));
    });

    test('registerPushToken() sends device token to backend (đặc tả §6/§15)', () async {
      final session = Session(storage: InMemoryTokenStorage());
      Map<String, dynamic>? sentBody;
      String? path;
      final api = ApiClient(
        session,
        httpClient: MockClient((request) async {
          path = request.url.path;
          sentBody = jsonDecode(request.body);
          return jsonResponse(null, 200);
        }),
      );

      await NotificationsService(api).registerPushToken('device-token-abc');
      expect(path, endsWith('/me/push-token'));
      expect(sentBody!['pushToken'], 'device-token-abc');
    });
  });
}
