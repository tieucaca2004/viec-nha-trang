import '../core/api_client.dart';
import '../models/application.dart';

class ApplicationsService {
  final ApiClient api;
  ApplicationsService(this.api);

  /// Ứng tuyển 1 chạm (đặc tả mục 11) - chỉ cần jobId, hồ sơ đã có sẵn từ trước.
  Future<void> apply(String jobId) async {
    await api.post('/jobs/$jobId/apply');
  }

  Future<List<JobApplication>> listMine() async {
    final res = await api.get('/applications/me') as List;
    return res.map((e) => JobApplication.fromJson(e)).toList();
  }

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
