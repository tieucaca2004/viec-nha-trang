import 'job.dart';

/// Trạng thái theo state machine ở đặc tả mục 16.
class JobApplication {
  final String id;
  final String status;
  final int? matchScore;
  final Job? job;
  final DateTime? createdAt;

  JobApplication({required this.id, required this.status, this.matchScore, this.job, this.createdAt});

  static const statusLabels = {
    'NEW': 'Mới',
    'VIEWED': 'Đã xem',
    'CONTACTED': 'Đã liên hệ',
    'INTERVIEW': 'Phỏng vấn',
    'HIRED': 'Đã nhận',
    'NOT_SUITABLE': 'Không phù hợp',
    'NO_SHOW': 'Ứng viên không đến',
  };

  String get statusLabel => statusLabels[status] ?? status;

  factory JobApplication.fromJson(Map<String, dynamic> json) => JobApplication(
        id: json['id'],
        status: json['status'] ?? 'NEW',
        matchScore: json['matchScore'],
        job: json['job'] != null ? Job.fromJson(json['job']) : null,
        createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt']) : null,
      );
}
