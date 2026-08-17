import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Trạng thái đăng nhập toàn cục: access/refresh token + vai trò hiện tại.
/// Một tài khoản có thể vừa là người tìm việc vừa là nhà tuyển dụng (đặc tả mục 5),
/// [activeRole] chỉ quyết định UI đang hiển thị ở chế độ nào.
class Session extends ChangeNotifier {
  String? accessToken;
  String? refreshToken;
  List<String> roles = [];
  String activeRole = 'JOB_SEEKER';

  bool get isLoggedIn => accessToken != null;
  bool get isEmployer => roles.contains('EMPLOYER');
  bool get isJobSeeker => roles.contains('JOB_SEEKER');

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    accessToken = prefs.getString('accessToken');
    refreshToken = prefs.getString('refreshToken');
    roles = prefs.getStringList('roles') ?? ['JOB_SEEKER'];
    activeRole = prefs.getString('activeRole') ?? 'JOB_SEEKER';
    notifyListeners();
  }

  Future<void> setTokens({required String access, required String refresh, List<String>? roles}) async {
    accessToken = access;
    refreshToken = refresh;
    if (roles != null) this.roles = roles;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('accessToken', access);
    await prefs.setString('refreshToken', refresh);
    if (roles != null) await prefs.setStringList('roles', roles);
    notifyListeners();
  }

  Future<void> setActiveRole(String role) async {
    activeRole = role;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('activeRole', role);
    notifyListeners();
  }

  Future<void> logout() async {
    accessToken = null;
    refreshToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('accessToken');
    await prefs.remove('refreshToken');
    notifyListeners();
  }
}
