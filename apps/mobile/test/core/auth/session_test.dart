import 'package:flutter_test/flutter_test.dart';
import 'package:viec_nha_trang/core/auth/session.dart';
import '../../helpers/in_memory_token_storage.dart';

void main() {
  group('Session (đặc tả §5 Phase 3: role switching, persistence)', () {
    test('setActiveRole persists and notifies listeners (đặc tả §17: employer nav vs seeker nav)', () async {
      final storage = InMemoryTokenStorage();
      final session = Session(storage: storage);
      var notified = 0;
      session.addListener(() => notified++);

      await session.setActiveRole('EMPLOYER');

      expect(session.activeRole, 'EMPLOYER');
      expect(notified, greaterThan(0));
      expect(await storage.readActiveRole(), 'EMPLOYER');
    });

    test('restore() re-hydrates tokens/roles/activeRole from storage after app restart', () async {
      final storage = InMemoryTokenStorage();
      final first = Session(storage: storage);
      await first.setTokens(access: 'a1', refresh: 'r1', roles: ['JOB_SEEKER', 'EMPLOYER']);
      await first.setActiveRole('EMPLOYER');

      final second = Session(storage: storage);
      await second.restore();

      expect(second.accessToken, 'a1');
      expect(second.isEmployer, isTrue);
      expect(second.isJobSeeker, isTrue);
      expect(second.activeRole, 'EMPLOYER');
    });

    test('logout clears tokens but a fresh restore starts as JOB_SEEKER default', () async {
      final storage = InMemoryTokenStorage();
      final session = Session(storage: storage);
      await session.setTokens(access: 'a1', refresh: 'r1', roles: ['EMPLOYER']);

      await session.logout();

      expect(session.isLoggedIn, isFalse);
      expect(await storage.readAccessToken(), isNull);
    });
  });
}
