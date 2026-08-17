import '../../../core/network/api_client.dart';
import '../../../shared/models/application.dart';

/// Ứng tuyển & theo dõi trạng thái - đặc tả §12/§13. Backend tự chống apply trùng
/// (unique constraint DB, xem docs/DATABASE.md) - gọi lại `apply` trên job đã ứng tuyển trả về
/// đúng application đã có thay vì lỗi, nên UI có thể coi đây là thao tác idempotent.
class ApplicationsService {
  final ApiClient api;
  ApplicationsService(this.api);

  /// Ứng tuyển 1 chạm - chỉ cần jobId, hồ sơ đã có sẵn từ trước. Trả về application vừa
  /// tạo/đã có để UI cập nhật trạng thái "ĐÃ ỨNG TUYỂN" ngay lập tức.
  Future<JobApplication> apply(String jobId) async {
    final res = await api.post('/jobs/$jobId/apply');
    return JobApplication.fromJson(res as Map<String, dynamic>);
  }

  Future<List<JobApplication>> listMine() async {
    final res = await api.get('/applications/me') as List;
    return res.map((e) => JobApplication.fromJson(e)).toList();
  }
}
