import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/auth/session.dart';
import '../../../shared/widgets/auth_prompt.dart';
import '../../../shared/widgets/main_nav_scaffold.dart';
import '../../auth/data/auth_service.dart';
import 'post_job_wizard_screen.dart';

/// Điểm vào cho nhà tuyển dụng CHƯA có tài khoản (đặc tả AUTH UX Part 4) - cho xem thông tin
/// (cách hoạt động) TRƯỚC, chỉ hỏi xác thực đúng lúc họ bấm bắt đầu đăng tin - không bắt xác thực
/// chỉ để xem app hoạt động ra sao.
class EmployerEntryScreen extends StatefulWidget {
  const EmployerEntryScreen({super.key});

  @override
  State<EmployerEntryScreen> createState() => _EmployerEntryScreenState();
}

class _EmployerEntryScreenState extends State<EmployerEntryScreen> {
  bool _starting = false;

  Future<void> _startPosting() async {
    setState(() => _starting = true);
    try {
      final session = context.read<Session>();
      // Khách chưa có tài khoản: cho CHỌN đăng ký (email + email OTP) hay đăng nhập - không ép
      // xác thực SĐT ở bước này (phone verification là yêu cầu riêng của backend khi thực sự tạo
      // tin, PostJobWizardScreen đã tự xử lý qua showPhoneVerificationSheet).
      if (!session.isLoggedIn) {
        final ok = await requireAuthentication(
          context,
          reason: 'Để đăng tin tuyển dụng, bạn cần đăng nhập hoặc tạo tài khoản.',
          intendedRole: 'EMPLOYER',
        );
        if (!ok || !mounted) return;
      }

      final authService = context.read<AuthService>();
      if (!session.isEmployer) {
        await authService.becomeEmployer();
      }
      await session.setActiveRole('EMPLOYER');

      // Đi THẲNG vào wizard đăng tin - đúng việc người dùng vừa bấm, không quay lại Home/nav rồi
      // bắt họ tìm nút đăng tin lần nữa. Xong wizard mới đưa về nav của nhà tuyển dụng.
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PostJobWizardScreen()),
      );

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainNavScaffold()),
        (route) => route.isFirst,
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tuyển người')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.storefront, size: 56, color: Color(0xFF0F9D58)),
              const SizedBox(height: 16),
              const Text(
                'Đăng tin tuyển dụng nhanh chóng',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const _HowItWorksStep(number: '1', text: 'Đăng tin miễn phí, mô tả công việc rõ ràng.'),
              const _HowItWorksStep(number: '2', text: 'Ứng viên phù hợp trong khu vực Nha Trang ứng tuyển trực tiếp.'),
              const _HowItWorksStep(number: '3', text: 'Gọi điện hoặc nhắn Zalo để trao đổi và tuyển người.'),
              const Spacer(),
              FilledButton(
                onPressed: _starting ? null : _startPosting,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
                child: _starting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('ĐĂNG TIN NGAY', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HowItWorksStep extends StatelessWidget {
  final String number;
  final String text;
  const _HowItWorksStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 14, child: Text(number, style: const TextStyle(fontSize: 13))),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 15))),
        ],
      ),
    );
  }
}
