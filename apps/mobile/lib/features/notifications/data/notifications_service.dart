import '../../../core/network/api_client.dart';

/// Thông báo (đặc tả §15/§6 Phase 3). Push thật qua FCM - backend đã có tích hợp
/// (docs/PLAN.md §9), mobile đăng ký device token qua [registerPushToken].
class NotificationsService {
  final ApiClient api;
  NotificationsService(this.api);

  Future<List<dynamic>> list() async {
    return await api.get('/notifications') as List;
  }

  Future<void> markRead(String id) async {
    await api.patch('/notifications/$id/read');
  }

  Future<void> registerPushToken(String token) async {
    await api.patch('/me/push-token', body: {'pushToken': token});
  }
}
