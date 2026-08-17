import 'package:flutter/material.dart';
import '../../core/network/api_exception.dart';

/// Trạng thái chuẩn cho mọi màn hình gọi API: loading / success / empty / error (§25).
/// Không bao giờ để màn hình trắng khi lỗi - luôn có message + nút "Thử lại".
class AsyncStateView<T> extends StatelessWidget {
  final bool loading;
  final Object? error;
  final T? data;
  final bool Function(T data)? isEmpty;
  final String emptyMessage;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback onRetry;

  const AsyncStateView({
    super.key,
    required this.loading,
    required this.error,
    required this.data,
    required this.builder,
    required this.onRetry,
    this.isEmpty,
    this.emptyMessage = 'Chưa có dữ liệu.',
  });

  @override
  Widget build(BuildContext context) {
    if (loading && data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && data == null) {
      final message = error is ApiException ? (error as ApiException).userMessage : 'Đã có lỗi xảy ra. Vui lòng thử lại.';
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40, color: Colors.grey),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('THỬ LẠI')),
            ],
          ),
        ),
      );
    }
    if (data == null || (isEmpty?.call(data as T) ?? false)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(emptyMessage, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
        ),
      );
    }
    return builder(context, data as T);
  }
}
