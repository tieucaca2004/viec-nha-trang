import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/auth/session.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/async_state_view.dart';
import '../../../shared/widgets/phone_verification_sheet.dart';
import '../../auth/data/auth_service.dart';
import '../data/job_seeker_profile_service.dart';
import 'job_seeker_dashboard_screen.dart';
import 'job_seeker_profile_form_screen.dart';

/// Hồ sơ cá nhân (đặc tả §16 Phase 3). Có công tắc "Tôi đang cần việc ngay".
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _me;
  ApiException? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profileService = context.read<JobSeekerProfileService>();
    final authService = context.read<AuthService>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await profileService.getJobSeekerProfile();
      final me = await authService.getMe();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _me = me;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Xác minh số điện thoại (đặc tả §4) - hiển thị trạng thái thật từ /me (isPhoneVerified), chỉ
  // đánh dấu "Đã xác minh" khi backend xác nhận qua OTP thật, không phải chỉ vì đã nhập số.
  Future<void> _verifyPhone() async {
    final verified = await showPhoneVerificationSheet(context);
    if (verified == true) _load();
  }

  // Đăng xuất xong phải quay về đúng Home (route đầu tiên - OnboardingScreen), không để lại
  // MainNavScaffold cũ (đã hết phiên) hiển thị lơ lửng trên stack (sửa lỗi navigation §1).
  Future<void> _logout(BuildContext context, Session session) async {
    await session.logout();
    if (context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _toggleLookingNow(bool value) async {
    if (_profile == null) return;
    try {
      await context.read<JobSeekerProfileService>().saveJobSeekerProfile({
        'fullName': _profile!['fullName'],
        'isLookingNow': value,
      });
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.userMessage)));
    }
  }

  Future<void> _becomeEmployer() async {
    final authService = context.read<AuthService>();
    final session = context.read<Session>();
    try {
      await authService.becomeEmployer();
      await session.setActiveRole('EMPLOYER');
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.userMessage)));
    }
  }

  Future<void> _switchActiveRole(String role) => context.read<Session>().setActiveRole(role);

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();

    return Scaffold(
      appBar: AppBar(title: const Text('Cá nhân'), automaticallyImplyLeading: false),
      body: AsyncStateView<Map<String, dynamic>?>(
        loading: _loading,
        error: _error,
        data: _loading ? null : (_profile ?? const <String, dynamic>{}),
        onRetry: _load,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.bar_chart),
                title: const Text('Thống kê của bạn'),
                subtitle: const Text('Hồ sơ, việc đã lưu, ứng tuyển'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const JobSeekerDashboardScreen()),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: Icon(
                  _me?['isPhoneVerified'] == true ? Icons.verified : Icons.phone_outlined,
                  color: _me?['isPhoneVerified'] == true ? Colors.green : null,
                ),
                title: Text(_me?['phone'] ?? 'Chưa có số điện thoại'),
                subtitle: Text(_me?['isPhoneVerified'] == true ? 'Đã xác minh' : 'Chưa xác minh'),
                trailing: _me?['isPhoneVerified'] == true
                    ? null
                    : TextButton(onPressed: _verifyPhone, child: const Text('XÁC MINH')),
              ),
            ),
            const SizedBox(height: 12),
            if (_profile == null)
              Card(
                child: ListTile(
                  title: const Text('Tạo hồ sơ tìm việc'),
                  subtitle: const Text('Chỉ mất khoảng 1 phút, không cần CV.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JobSeekerProfileFormScreen()));
                    _load();
                  },
                ),
              )
            else ...[
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(_profile!['fullName'] ?? ''),
                subtitle: Text(_profile!['isSeeking'] == true ? '🟢 Đang tìm việc' : 'Tạm ngừng tìm việc'),
                trailing: IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => JobSeekerProfileFormScreen(existing: _profile)),
                    );
                    _load();
                  },
                ),
              ),
              SwitchListTile(
                title: const Text('Tôi đang cần việc ngay'),
                subtitle: const Text('Ưu tiên giới thiệu việc phù hợp cho bạn'),
                value: _profile!['isLookingNow'] == true,
                onChanged: _toggleLookingNow,
              ),
            ],
            const Divider(height: 32),
            if (!session.isEmployer)
              ListTile(
                leading: const Icon(Icons.storefront),
                title: const Text('Tôi là nhà tuyển dụng'),
                subtitle: const Text('Đăng tin tuyển người trên Việc Nha Trang'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _becomeEmployer,
              )
            else if (session.activeRole != 'EMPLOYER')
              ListTile(
                leading: const Icon(Icons.storefront),
                title: const Text('Chuyển sang chế độ Nhà tuyển dụng'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _switchActiveRole('EMPLOYER'),
              )
            else
              ListTile(
                leading: const Icon(Icons.person_search),
                title: const Text('Chuyển sang chế độ Tìm việc'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _switchActiveRole('JOB_SEEKER'),
              ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Đăng xuất', style: TextStyle(color: Colors.red)),
              onTap: () => _logout(context, session),
            ),
          ],
        ),
      ),
    );
  }
}
