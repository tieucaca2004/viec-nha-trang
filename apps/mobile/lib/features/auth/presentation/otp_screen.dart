import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/auth_service.dart';
import '../../../core/auth/session.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/main_nav_scaffold.dart';

class OtpScreen extends StatefulWidget {
  final String phone;
  final String intendedRole;
  const OtpScreen({super.key, required this.phone, this.intendedRole = 'JOB_SEEKER'});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _codeController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final authService = context.read<AuthService>();
      final session = context.read<Session>();
      await authService.verifyOtp(widget.phone, _codeController.text.trim());

      // Ý định ban đầu chọn ở onboarding (đặc tả §6) - nếu chọn "Tuyển người" và tài khoản
      // chưa có vai trò EMPLOYER, thêm vai trò đó (không tạo tài khoản mới, đặc tả §5 gốc).
      if (widget.intendedRole == 'EMPLOYER' && !session.isEmployer) {
        await authService.becomeEmployer();
      }
      await session.setActiveRole(widget.intendedRole);

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainNavScaffold()),
        (route) => false,
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
      appBar: AppBar(title: const Text('Xác thực OTP')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nhập mã OTP gửi tới ${widget.phone}', style: const TextStyle(fontSize: 16)),
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
          ],
        ),
      ),
    );
  }
}
