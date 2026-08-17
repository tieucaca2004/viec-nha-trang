import '../../../core/network/api_client.dart';

/// Đăng tin & quản lý tin / ứng viên cho nhà tuyển dụng (đặc tả §19/§20/§21 Phase 3).
class EmployerJobsService {
  final ApiClient api;
  EmployerJobsService(this.api);

  Future<List<dynamic>> myJobs() async => await api.get('/jobs/mine') as List;

  Future<Map<String, dynamic>> createJob(Map<String, dynamic> data) async =>
      await api.post('/jobs', body: data) as Map<String, dynamic>;

  Future<void> closeJob(String id) async => await api.post('/jobs/$id/close');

  Future<void> renewJob(String id) async => await api.post('/jobs/$id/renew');

  Future<void> boostJob(String id) async => await api.post('/jobs/$id/boost');

  Future<List<dynamic>> applicantsForJob(String jobId) async =>
      await api.get('/employer/jobs/$jobId/applications') as List;

  Future<void> updateApplicationStatus(String applicationId, String status, {String? note}) async {
    await api.patch('/applications/$applicationId/status', body: {'status': status, 'employerNote': note});
  }
}
