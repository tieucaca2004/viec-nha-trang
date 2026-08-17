import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';

/// Hồ sơ doanh nghiệp/cơ sở nhà tuyển dụng (đặc tả §18 Phase 3, §13 gốc).
class EmployerProfileService {
  final ApiClient api;
  EmployerProfileService(this.api);

  Future<Map<String, dynamic>?> getEmployerProfile() async {
    try {
      return await api.get('/me/employer-profile') as Map<String, dynamic>;
    } on ApiException catch (e) {
      if (e.isNotFound) return null;
      rethrow;
    }
  }

  Future<void> saveEmployerProfile(Map<String, dynamic> data) async {
    await api.put('/me/employer-profile', body: data);
  }

  Future<List<dynamic>> myEmployerLocations() async {
    return await api.get('/me/employer-profile/locations') as List;
  }

  Future<Map<String, dynamic>> addEmployerLocation(Map<String, dynamic> data) async {
    return await api.post('/me/employer-profile/locations', body: data) as Map<String, dynamic>;
  }
}
