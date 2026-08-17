import 'dart:convert';
import 'package:http/http.dart' as http;

/// http.Response mặc định encode body bằng Latin1 nếu không khai rõ charset, làm hỏng
/// chuỗi UTF-8 tiếng Việt trong test. Helper này luôn set charset=utf-8.
http.Response jsonResponse(Object? body, int statusCode) {
  return http.Response(
    body == null ? '' : jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}
