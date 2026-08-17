import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/async_state_view.dart';
import '../data/employer_jobs_service.dart';
import '../data/employer_profile_service.dart';
import 'employer_applicants_screen.dart';
import 'employer_business_setup_screen.dart';
import 'post_job_wizard_screen.dart';

/// Khu vực quản lý dành cho nhà tuyển dụng (đặc tả §20 Phase 3).
/// Ghi chú API gap: backend chưa có action "Pause"/"Edit rút gọn" riêng cho employer (chỉ có
/// close/renew/boost + PATCH thay toàn bộ field) - xem docs/MOBILE.md mục API gaps.
class EmployerHomeScreen extends StatefulWidget {
  const EmployerHomeScreen({super.key});

  @override
  State<EmployerHomeScreen> createState() => _EmployerHomeScreenState();
}

class _EmployerHomeScreenState extends State<EmployerHomeScreen> {
  List<dynamic> _jobs = [];
  ApiException? _error;
  bool _loading = true;
  bool _hasBusinessProfile = false;

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
    final profileService = context.read<EmployerProfileService>();
    final jobsService = context.read<EmployerJobsService>();
    try {
      final profile = await profileService.getEmployerProfile();
      final jobs = profile == null ? <dynamic>[] : await jobsService.myJobs();
      if (!mounted) return;
      setState(() {
        _hasBusinessProfile = profile != null;
        _jobs = jobs;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openWizard() async {
    if (!_hasBusinessProfile) {
      final created = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const EmployerBusinessSetupScreen()),
      );
      if (created != true) return;
    }
    if (!mounted) return;
    final posted = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const PostJobWizardScreen()));
    if (posted == true) _load();
  }

  Future<void> _runAction(Future<void> Function() action) async {
    try {
      await action();
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.userMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tin của tôi')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openWizard,
        icon: const Icon(Icons.add),
        label: const Text('ĐĂNG TUYỂN'),
      ),
      body: AsyncStateView<List<dynamic>>(
        loading: _loading,
        error: _error,
        data: _loading ? null : _jobs,
        onRetry: _load,
        builder: (context, jobs) {
          if (!_hasBusinessProfile) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Bạn chưa có hồ sơ doanh nghiệp.', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _openWizard, child: const Text('TẠO HỒ SƠ NGAY')),
                  ],
                ),
              ),
            );
          }
          if (jobs.isEmpty) {
            return const Center(child: Text('Bạn chưa đăng tin nào. Nhấn "+ ĐĂNG TUYỂN" để bắt đầu.'));
          }
          return RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              itemCount: jobs.length,
              itemBuilder: (context, index) {
                final job = jobs[index] as Map<String, dynamic>;
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    title: Text(job['title'] ?? ''),
                    subtitle: Text(
                      '${job['status']} · ${job['applicationCount']} ứng viên · ${job['viewCount']} lượt xem',
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => EmployerApplicantsScreen(jobId: job['id'], jobTitle: job['title'] ?? ''),
                      ),
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) {
                        final jobsService = context.read<EmployerJobsService>();
                        if (action == 'close') _runAction(() => jobsService.closeJob(job['id']));
                        if (action == 'renew') _runAction(() => jobsService.renewJob(job['id']));
                        if (action == 'boost') _runAction(() => jobsService.boostJob(job['id']));
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'renew', child: Text('Gia hạn')),
                        PopupMenuItem(value: 'boost', child: Text('🔥 Đẩy tin')),
                        PopupMenuItem(value: 'close', child: Text('Đóng tin')),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
