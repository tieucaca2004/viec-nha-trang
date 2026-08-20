import 'package:flutter/material.dart';
import 'email_register_screen.dart';
import 'login_screen.dart';

/// Tab "Tài khoản" cho KHÁCH (chưa đăng nhập) trong MainNavScaffold (đặc tả AUTH UX Part 2/3/8).
/// Thay thế ProfileScreen thật (vốn giả định đã đăng nhập) - không đẩy khách vào màn "Đăng nhập"
/// generic ngay khi mở app, chỉ mời xác thực khi họ chủ động bấm vào tab này.
class GuestAccountScreen extends StatelessWidget {
  const GuestAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tài khoản'), automaticallyImplyLeading: false),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person_outline, size: 64, color: Colors.black38),
                const SizedBox(height: 16),
                const Text(
                  'Đăng nhập hoặc tạo tài khoản để lưu việc, ứng tuyển và quản lý hồ sơ của bạn.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.black87),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const EmailRegisterScreen()),
                  ),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16)),
                  child: const Text('ĐĂNG KÝ TÀI KHOẢN MỚI'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  ),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16)),
                  child: const Text('TÔI ĐÃ CÓ TÀI KHOẢN'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
