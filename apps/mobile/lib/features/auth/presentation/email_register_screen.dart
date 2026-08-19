import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/auth_service.dart';
import '../../../core/network/api_exception.dart';
import 'email_verify_screen.dart';
import 'phone_login_screen.dart';

/// Đăng ký tài khoản bằng email (đặc tả §1 phase kế tiếp) - thay thế SMS OTP làm bước tạo tài
/// khoản chính. Người dùng đã có tài khoản qua số điện thoại từ trước vẫn đăng nhập được bình
/// thường qua liên kết "Đăng nhập bằng số điện thoại" bên dưới (PhoneLoginScreen KHÔNG đổi).
class EmailRegisterScreen extends StatefulWidget {
  final String intendedRole;
  const EmailRegisterScreen({super.key, this.intendedRole = 'JOB_SEEKER'});

  @override
  State<EmailRegisterScreen> createState() => _EmailRegisterScreenState();
}

class _EmailRegisterScreenState extends State<EmailRegisterScreen> {
  final _emailController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final authService = context.read<AuthService>();
      await authService.requestEmailVerification(_emailController.text.trim());
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EmailVerifyScreen(email: _emailController.text.trim(), intendedRole: widget.intendedRole),
        ),
      );
    } on ApiException catch (e) {
      setState(() => _error = e.userMessage);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Đăng ký')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('VIỆC NHA TRANG', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Đăng ký bằng email để bắt đầu', style: TextStyle(color: Colors.black54)),
              const SizedBox(height: 24),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(fontSize: 18),
                decoration: const InputDecoration(
                  labelText: 'Email',
                  hintText: 'ban@example.com',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _loading ? null : _submit,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('GỬI MÃ XÁC MINH', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => PhoneLoginScreen(intendedRole: widget.intendedRole)),
                ),
                child: const Text('Đã có tài khoản qua số điện thoại? Đăng nhập bằng SĐT'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
