import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/auth_service.dart';
import '../../../core/auth/session.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/otp_cooldown.dart';
import '../../../shared/widgets/main_nav_scaffold.dart';

/// Nhập mã xác minh email (EMAIL OTP) để hoàn tất đăng ký hoặc đăng nhập - cùng cấu trúc
/// navigation với OtpScreen (giữ Home làm route gốc, không đẩy chồng nhiều bản Home).
///
/// [isLogin] không chỉ đổi wording - nó chọn ĐÚNG cặp endpoint + cooldown bucket: đăng ký dùng
/// `/auth/register/email/request|verify` (OtpCooldown.emailRegister), đăng nhập dùng
/// `/auth/login/email/request|verify` (OtpCooldown.emailLogin). Backend chạy cùng 1 logic
/// nghiệp vụ (email chưa có tài khoản -> tạo mới; email đã có -> đăng nhập) nhưng route/hạn mức
/// throttle tách riêng - sửa bug thật: trước đây dùng chung route nên đăng ký làm đăng nhập bị
/// 429 dù tài khoản hợp lệ.
class EmailVerifyScreen extends StatefulWidget {
  final String email;
  final String intendedRole;

  /// Chế độ "xác thực theo ngữ cảnh": khi true, xác minh xong chỉ pop(true) về nơi gọi để tiếp
  /// tục đúng hành động ban đầu (ứng tuyển/lưu việc/đăng tin), KHÔNG tự điều hướng sang
  /// MainNavScaffold và KHÔNG tự đổi vai trò - việc đó do caller quyết định.
  final bool returnOnSuccess;
  final bool isLogin;

  const EmailVerifyScreen({
    super.key,
    required this.email,
    this.intendedRole = 'JOB_SEEKER',
    this.returnOnSuccess = false,
    this.isLogin = false,
  });

  @override
  State<EmailVerifyScreen> createState() => _EmailVerifyScreenState();
}

class _EmailVerifyScreenState extends State<EmailVerifyScreen> {
  final _codeController = TextEditingController();
  bool _loading = false;
  bool _resending = false;
  String? _error;

  // Đăng ký và đăng nhập dùng 2 bucket cooldown RIÊNG (xem docstring EmailVerifyScreen).
  OtpCooldown get _cooldown => widget.isLogin ? OtpCooldown.emailLogin : OtpCooldown.emailRegister;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final authService = context.read<AuthService>();
      final session = context.read<Session>();
      if (widget.isLogin) {
        await authService.verifyLoginEmailOtp(widget.email, _codeController.text.trim());
      } else {
        await authService.verifyEmailAndRegister(widget.email, _codeController.text.trim());
      }

      // Xác thực theo ngữ cảnh: chỉ cần có tài khoản, caller sẽ tự tiếp tục hành động ban đầu.
      if (widget.returnOnSuccess) {
        if (!mounted) return;
        Navigator.of(context).pop(true);
        return;
      }

      if (widget.intendedRole == 'EMPLOYER' && !session.isEmployer) {
        await authService.becomeEmployer();
      }
      await session.setActiveRole(widget.intendedRole);

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainNavScaffold()),
        (route) => route.isFirst,
      );
    } on ApiException catch (e) {
      setState(() => _error = e.userMessage);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    // "Gửi lại mã" bắn đúng route (đăng ký hoặc đăng nhập) bị giới hạn 3 lần/60s theo IP - phải
    // tôn trọng đúng cooldown bucket của route đó (xem _cooldown ở trên).
    if (_resending || _cooldown.isActive) return;
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      final authService = context.read<AuthService>();
      if (widget.isLogin) {
        await authService.requestLoginEmailOtp(widget.email);
      } else {
        await authService.requestEmailVerification(widget.email);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã gửi lại mã xác minh.')));
    } on ApiException catch (e) {
      if (e.isRateLimited) _cooldown.start(e.retryAfterSeconds ?? 60);
      setState(() => _error = e.userMessage);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.isLogin ? 'Đăng nhập' : 'Xác minh email')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nhập mã xác minh gửi tới ${widget.email}', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 20),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 24, letterSpacing: 8),
              textAlign: TextAlign.center,
              maxLength: 6,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loading ? null : _submit,
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
              child: _loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('XÁC NHẬN', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<int>(
              valueListenable: _cooldown.remainingSeconds,
              builder: (context, remaining, _) {
                final locked = remaining > 0;
                return TextButton(
                  onPressed: (_resending || locked) ? null : _resend,
                  child: _resending
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(locked ? 'Gửi lại mã sau $remaining giây' : 'Gửi lại mã'),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
