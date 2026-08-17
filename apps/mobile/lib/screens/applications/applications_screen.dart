import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/application.dart';
import '../../services/applications_service.dart';
import '../job_detail/job_detail_screen.dart';

/// Theo dõi trạng thái ứng tuyển (đặc tả mục 16).
class ApplicationsScreen extends StatefulWidget {
  const ApplicationsScreen({super.key});

  @override
  State<ApplicationsScreen> createState() => _ApplicationsScreenState();
}

class _ApplicationsScreenState extends State<ApplicationsScreen> {
  List<JobApplication> _applications = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final apps = await context.read<ApplicationsService>().listMine();
    setState(() {
      _applications = apps;
      _loading = false;
    });
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'HIRED':
        return Colors.green;
      case 'NOT_SUITABLE':
      case 'NO_SHOW':
        return Colors.red;
      case 'INTERVIEW':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ứng tuyển của tôi'), automaticallyImplyLeading: false),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _applications.isEmpty
              ? const Center(child: Text('Bạn chưa ứng tuyển việc nào.'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: _applications.length,
                    itemBuilder: (context, index) {
                      final app = _applications[index];
                      return ListTile(
                        title: Text(app.job?.title ?? ''),
                        subtitle: Text(app.job?.employer?.businessName ?? ''),
                        trailing: Chip(
                          label: Text(app.statusLabel, style: const TextStyle(color: Colors.white)),
                          backgroundColor: _statusColor(app.status),
                        ),
                        onTap: app.job == null
                            ? null
                            : () => Navigator.of(context)
                                .push(MaterialPageRoute(builder: (_) => JobDetailScreen(jobId: app.job!.id))),
                      );
                    },
                  ),
                ),
    );
  }
}
