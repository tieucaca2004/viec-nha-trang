class JobCategory {
  final String id;
  final String name;
  final String? icon;

  JobCategory({required this.id, required this.name, this.icon});

  factory JobCategory.fromJson(Map<String, dynamic> json) =>
      JobCategory(id: json['id'], name: json['name'], icon: json['icon']);
}

class Area {
  final String id;
  final String name;

  Area({required this.id, required this.name});

  factory Area.fromJson(Map<String, dynamic> json) => Area(id: json['id'], name: json['name']);
}

class Employer {
  final String id;
  final String businessName;
  final String? logoUrl;
  final String verificationLevel;
  final double ratingAvg;
  final int ratingCount;
  final int hiredCount;

  Employer({
    required this.id,
    required this.businessName,
    this.logoUrl,
    required this.verificationLevel,
    required this.ratingAvg,
    required this.ratingCount,
    required this.hiredCount,
  });

  bool get isVerified => verificationLevel != 'UNVERIFIED';

  factory Employer.fromJson(Map<String, dynamic> json) => Employer(
        id: json['id'],
        businessName: json['businessName'] ?? '',
        logoUrl: json['logoUrl'],
        verificationLevel: json['verificationLevel'] ?? 'UNVERIFIED',
        ratingAvg: (json['ratingAvg'] ?? 0).toDouble(),
        ratingCount: json['ratingCount'] ?? 0,
        hiredCount: json['hiredCount'] ?? 0,
      );
}

/// Đại diện 1 tin tuyển dụng - trường tối thiểu hiển thị trên Job Card (đặc tả mục 6).
class Job {
  final String id;
  final String title;
  final Employer? employer;
  final int salaryMin;
  final int salaryMax;
  final String salaryUnit;
  final String? shiftStartTime;
  final String? shiftEndTime;
  final Area? area;
  final double? distanceKm;
  final String employmentType;
  final String startUrgency;
  final bool isUrgent;
  final String status;
  final DateTime? publishedAt;
  // Provenance (đặc tả JobHunter Phần 11) - USER_CREATED không hiển thị gì khác thường lệ;
  // SYNTHETIC hiển thị nhãn "Dữ liệu mẫu"/"Tin mẫu"; IMPORTED hiển thị "Nguồn: X" + ngày.
  final String sourceType;
  final String? sourceName;
  final DateTime? sourcePublishedAt;
  final DateTime? sourceUpdatedAt;

  Job({
    required this.id,
    required this.title,
    this.employer,
    required this.salaryMin,
    required this.salaryMax,
    required this.salaryUnit,
    this.shiftStartTime,
    this.shiftEndTime,
    this.area,
    this.distanceKm,
    required this.employmentType,
    required this.startUrgency,
    required this.isUrgent,
    required this.status,
    this.publishedAt,
    this.sourceType = 'USER_CREATED',
    this.sourceName,
    this.sourcePublishedAt,
    this.sourceUpdatedAt,
  });

  bool get isSynthetic => sourceType == 'SYNTHETIC';
  bool get isImported => sourceType == 'IMPORTED';

  String get salaryLabel {
    final unitLabel = {'HOUR': '/giờ', 'DAY': '/ngày', 'MONTH': '/tháng', 'SHIFT': '/ca'}[salaryUnit] ?? '';
    return '${_formatMoney(salaryMin)}–${_formatMoney(salaryMax)}đ$unitLabel';
  }

  static String _formatMoney(int value) {
    final s = value.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  factory Job.fromJson(Map<String, dynamic> json) => Job(
        id: json['id'],
        title: json['title'] ?? '',
        employer: json['employer'] != null ? Employer.fromJson(json['employer']) : null,
        salaryMin: json['salaryMin'] ?? 0,
        salaryMax: json['salaryMax'] ?? 0,
        salaryUnit: json['salaryUnit'] ?? 'HOUR',
        shiftStartTime: json['shiftStartTime'],
        shiftEndTime: json['shiftEndTime'],
        area: json['area'] != null ? Area.fromJson(json['area']) : null,
        distanceKm: (json['distanceKm'] as num?)?.toDouble(),
        employmentType: json['employmentType'] ?? 'PART_TIME',
        startUrgency: json['startUrgency'] ?? 'NOT_URGENT',
        isUrgent: json['isUrgent'] ?? false,
        status: json['status'] ?? 'ACTIVE',
        publishedAt: json['publishedAt'] != null ? DateTime.tryParse(json['publishedAt']) : null,
        sourceType: json['sourceType'] ?? 'USER_CREATED',
        sourceName: json['sourceName'],
        sourcePublishedAt: json['sourcePublishedAt'] != null ? DateTime.tryParse(json['sourcePublishedAt']) : null,
        sourceUpdatedAt: json['sourceUpdatedAt'] != null ? DateTime.tryParse(json['sourceUpdatedAt']) : null,
      );
}
