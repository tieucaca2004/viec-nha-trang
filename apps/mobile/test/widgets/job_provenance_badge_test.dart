import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viec_nha_trang/shared/models/job.dart';
import 'package:viec_nha_trang/shared/widgets/job_provenance_badge.dart';

/// Đặc tả JobHunter Phần 11: SYNTHETIC hiển thị "Tin mẫu", IMPORTED hiển thị "Nguồn: X" + ngày
/// (hoặc không có ngày nếu backend trả null - KHÔNG bịa), USER_CREATED không hiển thị gì.
Job _job({
  required String sourceType,
  String? sourceName,
  DateTime? sourcePublishedAt,
  DateTime? sourceUpdatedAt,
}) {
  return Job(
    id: 'job-1',
    title: 'Test job',
    salaryMin: 0,
    salaryMax: 0,
    salaryUnit: 'MONTH',
    employmentType: 'FULL_TIME',
    startUrgency: 'NOT_URGENT',
    isUrgent: false,
    status: 'ACTIVE',
    sourceType: sourceType,
    sourceName: sourceName,
    sourcePublishedAt: sourcePublishedAt,
    sourceUpdatedAt: sourceUpdatedAt,
  );
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('SYNTHETIC hiển thị nhãn "Tin mẫu"', (tester) async {
    await tester.pumpWidget(_wrap(JobProvenanceBadge(job: _job(sourceType: 'SYNTHETIC'))));
    expect(find.text('Tin mẫu'), findsOneWidget);
  });

  testWidgets('IMPORTED có sourceUpdatedAt => hiển thị "Nguồn: X · Cập nhật DD/MM/YYYY"', (tester) async {
    await tester.pumpWidget(_wrap(JobProvenanceBadge(
      job: _job(sourceType: 'IMPORTED', sourceName: 'careerviet', sourceUpdatedAt: DateTime(2026, 8, 5)),
    )));
    expect(find.text('Nguồn: careerviet · Cập nhật 05/08/2026'), findsOneWidget);
  });

  testWidgets('IMPORTED không có ngày nào => chỉ hiển thị "Nguồn: X", KHÔNG bịa ngày', (tester) async {
    await tester.pumpWidget(_wrap(JobProvenanceBadge(job: _job(sourceType: 'IMPORTED', sourceName: 'topcv'))));
    expect(find.text('Nguồn: topcv'), findsOneWidget);
  });

  testWidgets('USER_CREATED không hiển thị badge nào', (tester) async {
    await tester.pumpWidget(_wrap(JobProvenanceBadge(job: _job(sourceType: 'USER_CREATED'))));
    expect(find.text('Tin mẫu'), findsNothing);
    expect(find.textContaining('Nguồn:'), findsNothing);
  });
}
