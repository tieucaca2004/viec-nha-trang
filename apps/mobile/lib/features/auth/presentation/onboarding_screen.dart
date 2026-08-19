import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'email_register_screen.dart';
import '../../../core/auth/session.dart';
import '../../../shared/widgets/main_nav_scaffold.dart';

/// Home/root của app (đặc tả Phase 3 §6, sửa lỗi navigation §1): logo + slogan + chọn nhu cầu.
/// Đây LUÔN là route đầu tiên của app (xem main.dart), kể cả khi đã đăng nhập - để mọi màn hình
/// bên trong luôn có đường quay lại đúng Home này qua Navigator.pop/system back, thay vì Home
/// biến mất khỏi stack sau khi đăng nhập như trước.
///
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
                onPressed: () => _selectRole(context, 'JOB_SEEKER'),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
                child: const Text('TÌM VIỆC', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => _selectRole(context, 'EMPLOYER'),
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

  // Đã đăng nhập -> vào thẳng nav của vai trò đó (không qua lại màn đăng ký/đăng nhập). Chưa
  // đăng nhập -> đăng ký bằng EMAIL (đặc tả §1 phase kế tiếp: không dùng SMS OTP để tạo tài
  // khoản nữa). Tài khoản cũ tạo qua SĐT vẫn đăng nhập được qua liên kết trong
  // EmailRegisterScreen ("Đăng nhập bằng SĐT") - KHÔNG xoá bỏ PhoneLoginScreen.
  void _selectRole(BuildContext context, String intendedRole) {
    final session = context.read<Session>();
    if (session.isLoggedIn) {
      session.setActiveRole(intendedRole);
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const MainNavScaffold()),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => EmailRegisterScreen(intendedRole: intendedRole)),
      );
    }
  }
}
