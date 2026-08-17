import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/async_state_view.dart';
import '../data/employer_jobs_service.dart';
import 'employer_applicants_screen.dart';

/// Tab "Ứng viên" tổng hợp trên toàn bộ tin của employer (đặc tả §17 Phase 3).
/// Ghi chú API gap: backend chỉ có `/employer/jobs/:jobId/applications` theo từng job, chưa có
/// endpoint gộp applicants của tất cả job một employer trong 1 lần gọi - màn hình này liệt kê
/// job trước, employer bấm vào từng job để xem applicants (thay vì bảng phẳng tất cả applicant).
/// Đủ dùng ở MVP vì employer thường chỉ có vài job hoạt động - xem docs/MOBILE.md.
class EmployerApplicantsOverviewScreen extends StatefulWidget {
  const EmployerApplicantsOverviewScreen({super.key});

  @override
  State<EmployerApplicantsOverviewScreen> createState() => _EmployerApplicantsOverviewScreenState();
}

class _EmployerApplicantsOverviewScreenState extends State<EmployerApplicantsOverviewScreen> {
  List<dynamic> _jobs = [];
  ApiException? _error;
  bool _loading = true;

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
    try {
      final jobs = await context.read<EmployerJobsService>().myJobs();
      if (!mounted) return;
      setState(() => _jobs = jobs);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ứng viên'), automaticallyImplyLeading: false),
      body: AsyncStateView<List<dynamic>>(
        loading: _loading,
        error: _error,
        data: _loading ? null : _jobs,
        isEmpty: (jobs) => jobs.isEmpty,
        emptyMessage: 'Bạn chưa có tin tuyển dụng nào để xem ứng viên.',
        onRetry: _load,
        builder: (context, jobs) => RefreshIndicator(
          onRefresh: _load,
          child: ListView.builder(
            itemCount: jobs.length,
            itemBuilder: (context, index) {
              final job = jobs[index] as Map<String, dynamic>;
              final count = job['applicationCount'] ?? 0;
              return ListTile(
                title: Text(job['title'] ?? ''),
                subtitle: Text('$count ứng viên · ${job['status']}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EmployerApplicantsScreen(jobId: job['id'], jobTitle: job['title'] ?? ''),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
