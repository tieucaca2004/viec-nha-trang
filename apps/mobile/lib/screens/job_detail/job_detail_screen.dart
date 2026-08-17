import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api_client.dart';
import '../../services/applications_service.dart';
import '../../services/jobs_service.dart';

/// Trang chi tiết việc làm (đặc tả mục 10): mô tả, yêu cầu, quyền lợi,
/// thông tin nhà tuyển dụng, và 3 nút hành động chính: Ứng tuyển / Gọi / Zalo.
class JobDetailScreen extends StatefulWidget {
  final String jobId;
  const JobDetailScreen({super.key, required this.jobId});

  @override
  State<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  Map<String, dynamic>? _job;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final job = await context.read<JobsService>().getById(widget.jobId);
      setState(() => _job = job);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _apply() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bạn muốn ứng tuyển công việc này?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ỨNG TUYỂN')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await context.read<ApplicationsService>().apply(widget.jobId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ứng tuyển thành công.')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _call(String? phone) async {
    if (phone == null) return;
    await launchUrl(Uri.parse('tel:$phone'));
  }

  Future<void> _zalo(String? phone) async {
    if (phone == null) return;
    await launchUrl(Uri.parse('https://zalo.me/$phone'), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null || _job == null) {
      return Scaffold(body: Center(child: Text(_error ?? 'Không tìm thấy tin.')));
    }

    final job = _job!;
    final employer = job['employer'] as Map<String, dynamic>?;
    final area = job['area'] as Map<String, dynamic>?;
    final phone = job['employerLocation']?['phone'] as String?;

    return Scaffold(
      appBar: AppBar(title: Text(job['title'] ?? '')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(job['title'] ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text(employer?['businessName'] ?? '', style: const TextStyle(fontSize: 16, color: Colors.black54)),
          const SizedBox(height: 4),
          const Text('🟢 Đang tuyển', style: TextStyle(color: Colors.green)),
          const SizedBox(height: 12),
          Text(
            '${job['salaryMin']}–${job['salaryMax']}đ',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green),
          ),
          if (area != null) Text('📍 ${area['name']}, Nha Trang'),
          if (job['shiftStartTime'] != null) Text('Ca làm: ${job['shiftStartTime']}–${job['shiftEndTime']}'),
          Text('Loại: ${job['employmentType'] == 'FULL_TIME' ? 'Full-time' : 'Part-time'}'),
          Text('Số lượng: ${job['headcount']} người'),
          const Divider(height: 32),
          const Text('Mô tả', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Text(job['description'] ?? 'Chưa có mô tả.'),
          const SizedBox(height: 16),
          const Text('Yêu cầu', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Text(job['requirements'] ?? 'Không yêu cầu đặc biệt.'),
          const SizedBox(height: 16),
          const Text('Quyền lợi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Text(job['benefits'] ?? 'Đang cập nhật.'),
          const Divider(height: 32),
          const Text('Nhà tuyển dụng', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(child: Icon(Icons.store)),
            title: Text(employer?['businessName'] ?? ''),
            subtitle: Text('⭐ ${(employer?['ratingAvg'] ?? 0).toStringAsFixed(1)} · Đã tuyển ${employer?['hiredCount'] ?? 0} người'),
          ),
          const SizedBox(height: 80),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: FilledButton(onPressed: _apply, child: const Text('ỨNG TUYỂN 1 CHẠM')),
              ),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton(onPressed: () => _call(phone), child: const Text('GỌI'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton(onPressed: () => _zalo(phone), child: const Text('ZALO'))),
            ],
          ),
        ),
      ),
    );
  }
}
