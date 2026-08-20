import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/auth_service.dart';
import '../../../core/network/api_exception.dart';
import 'otp_screen.dart';

/// Đăng nhập bằng SĐT + OTP (đặc tả §5 Phase 3).
class PhoneLoginScreen extends StatefulWidget {
  final String intendedRole;
  // Chế độ "xác thực theo ngữ cảnh" (đặc tả AUTH UX Part 6) - khi true, sau khi OTP đúng chỉ pop
  // về đúng 1 lần với kết quả true (KHÔNG điều hướng sang MainNavScaffold) để caller (vd. màn chi
  // tiết việc) tự tiếp tục hành động ban đầu (ứng tuyển/lưu việc), không mất ngữ cảnh, không bị đá
  // về Home. Mặc định false = hành vi đăng nhập bình thường (vào thẳng MainNavScaffold).
  final bool returnOnSuccess;
  const PhoneLoginScreen({super.key, this.intendedRole = 'JOB_SEEKER', this.returnOnSuccess = false});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final _phoneController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final authService = context.read<AuthService>();
      await authService.requestOtp(_phoneController.text.trim());
      if (!mounted) return;
      final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => OtpScreen(
            phone: _phoneController.text.trim(),
            intendedRole: widget.intendedRole,
            returnOnSuccess: widget.returnOnSuccess,
          ),
        ),
      );
      // Xác thực theo ngữ cảnh (Part 6): OTP đúng ở chế độ returnOnSuccess chỉ pop OtpScreen với
      // true - lan truyền tiếp 1 lần pop nữa để đóng luôn màn nhập SĐT này, trả kết quả về đúng
      // nơi đã gọi requireAuthentication().
      if (widget.returnOnSuccess && result == true && mounted) {
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (e) {
      setState(() => _error = e.userMessage);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Đặc tả Part 8: dùng ngôn ngữ "xác thực" thay vì khái niệm "đăng nhập" khi đây là 1 bước
      // xác thực theo ngữ cảnh (guest thực hiện hành động cần tài khoản), không phải màn đăng
      // nhập độc lập đầu tiên của app.
      appBar: AppBar(title: Text(widget.returnOnSuccess ? 'Xác thực số điện thoại' : 'Đăng nhập')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('VIỆC NHA TRANG', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(fontSize: 18),
                decoration: const InputDecoration(
                  labelText: 'Số điện thoại',
                  hintText: '09xxxxxxxx',
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
                    : const Text('GỬI MÃ OTP', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
