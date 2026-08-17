import 'package:flutter_test/flutter_test.dart';
import 'package:viec_nha_trang/shared/models/job.dart';

void main() {
  group('Job (đặc tả §8 Phase 3: Job Card fields)', () {
    test('fromJson parses nested employer/area and formats salary with thousands separators', () {
      final job = Job.fromJson({
        'id': 'job-1',
        'title': 'Phục vụ nhà hàng',
        'employer': {
          'id': 'emp-1',
          'businessName': 'Hủ Tiếu Xào A Tiểu',
          'verificationLevel': 'BUSINESS_VERIFIED',
          'ratingAvg': 4.5,
          'ratingCount': 10,
          'hiredCount': 20,
        },
        'salaryMin': 28000,
        'salaryMax': 32000,
        'salaryUnit': 'HOUR',
        'area': {'id': 'area-1', 'name': 'Vĩnh Hải'},
        'distanceKm': 1.2,
        'employmentType': 'PART_TIME',
        'startUrgency': 'IMMEDIATE',
        'isUrgent': true,
        'status': 'ACTIVE',
      });

      expect(job.title, 'Phục vụ nhà hàng');
      expect(job.employer!.businessName, 'Hủ Tiếu Xào A Tiểu');
      expect(job.employer!.isVerified, isTrue);
      expect(job.area!.name, 'Vĩnh Hải');
      expect(job.salaryLabel, '28.000–32.000đ/giờ');
      expect(job.isUrgent, isTrue);
    });

    test('handles missing optional fields without throwing (empty state safety, đặc tả §25)', () {
      final job = Job.fromJson({'id': 'job-2', 'salaryMin': 0, 'salaryMax': 0});
      expect(job.employer, isNull);
      expect(job.area, isNull);
      expect(job.title, '');
    });

    test('Employer.isVerified is false for UNVERIFIED level', () {
      final employer = Employer.fromJson({'id': 'e1', 'businessName': 'X', 'verificationLevel': 'UNVERIFIED'});
      expect(employer.isVerified, isFalse);
    });
  });
}
