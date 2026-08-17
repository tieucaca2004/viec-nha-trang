import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'session.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}

/// Client HTTP dùng chung cho toàn app. Server luôn là nguồn sự thật cho quyền hạn
/// (đặc tả mục 32) - client chỉ gửi Bearer token, không tự khai userId/role.
class ApiClient {
  final Session session;
  ApiClient(this.session);

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final normalizedQuery = query?.map((k, v) => MapEntry(k, v?.toString()))
      ..removeWhere((k, v) => v == null);
    return Uri.parse('${AppConfig.apiBaseUrl}$path').replace(
      queryParameters: normalizedQuery?.isEmpty == true ? null : normalizedQuery,
    );
  }

  Map<String, String> _headers({bool json = true}) => {
        if (json) 'Content-Type': 'application/json',
        if (session.accessToken != null) 'Authorization': 'Bearer ${session.accessToken}',
      };

  dynamic _handle(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return null;
      return jsonDecode(utf8.decode(res.bodyBytes));
    }
    String message = 'Đã có lỗi xảy ra.';
    try {
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      message = body['message']?.toString() ?? message;
    } catch (_) {}
    throw ApiException(res.statusCode, message);
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    final res = await http.get(_uri(path, query), headers: _headers());
    return _handle(res);
  }

  Future<dynamic> post(String path, {Map<String, dynamic>? body}) async {
    final res = await http.post(_uri(path), headers: _headers(), body: body == null ? null : jsonEncode(body));
    return _handle(res);
  }

  Future<dynamic> patch(String path, {Map<String, dynamic>? body}) async {
    final res = await http.patch(_uri(path), headers: _headers(), body: body == null ? null : jsonEncode(body));
    return _handle(res);
  }

  Future<dynamic> put(String path, {Map<String, dynamic>? body}) async {
    final res = await http.put(_uri(path), headers: _headers(), body: body == null ? null : jsonEncode(body));
    return _handle(res);
  }

  Future<dynamic> delete(String path) async {
    final res = await http.delete(_uri(path), headers: _headers());
    return _handle(res);
  }
}
