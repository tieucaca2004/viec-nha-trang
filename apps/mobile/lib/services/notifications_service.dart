import '../core/api_client.dart';

class NotificationsService {
  final ApiClient api;
  NotificationsService(this.api);

  Future<List<dynamic>> list() async {
    return await api.get('/notifications') as List;
  }

  Future<void> markRead(String id) async {
    await api.patch('/notifications/$id/read');
  }
}
