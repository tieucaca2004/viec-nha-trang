import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/async_state_view.dart';
import '../../applications/data/applications_service.dart';
import '../../profile/data/job_seeker_profile_service.dart';
import '../../profile/presentation/job_seeker_profile_form_screen.dart';
import '../data/jobs_service.dart';

/// Trang chi tiết việc làm (đặc tả §11 Phase 3): mô tả, yêu cầu, quyền lợi,
/// thông tin nhà tuyển dụng, và 3 nút hành động chính: Ứng tuyển / Gọi / Zalo.
class JobDetailScreen extends StatefulWidget {
  final String jobId;
  const JobDetailScreen({super.key, required this.jobId});

  @override
  State<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  Map<String, dynamic>? _job;
  ApiException? _error;
  bool _loading = true;
  bool _applied = false;
  bool _applying = false;

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
    final jobsService = context.read<JobsService>();
    final applicationsService = context.read<ApplicationsService>();
    try {
      final job = await jobsService.getById(widget.jobId);
      final applications = await applicationsService.listMine();
      if (!mounted) return;
      setState(() {
        _job = job;
        _applied = applications.any((a) => a.job?.id == widget.jobId);
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _apply() async {
    final profileService = context.read<JobSeekerProfileService>();
    final applicationsService = context.read<ApplicationsService>();
    final profile = await profileService.getJobSeekerProfile();
    if (!profileService.isCompleteEnoughToApply(profile)) {
      if (!mounted) return;
      await _promptCompleteProfile();
      return;
    }

    if (!mounted) return;
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

    setState(() => _applying = true);
    try {
      await applicationsService.apply(widget.jobId);
      if (!mounted) return;
      setState(() => _applied = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ứng tuyển thành công.')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.userMessage)));
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<void> _promptCompleteProfile() async {
    final shouldGo = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hoàn thiện hồ sơ để ứng tuyển'),
        content: const Text('Bạn cần có hồ sơ cơ bản (họ tên) trước khi ứng tuyển. CV không bắt buộc.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Để sau')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('HOÀN THIỆN NGAY')),
        ],
      ),
    );
    if (shouldGo == true && mounted) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JobSeekerProfileFormScreen()));
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
    return Scaffold(
      appBar: AppBar(title: Text(_job?['title'] ?? 'Chi tiết công việc')),
      body: AsyncStateView<Map<String, dynamic>>(
        loading: _loading,
        error: _error,
        data: _job,
        onRetry: _load,
        builder: (context, job) => _buildBody(job),
      ),
      bottomNavigationBar: _job == null ? null : _buildBottomBar(_job!),
    );
  }

  Widget _buildBody(Map<String, dynamic> job) {
    final employer = job['employer'] as Map<String, dynamic>?;
    final area = job['area'] as Map<String, dynamic>?;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
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
      ],
    );
  }

  Widget _buildBottomBar(Map<String, dynamic> job) {
    final phone = job['employerLocation']?['phone'] as String?;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: _applied
                  ? const OutlinedButton(onPressed: null, child: Text('ĐÃ ỨNG TUYỂN'))
                  : FilledButton(
                      onPressed: _applying ? null : _apply,
                      child: _applying
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('ỨNG TUYỂN 1 CHẠM'),
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: () => _call(phone), child: const Text('GỌI'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: () => _zalo(phone), child: const Text('ZALO'))),
          ],
        ),
      ),
    );
  }
}
