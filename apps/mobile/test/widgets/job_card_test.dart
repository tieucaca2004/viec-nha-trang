import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viec_nha_trang/features/jobs/presentation/widgets/job_card.dart';
import 'package:viec_nha_trang/shared/models/job.dart';

Job _buildJob({bool urgent = false}) => Job.fromJson({
      'id': 'job-1',
      'title': 'Phục vụ nhà hàng',
      'employer': {'id': 'e1', 'businessName': 'Hủ Tiếu Xào A Tiểu', 'verificationLevel': 'BUSINESS_VERIFIED'},
      'salaryMin': 28000,
      'salaryMax': 32000,
      'salaryUnit': 'HOUR',
      'area': {'id': 'a1', 'name': 'Vĩnh Hải'},
      'distanceKm': 1.2,
      'employmentType': 'PART_TIME',
      'startUrgency': 'IMMEDIATE',
      'isUrgent': urgent,
      'status': 'ACTIVE',
    });

void main() {
  group('JobCard (đặc tả §8 Phase 3)', () {
    testWidgets('renders the minimum required fields', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: JobCard(job: _buildJob(), onTap: () {}, onApply: () {})),
      ));

      expect(find.text('PHỤC VỤ NHÀ HÀNG'), findsOneWidget);
      expect(find.text('Hủ Tiếu Xào A Tiểu'), findsOneWidget);
      expect(find.text('28.000–32.000đ/giờ'), findsOneWidget);
      expect(find.textContaining('Vĩnh Hải'), findsOneWidget);
      expect(find.text('🟢 Đã xác minh'), findsOneWidget);
      expect(find.text('ỨNG TUYỂN 1 CHẠM'), findsOneWidget);
    });

    testWidgets('shows the urgent badge only when isUrgent is true', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: JobCard(job: _buildJob(urgent: true), onTap: () {}, onApply: () {})),
      ));
      expect(find.textContaining('Tuyển gấp'), findsOneWidget);
    });

    testWidgets('shows ĐÃ ỨNG TUYỂN and disables the apply button when already applied (đặc tả §11)', (tester) async {
      var applyTapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: JobCard(job: _buildJob(), isApplied: true, onTap: () {}, onApply: () => applyTapped = true),
        ),
      ));

      expect(find.text('ĐÃ ỨNG TUYỂN'), findsOneWidget);
      expect(find.text('ỨNG TUYỂN 1 CHẠM'), findsNothing);

      final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(button.onPressed, isNull);
      expect(applyTapped, isFalse);
    });

    testWidgets('tapping the card triggers onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: JobCard(job: _buildJob(), onTap: () => tapped = true, onApply: () {})),
      ));

      await tester.tap(find.text('PHỤC VỤ NHÀ HÀNG'));
      expect(tapped, isTrue);
    });
  });
}
