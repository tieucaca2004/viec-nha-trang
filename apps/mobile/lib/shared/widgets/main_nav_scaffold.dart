import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/session.dart';
import '../../features/applications/presentation/applications_screen.dart';
import '../../features/employer/presentation/employer_applicants_overview_screen.dart';
import '../../features/employer/presentation/employer_dashboard_screen.dart';
import '../../features/employer/presentation/employer_home_screen.dart';
import '../../features/jobs/presentation/home_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/saved_jobs/presentation/saved_jobs_screen.dart';

/// Root nav sau khi đăng nhập - chọn giao diện Người tìm việc hay Nhà tuyển dụng theo
/// [Session.activeRole] (đặc tả §7/§17 Phase 3). Chuyển vai trò qua màn Cá nhân (đã hỗ trợ cả 2
/// vai trò trên cùng 1 tài khoản, đặc tả §5 gốc) - không tạo tài khoản/đăng nhập lại.
class MainNavScaffold extends StatelessWidget {
  const MainNavScaffold({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return session.activeRole == 'EMPLOYER' ? const _EmployerNav() : const _SeekerNav();
  }
}

class _SeekerNav extends StatefulWidget {
  const _SeekerNav();

  @override
  State<_SeekerNav> createState() => _SeekerNavState();
}

class _SeekerNavState extends State<_SeekerNav> {
  int _index = 0;

  static const _screens = [
    HomeScreen(),
    SavedJobsScreen(),
    ApplicationsScreen(),
    NotificationsScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Việc làm'),
          NavigationDestination(icon: Icon(Icons.favorite_border), selectedIcon: Icon(Icons.favorite), label: 'Đã lưu'),
          NavigationDestination(icon: Icon(Icons.send_outlined), selectedIcon: Icon(Icons.send), label: 'Ứng tuyển'),
          NavigationDestination(icon: Icon(Icons.notifications_none), selectedIcon: Icon(Icons.notifications), label: 'Thông báo'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Cá nhân'),
        ],
      ),
    );
  }
}

/// Nav riêng cho nhà tuyển dụng (đặc tả §17): Dashboard / Tin tuyển dụng / Ứng viên /
/// Thông báo / Cá nhân. Nút "+ ĐĂNG TUYỂN" nằm trong tab Tin tuyển dụng (EmployerHomeScreen).
class _EmployerNav extends StatefulWidget {
  const _EmployerNav();

  @override
  State<_EmployerNav> createState() => _EmployerNavState();
}

class _EmployerNavState extends State<_EmployerNav> {
  int _index = 0;

  static const _screens = [
    EmployerDashboardScreen(),
    EmployerHomeScreen(),
    EmployerApplicantsOverviewScreen(),
    NotificationsScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.work_outline), selectedIcon: Icon(Icons.work), label: 'Tin tuyển dụng'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Ứng viên'),
          NavigationDestination(icon: Icon(Icons.notifications_none), selectedIcon: Icon(Icons.notifications), label: 'Thông báo'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Cá nhân'),
        ],
      ),
    );
  }
}
