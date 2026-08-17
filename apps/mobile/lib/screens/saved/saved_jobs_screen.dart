import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/job.dart';
import '../../services/applications_service.dart';
import '../job_detail/job_detail_screen.dart';

/// Danh sách việc đã lưu (đặc tả mục 25).
class SavedJobsScreen extends StatefulWidget {
  const SavedJobsScreen({super.key});

  @override
  State<SavedJobsScreen> createState() => _SavedJobsScreenState();
}

class _SavedJobsScreenState extends State<SavedJobsScreen> {
  List<dynamic> _saved = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final saved = await context.read<ApplicationsService>().listSaved();
    setState(() {
      _saved = saved;
      _loading = false;
    });
  }

  Future<void> _unsave(String jobId) async {
    await context.read<ApplicationsService>().unsave(jobId);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Việc đã lưu'), automaticallyImplyLeading: false),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _saved.isEmpty
              ? const Center(child: Text('Bạn chưa lưu việc nào.'))
              : ListView.builder(
                  itemCount: _saved.length,
                  itemBuilder: (context, index) {
                    final entry = _saved[index] as Map<String, dynamic>;
                    final job = Job.fromJson(entry['job']);
                    return ListTile(
                      title: Text(job.title),
                      subtitle: Text('${job.employer?.businessName ?? ''} · ${job.salaryLabel}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.favorite, color: Colors.red),
                        onPressed: () => _unsave(job.id),
                      ),
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => JobDetailScreen(jobId: job.id))),
                    );
                  },
                ),
    );
  }
}
