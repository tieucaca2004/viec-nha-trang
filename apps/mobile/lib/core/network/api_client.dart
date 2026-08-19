import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
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

  // Hotfix §10: log latency/status mỗi request ở debug build để tìm đúng request chậm/lỗi thay vì
  // đoán - KHÔNG log ở release build (kDebugMode=false khi build APK release), KHÔNG log
  // Authorization header/token/body (chỉ log method+path+thời gian+status, đúng yêu cầu không lộ
  // secret). method/path chỉ dùng để log, không ảnh hưởng logic gọi request.
  Future<dynamic> _handle(
    Future<http.Response> Function() send, {
    bool allowRefresh = true,
    String method = '?',
    String path = '?',
  }) async {
    final stopwatch = kDebugMode ? (Stopwatch()..start()) : null;
    http.Response res;
    try {
      res = await send().timeout(_timeout);
    } on TimeoutException {
      _logApi(method, path, stopwatch, null, 'TIMEOUT');
      throw ApiException.timeout();
    } on SocketException {
      _logApi(method, path, stopwatch, null, 'SOCKET_ERROR');
      throw ApiException.network();
    } on http.ClientException {
      _logApi(method, path, stopwatch, null, 'CLIENT_ERROR');
      throw ApiException.network();
    }
    _logApi(method, path, stopwatch, res.statusCode, null);

    if (res.statusCode == 401 && allowRefresh && session.refreshToken != null) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        return _handle(send, allowRefresh: false, method: method, path: path);
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

  void _logApi(String method, String path, Stopwatch? stopwatch, int? statusCode, String? errorKind) {
    if (stopwatch == null) return; // release build (kDebugMode=false) - không log gì.
    stopwatch.stop();
    final status = errorKind ?? statusCode?.toString() ?? '?';
    debugPrint('[API] $method $path ${stopwatch.elapsedMilliseconds}ms $status');
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
    return _handle(() => _http.get(_uri(path, query), headers: _headers()), method: 'GET', path: path);
  }

  Future<dynamic> post(String path, {Map<String, dynamic>? body}) {
    return _handle(
      () => _http.post(_uri(path), headers: _headers(), body: body == null ? null : jsonEncode(body)),
      allowRefresh: true,
      method: 'POST',
      path: path,
    );
  }

  Future<dynamic> patch(String path, {Map<String, dynamic>? body}) {
    return _handle(
      () => _http.patch(_uri(path), headers: _headers(), body: body == null ? null : jsonEncode(body)),
      method: 'PATCH',
      path: path,
    );
  }

  Future<dynamic> put(String path, {Map<String, dynamic>? body}) {
    return _handle(
      () => _http.put(_uri(path), headers: _headers(), body: body == null ? null : jsonEncode(body)),
      method: 'PUT',
      path: path,
    );
  }

  Future<dynamic> delete(String path) {
    return _handle(() => _http.delete(_uri(path), headers: _headers()), method: 'DELETE', path: path);
  }
}
