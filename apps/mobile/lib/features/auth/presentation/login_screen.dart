import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/auth_service.dart';
import '../../../core/network/api_exception.dart';
import 'email_verify_screen.dart';
import 'phone_login_screen.dart';

/// Màn ĐĂNG NHẬP thật của app - OTP-first, KHÔNG mật khẩu.
///
/// Kiến trúc xác thực hiện có (không thay đổi, chỉ dùng đúng):
/// - Email OTP (`/auth/register/email/request|verify`): backend tìm user theo email - đã có tài
///   khoản thì ĐĂNG NHẬP, chưa có thì tạo mới. Đây là đường chính vì tài khoản mới đăng ký bằng
///   email (xem EmailRegisterScreen).
/// - Phone OTP (`/auth/otp/request|verify`): giữ nguyên cho tài khoản cũ tạo bằng SĐT từ trước.
///   KHÔNG phải bước đăng ký mặc định, chỉ là lối đăng nhập phụ ở đây.
///
/// Màn này KHÔNG bao giờ là màn đầu tiên khi mở app - chỉ mở khi người dùng chủ động chọn Đăng
/// nhập, hoặc khi một hành động cần tài khoản (xem shared/widgets/auth_prompt.dart).
class LoginScreen extends StatefulWidget {
  final String intendedRole;

  /// Xác thực theo ngữ cảnh: đăng nhập xong pop(true) về nơi gọi để tiếp tục hành động ban đầu.
  final bool returnOnSuccess;

  const LoginScreen({super.key, this.intendedRole = 'JOB_SEEKER', this.returnOnSuccess = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final email = _emailController.text.trim();
      await context.read<AuthService>().requestEmailVerification(email);
      if (!mounted) return;
      final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => EmailVerifyScreen(
            email: email,
            intendedRole: widget.intendedRole,
            returnOnSuccess: widget.returnOnSuccess,
            isLogin: true,
          ),
        ),
      );
      if (widget.returnOnSuccess && result == true && mounted) {
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (e) {
      setState(() => _error = e.userMessage);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loginWithPhone() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PhoneLoginScreen(
          intendedRole: widget.intendedRole,
          returnOnSuccess: widget.returnOnSuccess,
        ),
      ),
    );
    if (widget.returnOnSuccess && result == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Đăng nhập')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('VIỆC NHA TRANG', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                'Nhập email của bạn, chúng tôi sẽ gửi mã xác minh để đăng nhập.',
                style: TextStyle(color: Colors.black54),
              ),
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
                    : const Text('GỬI MÃ ĐĂNG NHẬP', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _loading ? null : _loginWithPhone,
                child: const Text('Tài khoản cũ tạo bằng số điện thoại? Đăng nhập bằng SĐT'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
