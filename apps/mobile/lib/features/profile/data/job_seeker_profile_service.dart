import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';

/// Hồ sơ người tìm việc (đặc tả §16 Phase 3, §11/§12 gốc).
class JobSeekerProfileService {
  final ApiClient api;
  JobSeekerProfileService(this.api);

  /// Trả null khi chưa tạo hồ sơ (404 - trạng thái hợp lệ, không phải lỗi). Các lỗi khác
  /// (mạng, 401, 500...) được ném lại để UI hiển thị đúng trạng thái lỗi (đặc tả §25/§26).
  Future<Map<String, dynamic>?> getJobSeekerProfile() async {
    try {
      return await api.get('/me/job-seeker-profile') as Map<String, dynamic>;
    } on ApiException catch (e) {
      if (e.isNotFound) return null;
      rethrow;
    }
  }

  Future<void> saveJobSeekerProfile(Map<String, dynamic> data) async {
    await api.put('/me/job-seeker-profile', body: data);
  }

  /// Hồ sơ tối thiểu để ứng tuyển 1 chạm (đặc tả §12): có tên là đủ, các trường còn lại optional.
  bool isCompleteEnoughToApply(Map<String, dynamic>? profile) {
    return profile != null && (profile['fullName'] as String?)?.trim().isNotEmpty == true;
  }
}
