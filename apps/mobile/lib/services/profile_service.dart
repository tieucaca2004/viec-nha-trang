import '../core/api_client.dart';

class ProfileService {
  final ApiClient api;
  ProfileService(this.api);

  Future<Map<String, dynamic>?> getJobSeekerProfile() async {
    try {
      return await api.get('/me/job-seeker-profile') as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveJobSeekerProfile(Map<String, dynamic> data) async {
    await api.put('/me/job-seeker-profile', body: data);
  }

  Future<Map<String, dynamic>?> getEmployerProfile() async {
    try {
      return await api.get('/me/employer-profile') as Map<String, dynamic>;
    } catch (_) {
      return null;
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
