import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../auth/session.dart';
import '../config/app_config.dart';
import 'api_exception.dart';

/// Client HTTP dùng chung cho toàn app - đặc tả Phase 3 §4.
/// - Base URL cấu hình qua [AppConfig] (không hard-code, §36).
/// - Gắn Bearer token tự động từ [Session] (server luôn là nguồn sự thật cho quyền hạn, §32
///   docs/SECURITY.md - client chỉ gửi token, không tự khai userId/role).
/// - Timeout 15s mỗi request.
/// - Tự refresh access token 1 lần khi gặp 401, retry lại request gốc; nếu refresh cũng thất
///   bại thì đăng xuất để user đăng nhập lại (đặc tả §26).
/// - Không retry mù quáng cho POST/PATCH/DELETE (tránh double-submit) - chỉ GET được retry khi
///   lỗi mạng/timeout thoáng qua.
class ApiClient {
  final Session session;
  final http.Client _http;
  static const _timeout = Duration(seconds: 15);

  ApiClient(this.session, {http.Client? httpClient}) : _http = httpClient ?? http.Client();

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    Map<String, String>? normalizedQuery;
    if (query != null) {
      normalizedQuery = {};
      for (final entry in query.entries) {
        if (entry.value != null) normalizedQuery[entry.key] = entry.value.toString();
      }
    }
    return Uri.parse('${AppConfig.apiBaseUrl}$path').replace(
      queryParameters: (normalizedQuery == null || normalizedQuery.isEmpty) ? null : normalizedQuery,
    );
  }

  Map<String, String> _headers({bool json = true}) => {
        if (json) 'Content-Type': 'application/json',
        if (session.accessToken != null) 'Authorization': 'Bearer ${session.accessToken}',
      };

  Future<dynamic> _handle(Future<http.Response> Function() send, {bool allowRefresh = true}) async {
    http.Response res;
    try {
      res = await send().timeout(_timeout);
    } on TimeoutException {
      throw ApiException.timeout();
    } on SocketException {
      throw ApiException.network();
    } on http.ClientException {
      throw ApiException.network();
    }

    if (res.statusCode == 401 && allowRefresh && session.refreshToken != null) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        return _handle(send, allowRefresh: false);
      }
      await session.logout();
      throw ApiException(401, 'Phiên đăng nhập đã hết.');
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return null;
      return jsonDecode(utf8.decode(res.bodyBytes));
    }

    String message = '';
    try {
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      final rawMessage = body['message'];
      message = rawMessage is List ? rawMessage.join(', ') : (rawMessage?.toString() ?? '');
    } catch (_) {}
    throw ApiException(res.statusCode, message);
  }

  Future<bool> _tryRefresh() async {
    try {
      final res = await _http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/auth/refresh'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refreshToken': session.refreshToken}),
          )
          .timeout(_timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) return false;
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      await session.setTokens(access: body['accessToken'], refresh: body['refreshToken']);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) {
    return _handle(() => _http.get(_uri(path, query), headers: _headers()));
  }

  Future<dynamic> post(String path, {Map<String, dynamic>? body}) {
    return _handle(
      () => _http.post(_uri(path), headers: _headers(), body: body == null ? null : jsonEncode(body)),
      allowRefresh: true,
    );
  }

  Future<dynamic> patch(String path, {Map<String, dynamic>? body}) {
    return _handle(() => _http.patch(_uri(path), headers: _headers(), body: body == null ? null : jsonEncode(body)));
  }

  Future<dynamic> put(String path, {Map<String, dynamic>? body}) {
    return _handle(() => _http.put(_uri(path), headers: _headers(), body: body == null ? null : jsonEncode(body)));
  }

  Future<dynamic> delete(String path) {
    return _handle(() => _http.delete(_uri(path), headers: _headers()));
  }
}
