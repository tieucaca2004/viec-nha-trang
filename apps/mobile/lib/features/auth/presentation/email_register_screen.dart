import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/auth_service.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/otp_cooldown.dart';
import 'email_verify_screen.dart';
import 'phone_login_screen.dart';

/// Đăng ký tài khoản bằng email (đặc tả §1 phase kế tiếp) - thay thế SMS OTP làm bước tạo tài
/// khoản chính. Người dùng đã có tài khoản qua số điện thoại từ trước vẫn đăng nhập được bình
/// thường qua liên kết "Đăng nhập bằng số điện thoại" bên dưới (PhoneLoginScreen KHÔNG đổi).
class EmailRegisterScreen extends StatefulWidget {
  final String intendedRole;

  /// Xác thực theo ngữ cảnh: đăng ký xong pop(true) về nơi gọi để tiếp tục đúng hành động ban đầu
  /// (ứng tuyển/lưu việc/đăng tin) thay vì điều hướng về MainNavScaffold - xem EmailVerifyScreen.
  final bool returnOnSuccess;

  const EmailRegisterScreen({
    super.key,
    this.intendedRole = 'JOB_SEEKER',
    this.returnOnSuccess = false,
  });

  @override
  State<EmailRegisterScreen> createState() => _EmailRegisterScreenState();
}

class _EmailRegisterScreenState extends State<EmailRegisterScreen> {
  final _emailController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    // Route + hạn mức RIÊNG với màn Đăng nhập (xem OtpCooldown.emailRegister vs .emailLogin).
    if (_loading || OtpCooldown.emailRegister.isActive) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final authService = context.read<AuthService>();
      await authService.requestEmailVerification(_emailController.text.trim());
      if (!mounted) return;
      final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => EmailVerifyScreen(
            email: _emailController.text.trim(),
            intendedRole: widget.intendedRole,
            returnOnSuccess: widget.returnOnSuccess,
          ),
        ),
      );
      // Lan truyền kết quả xác thực về đúng nơi đã gọi (AuthGateScreen -> requireAuthentication).
      if (widget.returnOnSuccess && result == true && mounted) {
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (e) {
      if (e.isRateLimited) OtpCooldown.emailRegister.start(e.retryAfterSeconds ?? 60);
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
              ValueListenableBuilder<int>(
                valueListenable: OtpCooldown.emailRegister.remainingSeconds,
                builder: (context, remaining, _) {
                  final locked = remaining > 0;
                  return FilledButton(
                    onPressed: (_loading || locked) ? null : _submit,
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
                    child: _loading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(
                            locked ? 'GỬI LẠI SAU $remaining GIÂY' : 'GỬI MÃ XÁC MINH',
                            style: const TextStyle(fontSize: 16),
                          ),
                  );
                },
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
