import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viec_nha_trang/features/jobs/data/jobs_service.dart';
import 'package:viec_nha_trang/features/jobs/presentation/widgets/job_filter_sheet.dart';

/// Sửa lỗi High #9 (FULL AUDIT): trước đây JobFilterSheet không có filter lương dù có trong đặc
/// tả §10. Test này chứng minh nhập lương min/max rồi bấm ÁP DỤNG trả về đúng JobFilters, và bấm
/// XÓA BỘ LỌC trả về bộ lọc rỗng (bao gồm cả lương).
void main() {
  Future<JobFilters?> showSheet(WidgetTester tester, {JobFilters? initial}) async {
    JobFilters? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await JobFilterSheet.show(context, initial: initial ?? JobFilters(), categories: const [], areas: const []);
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('applying with empty salary fields leaves salaryMin/salaryMax as null', (tester) async {
    JobFilters? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await JobFilterSheet.show(context, initial: JobFilters(), categories: const [], areas: const []);
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ÁP DỤNG'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.salaryMin, isNull);
    expect(result!.salaryMax, isNull);
  });

  testWidgets('applying with salary min/max filled returns them on the JobFilters result', (tester) async {
    JobFilters? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await JobFilterSheet.show(context, initial: JobFilters(), categories: const [], areas: const []);
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Từ'), '25000');
    await tester.enterText(find.widgetWithText(TextField, 'Đến'), '50000');
    await tester.pumpAndSettle();

    await tester.tap(find.text('ÁP DỤNG'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.salaryMin, 25000);
    expect(result!.salaryMax, 50000);
  });

  testWidgets('XÓA BỘ LỌC returns a fresh JobFilters with no salary set, even if an initial one had values', (tester) async {
    JobFilters? result;
    final initial = JobFilters()
      ..salaryMin = 10000
      ..salaryMax = 20000;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await JobFilterSheet.show(context, initial: initial, categories: const [], areas: const []);
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('XÓA BỘ LỌC'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.salaryMin, isNull);
    expect(result!.salaryMax, isNull);
  });

  testWidgets('pre-fills the salary fields from the initial JobFilters', (tester) async {
    final initial = JobFilters()
      ..salaryMin = 15000
      ..salaryMax = 30000;
    await showSheet(tester, initial: initial);

    expect(find.widgetWithText(TextField, '15000'), findsOneWidget);
    expect(find.widgetWithText(TextField, '30000'), findsOneWidget);
  });
}
