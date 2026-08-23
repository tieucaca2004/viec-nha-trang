import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/auth/session.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/async_state_view.dart';
import '../../../shared/widgets/auth_prompt.dart';
import '../../applications/data/applications_service.dart';
import '../../profile/data/job_seeker_profile_service.dart';
import '../../profile/presentation/job_seeker_profile_form_screen.dart';
import '../../saved_jobs/data/saved_jobs_service.dart';
import '../data/jobs_service.dart';
import '../../../shared/widgets/phone_verification_sheet.dart';
import '../../../shared/widgets/job_provenance_badge.dart';
import '../../../shared/models/job.dart';

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
  bool _saved = false;
  bool _togglingSave = false;

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
    final savedJobsService = context.read<SavedJobsService>();
    final isLoggedIn = context.read<Session>().isLoggedIn;
    try {
      // GET /jobs/:id là public (OptionalJwtAuthGuard) - khách xem chi tiết việc bình thường
      // (đặc tả AUTH UX Part 3). isApplied/isSaved chỉ có ý nghĩa khi đã đăng nhập - KHÔNG gọi
      // /applications/me hay /saved-jobs cho khách (Part 11: guest browsing không phụ thuộc API
      // cần đăng nhập) - lỗi 401 ở đây trước đây còn làm hỏng luôn cả trang chi tiết (job load
      // được nhưng bị _error đè lên do listMine() ném 401 chung 1 try/catch).
      final job = await jobsService.getById(widget.jobId);
      bool applied = false;
      bool saved = false;
      if (isLoggedIn) {
        try {
          final applications = await applicationsService.listMine();
          applied = applications.any((a) => a.job?.id == widget.jobId);
        } catch (_) {
          // Không chặn trang chi tiết nếu không tải được trạng thái đã ứng tuyển.
        }
        try {
          final savedList = await savedJobsService.listSaved();
          saved = savedList.any((s) => (s as Map)['jobId']?.toString() == widget.jobId);
        } catch (_) {
          // Không chặn trang chi tiết nếu không tải được danh sách đã lưu - nút lưu vẫn hoạt động,
          // chỉ là trạng thái ban đầu có thể chưa chính xác.
        }
      }
      if (!mounted) return;
      setState(() {
        _job = job;
        _applied = applied;
        _saved = saved;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _apply() async {
    // Đặc tả AUTH UX Part 6: khách bấm ỨNG TUYỂN -> hỏi xác thực TRƯỚC bất kỳ bước nào khác (kể
    // cả kiểm tra hồ sơ, vì getJobSeekerProfile() cần đăng nhập) -> xác thực xong tự quay lại
    // đúng đây tiếp tục ứng tuyển, không phải tìm lại job/bấm lại từ Home.
    if (!context.read<Session>().isLoggedIn) {
      final ok = await requireAuthentication(context, reason: 'Để ứng tuyển, bạn cần đăng nhập hoặc tạo tài khoản.');
      if (!ok || !mounted) return;
    }

    final profileService = context.read<JobSeekerProfileService>();
    final applicationsService = context.read<ApplicationsService>();
    // Bug thật: getJobSeekerProfile() không được bọc try/catch nên lỗi 500/mất mạng ở đây khiến
    // nút ỨNG TUYỂN im lặng không phản hồi gì - không loading, không thông báo lỗi, không crash
    // rõ ràng, chỉ đơn giản là "bấm không có gì xảy ra". Bọc + báo lỗi đúng như phần applyJob bên
    // dưới trong cùng file này.
    Map<String, dynamic>? profile;
    try {
      profile = await profileService.getJobSeekerProfile();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.userMessage)));
      return;
    }
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
      // Đặc tả §3: backend từ chối ứng tuyển khi số điện thoại chưa xác minh, báo bằng message
      // cố định 'PHONE_NOT_VERIFIED' (không phải lỗi 403 chung) - mở sheet xác minh ngay tại
      // đây, xong thì thử ứng tuyển lại 1 lần, không bắt người dùng bấm nút ỨNG TUYỂN lần nữa.
      if (e.statusCode == 403 && e.rawMessage == 'PHONE_NOT_VERIFIED') {
        if (!mounted) return;
        final verified = await showPhoneVerificationSheet(context);
        if (verified == true && mounted) {
          try {
            await applicationsService.apply(widget.jobId);
            if (!mounted) return;
            setState(() => _applied = true);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ứng tuyển thành công.')));
          } on ApiException catch (e2) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e2.userMessage)));
          }
        }
      } else if (e.isUnauthorized) {
        // Phiên hết hạn giữa chừng (đặc tả Part 7) - hỏi xác thực lại rồi tự thử ứng tuyển lại
        // đúng 1 lần, không bắt user thoát ra tìm lại job.
        if (!mounted) return;
        final ok = await requireAuthentication(context, reason: 'Để ứng tuyển, bạn cần đăng nhập hoặc tạo tài khoản.');
        if (ok && mounted) {
          try {
            await applicationsService.apply(widget.jobId);
            if (!mounted) return;
            setState(() => _applied = true);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ứng tuyển thành công.')));
          } on ApiException catch (e2) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e2.userMessage)));
          }
        }
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.userMessage)));
      }
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

  Future<void> _toggleSave() async {
    if (_togglingSave) return;
    final wasSaved = _saved;
    setState(() => _togglingSave = true);
    try {
      final saved = await runWithAuth<bool>(
        context,
        reason: 'Để lưu việc này, bạn cần đăng nhập hoặc tạo tài khoản.',
        action: () async {
          final savedJobsService = context.read<SavedJobsService>();
          if (wasSaved) {
            await savedJobsService.unsave(widget.jobId);
          } else {
            await savedJobsService.save(widget.jobId);
          }
          return !wasSaved;
        },
      );
      if (saved != null && mounted) setState(() => _saved = saved);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.userMessage)));
    } finally {
      if (mounted) setState(() => _togglingSave = false);
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
      appBar: AppBar(
        title: Text(_job?['title'] ?? 'Chi tiết công việc'),
        actions: [
          if (_job != null)
            IconButton(
              icon: Icon(_saved ? Icons.bookmark : Icons.bookmark_border),
              tooltip: _saved ? 'Bỏ lưu việc này' : 'Lưu việc này',
              onPressed: _toggleSave,
            ),
        ],
      ),
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
    // Nhãn nguồn dữ liệu (đặc tả JobHunter Phần 11) - tái dùng Job.fromJson() có sẵn thay vì
    // refactor toàn bộ màn này sang dùng Job model (map thô vẫn đủ field từ GET /jobs/:id).
    final provenanceJob = Job.fromJson(job);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text(job['title'] ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text(employer?['businessName'] ?? '', style: const TextStyle(fontSize: 16, color: Colors.black54)),
        if (provenanceJob.isSynthetic || provenanceJob.isImported) ...[
          const SizedBox(height: 4),
          JobProvenanceBadge(job: provenanceJob),
        ],
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
