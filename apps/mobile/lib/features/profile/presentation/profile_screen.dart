import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/auth/session.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/async_state_view.dart';
import '../../auth/data/auth_service.dart';
import '../data/job_seeker_profile_service.dart';
import 'job_seeker_profile_form_screen.dart';

/// Hồ sơ cá nhân (đặc tả §16 Phase 3). Có công tắc "Tôi đang cần việc ngay".
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
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
      final profile = await context.read<JobSeekerProfileService>().getJobSeekerProfile();
      if (!mounted) return;
      setState(() => _profile = profile);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
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
              onTap: () => session.logout(),
            ),
          ],
        ),
      ),
    );
  }
}
