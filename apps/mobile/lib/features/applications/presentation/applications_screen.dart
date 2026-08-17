import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/models/application.dart';
import '../../../shared/widgets/async_state_view.dart';
import '../../jobs/presentation/job_detail_screen.dart';
import '../data/applications_service.dart';

/// Theo dõi trạng thái ứng tuyển (đặc tả §13 Phase 3) - tab theo trạng thái.
class ApplicationsScreen extends StatefulWidget {
  const ApplicationsScreen({super.key});

  @override
  State<ApplicationsScreen> createState() => _ApplicationsScreenState();
}

class _Tab {
  final String label;
  final Set<String> statuses;
  const _Tab(this.label, this.statuses);
}

class _ApplicationsScreenState extends State<ApplicationsScreen> with SingleTickerProviderStateMixin {
  static const _tabs = [
    _Tab('Mới', {'NEW'}),
    _Tab('Đã xem', {'VIEWED'}),
    _Tab('Đã liên hệ', {'CONTACTED'}),
    _Tab('Phỏng vấn', {'INTERVIEW'}),
    _Tab('Đã nhận', {'HIRED'}),
    _Tab('Không phù hợp', {'NOT_SUITABLE', 'NO_SHOW'}),
  ];

  late final TabController _tabController;
  List<JobApplication> _applications = [];
  ApiException? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final apps = await context.read<ApplicationsService>().listMine();
      if (!mounted) return;
      setState(() => _applications = apps);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
      appBar: AppBar(
        title: const Text('Ứng tuyển của tôi'),
        automaticallyImplyLeading: false,
        bottom: TabBar(controller: _tabController, isScrollable: true, tabs: _tabs.map((t) => Tab(text: t.label)).toList()),
      ),
      body: AsyncStateView<List<JobApplication>>(
        loading: _loading,
        error: _error,
        data: _loading ? null : _applications,
        onRetry: _load,
        builder: (context, applications) => TabBarView(
          controller: _tabController,
          children: _tabs.map((tab) {
            final items = applications.where((a) => tab.statuses.contains(a.status)).toList();
            if (items.isEmpty) {
              return Center(child: Text('Chưa có đơn ứng tuyển ở trạng thái "${tab.label}".'));
            }
            return RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final app = items[index];
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
            );
          }).toList(),
        ),
      ),
    );
  }
}
