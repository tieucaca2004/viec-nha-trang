import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../screens/applications/applications_screen.dart';
import '../screens/employer/employer_home_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/saved/saved_jobs_screen.dart';

/// Thanh điều hướng 5 mục (đặc tả mục 7): Việc làm, Đã lưu, Ứng tuyển, Thông báo, Cá nhân.
/// Nếu tài khoản có vai trò nhà tuyển dụng, hiện thêm nút nổi "+ ĐĂNG TUYỂN".
class MainNavScaffold extends StatefulWidget {
  const MainNavScaffold({super.key});

  @override
  State<MainNavScaffold> createState() => _MainNavScaffoldState();
}

class _MainNavScaffoldState extends State<MainNavScaffold> {
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
    final session = context.watch<Session>();

    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      floatingActionButton: session.isEmployer
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const EmployerHomeScreen()),
              ),
              icon: const Icon(Icons.add),
              label: const Text('ĐĂNG TUYỂN'),
            )
          : null,
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
