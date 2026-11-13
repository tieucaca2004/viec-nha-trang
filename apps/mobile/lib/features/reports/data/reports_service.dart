import '../../../core/network/api_client.dart';

/// Báo cáo tin tuyển dụng (đặc tả mục 22). Phase này chỉ dùng targetType JOB - backend còn nhận
/// REVIEW/USER (CreateReportDto ở apps/backend/src/reports/reports.module.ts) nhưng mobile chưa có
/// màn hình nào cần tới.
class ReportsService {
  final ApiClient api;
  ReportsService(this.api);

  /// Đúng thứ tự và đủ 9 giá trị enum ReportReason trong prisma/schema.prisma.
  static const jobReasonLabels = <String, String>{
    'FAKE_JOB': 'Tin tuyển dụng giả',
    'SCAM': 'Có dấu hiệu lừa đảo',
    'WRONG_SALARY': 'Lương không đúng thực tế',
    'WRONG_LOCATION': 'Sai địa điểm làm việc',
    'MISMATCHED_DESCRIPTION': 'Mô tả không đúng công việc thực tế',
    'CHARGES_FEE_FROM_CANDIDATE': 'Thu phí người ứng tuyển',
    'INAPPROPRIATE_CONTENT': 'Nội dung không phù hợp',
    'SPAM': 'Tin rác / spam',
    'OTHER': 'Lý do khác',
  };

  Future<Map<String, dynamic>> reportJob({required String jobId, required String reason, String? note}) async {
    final res = await api.post('/reports', body: {
      'targetType': 'JOB',
      'jobId': jobId,
      'reason': reason,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
    return res as Map<String, dynamic>;
  }
}
