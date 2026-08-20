import 'package:flutter/material.dart';
import 'phone_login_screen.dart';

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
                  'Xác thực số điện thoại để lưu việc, ứng tuyển và quản lý hồ sơ của bạn.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.black87),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PhoneLoginScreen()),
                  ),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16)),
                  child: const Text('XÁC THỰC ĐỂ TIẾP TỤC'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
