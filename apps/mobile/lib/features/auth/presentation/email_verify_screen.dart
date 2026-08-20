import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/auth_service.dart';
import '../../../core/auth/session.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/main_nav_scaffold.dart';

/// Nhập mã xác minh email (EMAIL OTP) để hoàn tất đăng ký hoặc đăng nhập - cùng cấu trúc
/// navigation với OtpScreen (giữ Home làm route gốc, không đẩy chồng nhiều bản Home).
///
/// Backend dùng CHUNG 1 cặp endpoint (`/auth/register/email/request|verify`) cho cả 2 việc:
/// email chưa có tài khoản -> tạo mới; email đã có tài khoản -> đăng nhập (xem
/// AuthService.verifyEmailAndRegister ở backend). [isLogin] chỉ đổi WORDING cho đúng ngữ cảnh
/// người dùng đang ở, không đổi endpoint.
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

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final authService = context.read<AuthService>();
      final session = context.read<Session>();
      await authService.verifyEmailAndRegister(widget.email, _codeController.text.trim());

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
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      await context.read<AuthService>().requestEmailVerification(widget.email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã gửi lại mã xác minh.')));
    } on ApiException catch (e) {
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
            TextButton(
              onPressed: _resending ? null : _resend,
              child: _resending
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Gửi lại mã'),
            ),
          ],
        ),
      ),
    );
  }
}
