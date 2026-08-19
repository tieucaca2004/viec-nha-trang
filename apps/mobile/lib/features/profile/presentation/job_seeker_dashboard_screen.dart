import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/models/application.dart';
import '../../../shared/widgets/async_state_view.dart';
import '../../applications/data/applications_service.dart';
import '../../saved_jobs/data/saved_jobs_service.dart';
import '../data/job_seeker_profile_service.dart';

/// Dashboard người tìm việc (đặc tả §4 - trước đây KHÔNG tồn tại màn này). Chỉ dùng dữ liệu
/// thật từ API sẵn có - không tạo số liệu giả:
/// - % hoàn thiện hồ sơ: tính phía client từ các trường đã có trong GET /me/job-seeker-profile.
/// - Việc đã lưu: SavedJobsService.listSaved().
/// - Việc đã ứng tuyển + trạng thái: ApplicationsService.listMine().
/// KHÔNG có mục "việc phù hợp/gợi ý" - backend chưa có endpoint gợi ý việc làm cho job seeker,
/// nên không tự chế bằng heuristic phía client (đây là backend gap, xem docs/MOBILE.md).
class JobSeekerDashboardScreen extends StatefulWidget {
  const JobSeekerDashboardScreen({super.key});

  @override
  State<JobSeekerDashboardScreen> createState() => _JobSeekerDashboardScreenState();
}

class _DashboardData {
  final Map<String, dynamic>? profile;
  final List<dynamic> savedJobs;
  final List<JobApplication> applications;
  _DashboardData({required this.profile, required this.savedJobs, required this.applications});
}

class _JobSeekerDashboardScreenState extends State<JobSeekerDashboardScreen> {
  _DashboardData? _data;
  ApiException? _error;
  bool _loading = true;

  static const _profileFields = [
    'fullName',
    'desiredCategoryId',
    'areaId',
    'experienceLevel',
    'desiredSalaryMin',
    'desiredSalaryMax',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final profileService = context.read<JobSeekerProfileService>();
    final savedJobsService = context.read<SavedJobsService>();
    final applicationsService = context.read<ApplicationsService>();
    try {
      final profile = await profileService.getJobSeekerProfile();
      final savedJobs = await savedJobsService.listSaved();
      final applications = await applicationsService.listMine();
      if (!mounted) return;
      setState(() => _data = _DashboardData(profile: profile, savedJobs: savedJobs, applications: applications));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _profileCompletionPercent(Map<String, dynamic>? profile) {
    if (profile == null) return 0;
    final filled = _profileFields.where((f) {
      final v = profile[f];
      if (v == null) return false;
      if (v is String) return v.trim().isNotEmpty;
      return true;
    }).length;
    return ((filled / _profileFields.length) * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Thống kê của bạn')),
      body: AsyncStateView<_DashboardData?>(
        loading: _loading,
        error: _error,
        data: _loading ? null : _data,
        onRetry: _load,
        builder: (context, data) {
          final percent = _profileCompletionPercent(data!.profile);
          final byStatus = <String, int>{};
          for (final app in data.applications) {
            byStatus[app.status] = (byStatus[app.status] ?? 0) + 1;
          }

          return RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Hoàn thiện hồ sơ', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(value: percent / 100),
                        const SizedBox(height: 8),
                        Text('$percent%'),
                        if (data.profile == null) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Bạn chưa tạo hồ sơ tìm việc. Tạo hồ sơ để nhà tuyển dụng dễ tìm thấy bạn hơn.',
                            style: TextStyle(color: Colors.black54, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.6,
                  children: [
                    _statCard('Việc đã lưu', data.savedJobs.length.toString(), Icons.favorite_border),
                    _statCard('Đã ứng tuyển', data.applications.length.toString(), Icons.send_outlined),
                  ],
                ),
                if (byStatus.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Trạng thái ứng tuyển', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          for (final entry in byStatus.entries)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(JobApplication.statusLabels[entry.key] ?? entry.key),
                                  Text(entry.value.toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFF0F9D58)),
            const Spacer(),
            Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            Text(label, style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}
