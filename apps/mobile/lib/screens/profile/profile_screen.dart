import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/session.dart';
import '../../services/auth_service.dart';
import '../../services/profile_service.dart';
import '../employer/employer_home_screen.dart';
import 'job_seeker_profile_form_screen.dart';

/// Hồ sơ cá nhân (đặc tả mục 12). Có công tắc "Tôi đang cần việc ngay".
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final profile = await context.read<ProfileService>().getJobSeekerProfile();
    setState(() {
      _profile = profile;
      _loading = false;
    });
  }

  Future<void> _toggleLookingNow(bool value) async {
    if (_profile == null) return;
    await context.read<ProfileService>().saveJobSeekerProfile({
      'fullName': _profile!['fullName'],
      'isLookingNow': value,
    });
    _load();
  }

  Future<void> _becomeEmployer() async {
    await context.read<AuthService>().becomeEmployer();
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EmployerHomeScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();

    return Scaffold(
      appBar: AppBar(title: const Text('Cá nhân'), automaticallyImplyLeading: false),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_profile == null)
                  Card(
                    child: ListTile(
                      title: const Text('Tạo hồ sơ tìm việc'),
                      subtitle: const Text('Chỉ mất khoảng 1 phút, không cần CV.'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => const JobSeekerProfileFormScreen()));
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
                else
                  ListTile(
                    leading: const Icon(Icons.storefront),
                    title: const Text('Khu vực nhà tuyển dụng'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const EmployerHomeScreen())),
                  ),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text('Đăng xuất', style: TextStyle(color: Colors.red)),
                  onTap: () => session.logout(),
                ),
              ],
            ),
    );
  }
}
