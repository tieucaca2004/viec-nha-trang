import 'package:flutter/material.dart';
import 'email_register_screen.dart';
import 'login_screen.dart';

/// Điểm rẽ ĐĂNG NHẬP / ĐĂNG KÝ khi một hành động thực sự cần tài khoản (ứng tuyển, lưu việc,
/// đăng tin). Giải thích LÝ DO trước, rồi để người dùng tự chọn - KHÔNG ép thẳng vào một phương
/// thức xác thực cụ thể nào (bug thật đã sửa: trước đây mọi hành động đều nhảy thẳng sang màn
/// "Xác thực số điện thoại", khiến người đăng ký mới bị hỏi SĐT thay vì email).
///
/// Trả về true qua Navigator.pop khi xác thực thành công - nơi gọi tiếp tục đúng hành động ban
/// đầu, không quay về Home (xem shared/widgets/auth_prompt.dart).
class AuthGateScreen extends StatelessWidget {
  final String reason;
  final String intendedRole;

  const AuthGateScreen({super.key, required this.reason, this.intendedRole = 'JOB_SEEKER'});

  Future<void> _open(BuildContext context, Widget screen) async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => screen));
    if (ok == true && context.mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Xác thực tài khoản')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 56, color: Colors.black38),
              const SizedBox(height: 16),
              Text(reason, style: const TextStyle(fontSize: 16), textAlign: TextAlign.center),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: () => _open(
                  context,
                  EmailRegisterScreen(intendedRole: intendedRole, returnOnSuccess: true),
                ),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
                child: const Text('ĐĂNG KÝ TÀI KHOẢN MỚI', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => _open(
                  context,
                  LoginScreen(intendedRole: intendedRole, returnOnSuccess: true),
                ),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
                child: const Text('TÔI ĐÃ CÓ TÀI KHOẢN', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('ĐỂ SAU'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
