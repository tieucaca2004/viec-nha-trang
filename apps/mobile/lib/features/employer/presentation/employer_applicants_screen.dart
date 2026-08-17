import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/async_state_view.dart';
import '../data/employer_jobs_service.dart';

/// Quản lý ứng viên theo state machine trạng thái (đặc tả §21 Phase 3).
class EmployerApplicantsScreen extends StatefulWidget {
  final String jobId;
  final String jobTitle;
  const EmployerApplicantsScreen({super.key, required this.jobId, required this.jobTitle});

  @override
  State<EmployerApplicantsScreen> createState() => _EmployerApplicantsScreenState();
}

class _EmployerApplicantsScreenState extends State<EmployerApplicantsScreen> {
  List<dynamic> _applicants = [];
  ApiException? _error;
  bool _loading = true;

  static const _statusFlow = {
    'NEW': ['VIEWED', 'CONTACTED', 'NOT_SUITABLE'],
    'VIEWED': ['CONTACTED', 'NOT_SUITABLE'],
    'CONTACTED': ['INTERVIEW', 'NOT_SUITABLE'],
    'INTERVIEW': ['HIRED', 'NOT_SUITABLE', 'NO_SHOW'],
  };

  static const _statusLabels = {
    'NEW': 'Mới',
    'VIEWED': 'Đã xem',
    'CONTACTED': 'Đã liên hệ',
    'INTERVIEW': 'Phỏng vấn',
    'HIRED': 'Đã nhận',
    'NOT_SUITABLE': 'Không phù hợp',
    'NO_SHOW': 'Ứng viên không đến',
  };

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
      final applicants = await context.read<EmployerJobsService>().applicantsForJob(widget.jobId);
      if (!mounted) return;
      setState(() => _applicants = applicants);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateStatus(String applicationId, String status) async {
    try {
      await context.read<EmployerJobsService>().updateApplicationStatus(applicationId, status);
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.userMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Ứng viên - ${widget.jobTitle}')),
      body: AsyncStateView<List<dynamic>>(
        loading: _loading,
        error: _error,
        data: _loading ? null : _applicants,
        isEmpty: (a) => a.isEmpty,
        emptyMessage: 'Chưa có ứng viên nào.',
        onRetry: _load,
        builder: (context, applicants) => RefreshIndicator(
          onRefresh: _load,
          child: ListView.builder(
            itemCount: applicants.length,
            itemBuilder: (context, index) {
              final app = applicants[index] as Map<String, dynamic>;
              final seeker = app['jobSeeker'] as Map<String, dynamic>?;
              final phone = (seeker?['user'] as Map<String, dynamic>?)?['phone'] as String?;
              final status = app['status'] as String;
              final nextOptions = _statusFlow[status] ?? [];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(seeker?['fullName'] ?? 'Ứng viên', style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (app['matchScore'] != null) Text('🎯 ${app['matchScore']}% phù hợp'),
                      Text('Trạng thái: ${_statusLabels[status] ?? status}'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.call),
                            onPressed: phone == null ? null : () => launchUrl(Uri.parse('tel:$phone')),
                          ),
                          IconButton(
                            icon: const Icon(Icons.chat),
                            onPressed: phone == null ? null : () => launchUrl(Uri.parse('https://zalo.me/$phone')),
                          ),
                          const Spacer(),
                          if (nextOptions.isNotEmpty)
                            DropdownButton<String>(
                              hint: const Text('Đổi trạng thái'),
                              items: nextOptions.map((s) => DropdownMenuItem(value: s, child: Text(_statusLabels[s] ?? s))).toList(),
                              onChanged: (s) {
                                if (s != null) _updateStatus(app['id'], s);
                              },
                            ),
                        ],
                      ),
                    ],
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
