import 'package:flutter/material.dart';
import 'phone_login_screen.dart';

/// Màn hình lần đầu mở app (đặc tả Phase 3 §6): logo + slogan + chọn nhu cầu.
/// Vai trò chọn ở đây chỉ là "ý định ban đầu" - tài khoản vẫn có thể có cả 2 vai trò và
/// chuyển đổi sau (đặc tả §5 gốc, backend đã hỗ trợ qua PATCH /me/roles).
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              const Icon(Icons.work_outline, size: 72, color: Color(0xFF0F9D58)),
              const SizedBox(height: 16),
              const Text(
                'VIỆC NHA TRANG',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tìm việc gần bạn. Tuyển người thật.\nLương rõ ràng. Ứng tuyển 1 chạm.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.black54),
              ),
              const Spacer(flex: 2),
              const Text('Bạn đang muốn:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => _goToLogin(context, 'JOB_SEEKER'),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
                child: const Text('TÌM VIỆC', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => _goToLogin(context, 'EMPLOYER'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
                child: const Text('TUYỂN NGƯỜI', style: TextStyle(fontSize: 16)),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  void _goToLogin(BuildContext context, String intendedRole) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PhoneLoginScreen(intendedRole: intendedRole)),
    );
  }
}
