import '../../../core/network/api_client.dart';

/// Lưu việc (đặc tả §14). Backend chống lưu trùng bằng unique constraint DB.
class SavedJobsService {
  final ApiClient api;
  SavedJobsService(this.api);

  Future<void> save(String jobId) async {
    await api.post('/saved-jobs/$jobId');
  }

  Future<void> unsave(String jobId) async {
    await api.delete('/saved-jobs/$jobId');
  }

  Future<List<dynamic>> listSaved() async {
    return await api.get('/saved-jobs') as List;
  }
}
