import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_exception.dart';
import '../../features/auth/data/auth_service.dart';

/// Sheet xác minh số điện thoại (đặc tả §3) - dùng khi backend từ chối 1 hành động quan trọng
/// (ứng tuyển/đăng tuyển) với message 'PHONE_NOT_VERIFIED'. KHÔNG gửi SMS lúc đăng ký tài khoản -
/// chỉ gửi khi thật sự cần, ngay tại đây. Trả về `true` nếu xác minh thành công, `false`/`null`
/// nếu người dùng huỷ.
Future<bool?> showPhoneVerificationSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _PhoneVerificationSheetContent(),
  );
}

class _PhoneVerificationSheetContent extends StatefulWidget {
  const _PhoneVerificationSheetContent();

  @override
  State<_PhoneVerificationSheetContent> createState() => _PhoneVerificationSheetContentState();
}

class _PhoneVerificationSheetContentState extends State<_PhoneVerificationSheetContent> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  bool _codeSent = false;
  bool _loading = false;
  String? _error;

  Future<void> _sendCode() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<AuthService>().requestPhoneLink(_phoneController.text.trim());
      if (!mounted) return;
      setState(() => _codeSent = true);
    } on ApiException catch (e) {
      setState(() => _error = e.userMessage);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verify() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<AuthService>().verifyPhoneLink(_phoneController.text.trim(), _codeController.text.trim());
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.userMessage);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Xác minh số điện thoại', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'Cần xác minh số điện thoại trước khi tiếp tục.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phoneController,
            enabled: !_codeSent,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Số điện thoại', hintText: '09xxxxxxxx', border: OutlineInputBorder()),
          ),
          if (_codeSent) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(labelText: 'Mã OTP', border: OutlineInputBorder()),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _loading ? null : (_codeSent ? _verify : _sendCode),
            child: _loading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_codeSent ? 'XÁC NHẬN' : 'GỬI MÃ OTP'),
          ),
        ],
      ),
    );
  }
}
