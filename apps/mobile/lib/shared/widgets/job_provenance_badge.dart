import 'package:flutter/material.dart';
import '../models/job.dart';

/// Nhãn nguồn dữ liệu (đặc tả JobHunter Phần 11): SYNTHETIC hiển thị "Dữ liệu mẫu"/"Tin mẫu" -
/// KHÔNG BAO GIỜ được giả vờ là tin thật; IMPORTED hiển thị "Nguồn: X" + ngày đăng/cập nhật (nếu
/// biết) - không bịa ngày nếu backend trả null. USER_CREATED không hiển thị gì (tin bình thường).
class JobProvenanceBadge extends StatelessWidget {
  final Job job;
  const JobProvenanceBadge({super.key, required this.job});

  @override
  Widget build(BuildContext context) {
    if (job.isSynthetic) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(6)),
        child: Text(
          'Tin mẫu',
          style: TextStyle(color: Colors.purple.shade700, fontSize: 11, fontWeight: FontWeight.w600),
        ),
      );
    }

    if (job.isImported) {
      return Text(
        _importedLabel(),
        style: const TextStyle(color: Colors.black45, fontSize: 12),
      );
    }

    return const SizedBox.shrink();
  }

  String _importedLabel() {
    final source = job.sourceName ?? 'nguồn ngoài';
    final dateLabel = _formatDateLabel();
    return dateLabel != null ? 'Nguồn: $source · $dateLabel' : 'Nguồn: $source';
  }

  String? _formatDateLabel() {
    if (job.sourceUpdatedAt != null) return 'Cập nhật ${_formatDate(job.sourceUpdatedAt!)}';
    if (job.sourcePublishedAt != null) {
      final days = DateTime.now().difference(job.sourcePublishedAt!).inDays;
      if (days <= 0) return 'Mới hôm nay';
      return 'Đăng $days ngày trước';
    }
    return null; // Không rõ ngày - không hiển thị ngày bịa.
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
