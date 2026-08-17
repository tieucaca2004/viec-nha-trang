import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/models/job.dart';
import '../../../shared/widgets/async_state_view.dart';
import '../../jobs/presentation/job_detail_screen.dart';
import '../data/saved_jobs_service.dart';

/// Danh sách việc đã lưu (đặc tả §14 Phase 3).
class SavedJobsScreen extends StatefulWidget {
  const SavedJobsScreen({super.key});

  @override
  State<SavedJobsScreen> createState() => _SavedJobsScreenState();
}

class _SavedJobsScreenState extends State<SavedJobsScreen> {
  List<dynamic> _saved = [];
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
      final saved = await context.read<SavedJobsService>().listSaved();
      if (!mounted) return;
      setState(() => _saved = saved);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _unsave(String jobId) async {
    final previous = List<dynamic>.from(_saved);
    setState(() => _saved.removeWhere((s) => (s['job']['id']) == jobId));
    try {
      await context.read<SavedJobsService>().unsave(jobId);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saved = previous);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.userMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Việc đã lưu'), automaticallyImplyLeading: false),
      body: AsyncStateView<List<dynamic>>(
        loading: _loading,
        error: _error,
        data: _loading ? null : _saved,
        isEmpty: (saved) => saved.isEmpty,
        emptyMessage: 'Bạn chưa lưu việc nào.',
        onRetry: _load,
        builder: (context, saved) => RefreshIndicator(
          onRefresh: _load,
          child: ListView.builder(
            itemCount: saved.length,
            itemBuilder: (context, index) {
              final entry = saved[index] as Map<String, dynamic>;
              final job = Job.fromJson(entry['job']);
              return ListTile(
                title: Text(job.title),
                subtitle: Text('${job.employer?.businessName ?? ''} · ${job.salaryLabel}'),
                trailing: IconButton(
                  icon: const Icon(Icons.favorite, color: Colors.red),
                  onPressed: () => _unsave(job.id),
                ),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => JobDetailScreen(jobId: job.id))),
              );
            },
          ),
        ),
      ),
    );
  }
}
