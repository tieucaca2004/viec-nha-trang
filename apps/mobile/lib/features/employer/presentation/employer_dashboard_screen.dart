import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/async_state_view.dart';
import '../data/employer_jobs_service.dart';

/// Dashboard nhà tuyển dụng (đặc tả §17 Phase 3) - số liệu tổng hợp thật từ /jobs/mine,
/// không phải số liệu giả. Backend chưa có endpoint dashboard riêng cho employer (chỉ admin
/// có /admin/dashboard) - tính tổng phía client từ danh sách job của chính employer, đủ dùng
/// ở quy mô 1 employer (vài chục job), ghi API gap này vào docs/MOBILE.md.
class EmployerDashboardScreen extends StatefulWidget {
  const EmployerDashboardScreen({super.key});

  @override
  State<EmployerDashboardScreen> createState() => _EmployerDashboardScreenState();
}

class _EmployerDashboardScreenState extends State<EmployerDashboardScreen> {
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
      appBar: AppBar(title: const Text('Dashboard'), automaticallyImplyLeading: false),
      body: AsyncStateView<List<dynamic>>(
        loading: _loading,
        error: _error,
        data: _loading ? null : _jobs,
        onRetry: _load,
        builder: (context, jobs) {
          final activeJobs = jobs.where((j) => j['status'] == 'ACTIVE').length;
          final totalApplications = jobs.fold<int>(0, (sum, j) => sum + ((j['applicationCount'] ?? 0) as int));
          final totalViews = jobs.fold<int>(0, (sum, j) => sum + ((j['viewCount'] ?? 0) as int));
          final totalHired = jobs.fold<int>(0, (sum, j) => sum + ((j['hiredCount'] ?? 0) as int));

          return RefreshIndicator(
            onRefresh: _load,
            child: GridView.count(
              padding: const EdgeInsets.all(16),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.4,
              children: [
                _statCard('Tin đang tuyển', activeJobs.toString(), Icons.work_outline),
                _statCard('Lượt xem', totalViews.toString(), Icons.visibility_outlined),
                _statCard('Ứng viên', totalApplications.toString(), Icons.people_outline),
                _statCard('Đã tuyển', totalHired.toString(), Icons.check_circle_outline),
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
