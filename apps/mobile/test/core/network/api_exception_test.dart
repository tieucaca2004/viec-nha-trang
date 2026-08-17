import 'package:flutter_test/flutter_test.dart';
import 'package:viec_nha_trang/core/network/api_exception.dart';

void main() {
  group('ApiException', () {
    test('maps network failure to a Vietnamese, non-technical message (đặc tả §26)', () {
      final e = ApiException.network();
      expect(e.isNetwork, isTrue);
      expect(e.userMessage, 'Không thể kết nối. Kiểm tra Internet và thử lại.');
    });

    test('maps timeout distinctly from network failure', () {
      final e = ApiException.timeout();
      expect(e.isTimeout, isTrue);
      expect(e.userMessage, contains('quá chậm'));
    });

    test('401 -> phiên đăng nhập hết hạn, not a raw technical message', () {
      final e = ApiException(401, 'Unauthorized');
      expect(e.isUnauthorized, isTrue);
      expect(e.userMessage, 'Phiên đăng nhập đã hết. Vui lòng đăng nhập lại.');
    });

    test('403 -> permission denied message', () {
      final e = ApiException(403, 'Forbidden');
      expect(e.isForbidden, isTrue);
      expect(e.userMessage, contains('không có quyền'));
    });

    test('429 -> rate limit message, not raw "Too Many Requests"', () {
      final e = ApiException(429, 'ThrottlerException: Too Many Requests');
      expect(e.isRateLimited, isTrue);
      expect(e.userMessage, isNot(contains('ThrottlerException')));
    });

    test('400 with backend validation message surfaces that message to the user', () {
      final e = ApiException(400, 'Vui lòng nhập số điện thoại hợp lệ.');
      expect(e.isValidation, isTrue);
      expect(e.userMessage, 'Vui lòng nhập số điện thoại hợp lệ.');
    });

    test('500 -> generic "hệ thống đang bận" message, never a stack trace', () {
      final e = ApiException(500, 'Internal Server Error\n  at foo.js:12');
      expect(e.isServerError, isTrue);
      expect(e.userMessage, isNot(contains('.js')));
    });
  });
}
