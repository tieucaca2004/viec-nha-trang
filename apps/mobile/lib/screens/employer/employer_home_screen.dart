import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/employer_jobs_service.dart';
import '../../services/profile_service.dart';
import 'employer_applicants_screen.dart';
import 'employer_business_setup_screen.dart';
import 'post_job_wizard_screen.dart';

/// Khu vực quản lý dành cho nhà tuyển dụng (đặc tả mục 15).
class EmployerHomeScreen extends StatefulWidget {
  const EmployerHomeScreen({super.key});

  @override
  State<EmployerHomeScreen> createState() => _EmployerHomeScreenState();
}

class _EmployerHomeScreenState extends State<EmployerHomeScreen> {
  List<dynamic> _jobs = [];
  bool _loading = true;
  bool _hasBusinessProfile = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final profile = await context.read<ProfileService>().getEmployerProfile();
    final jobs = profile == null ? <dynamic>[] : await context.read<EmployerJobsService>().myJobs();
    setState(() {
      _hasBusinessProfile = profile != null;
      _jobs = jobs;
      _loading = false;
    });
  }

  Future<void> _openWizard() async {
    if (!_hasBusinessProfile) {
      final created = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const EmployerBusinessSetupScreen()),
      );
      if (created != true) return;
    }
    final posted = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const PostJobWizardScreen()));
    if (posted == true) _load();
  }

  Future<void> _closeJob(String id) async {
    await context.read<EmployerJobsService>().closeJob(id);
    _load();
  }

  Future<void> _renewJob(String id) async {
    await context.read<EmployerJobsService>().renewJob(id);
    _load();
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_hasBusinessProfile
              ? Center(
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
                )
              : _jobs.isEmpty
                  ? const Center(child: Text('Bạn chưa đăng tin nào. Nhấn "+ ĐĂNG TUYỂN" để bắt đầu.'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        itemCount: _jobs.length,
                        itemBuilder: (context, index) {
                          final job = _jobs[index] as Map<String, dynamic>;
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
                                  if (action == 'close') _closeJob(job['id']);
                                  if (action == 'renew') _renewJob(job['id']);
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'renew', child: Text('Gia hạn')),
                                  PopupMenuItem(value: 'close', child: Text('Đóng tin')),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
