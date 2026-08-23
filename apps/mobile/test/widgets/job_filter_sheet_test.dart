import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viec_nha_trang/features/jobs/data/jobs_service.dart';
import 'package:viec_nha_trang/features/jobs/presentation/widgets/job_filter_sheet.dart';
import 'package:viec_nha_trang/shared/models/job.dart';

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

  // Đặc tả Phase F (địa danh cũ): danh sách Area cũ (Vĩnh Hải, Lộc Thọ, ...) phải search được -
  // ô tìm kiếm chỉ hiện khi > 6 area (đủ để cần lọc), gõ đúng tên phải lọc ra đúng 1 kết quả.
  final manyAreas = [
    Area(id: 'a1', name: 'Lộc Thọ'),
    Area(id: 'a2', name: 'Tân Lập'),
    Area(id: 'a3', name: 'Phước Tiến'),
    Area(id: 'a4', name: 'Phước Tân'),
    Area(id: 'a5', name: 'Phước Long'),
    Area(id: 'a6', name: 'Phước Hải'),
    Area(id: 'a7', name: 'Vĩnh Hải'),
    Area(id: 'a8', name: 'Vĩnh Phước'),
  ];

  Future<JobFilters?> showSheetWithAreas(WidgetTester tester, {JobFilters? initial}) async {
    JobFilters? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await JobFilterSheet.show(context, initial: initial ?? JobFilters(), categories: const [], areas: manyAreas);
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('searching "Vĩnh Hải" filters the area chip list to only Vĩnh Hải', (tester) async {
    await showSheetWithAreas(tester);

    // Trước khi search: tất cả 8 area đều hiện.
    expect(find.widgetWithText(ChoiceChip, 'Lộc Thọ'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Vĩnh Hải'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Tìm phường/xã (vd: Vĩnh Hải, Lộc Thọ)'), 'Vĩnh Hải');
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ChoiceChip, 'Vĩnh Hải'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Lộc Thọ'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'Vĩnh Phước'), findsNothing);
  });

  testWidgets('searching "Lộc Thọ" filters the area chip list to only Lộc Thọ', (tester) async {
    await showSheetWithAreas(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Tìm phường/xã (vd: Vĩnh Hải, Lộc Thọ)'), 'Lộc Thọ');
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ChoiceChip, 'Lộc Thọ'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Vĩnh Hải'), findsNothing);
  });

  testWidgets('searching without diacritics ("vinh hai") still matches "Vĩnh Hải"', (tester) async {
    await showSheetWithAreas(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Tìm phường/xã (vd: Vĩnh Hải, Lộc Thọ)'), 'vinh hai');
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ChoiceChip, 'Vĩnh Hải'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Lộc Thọ'), findsNothing);
  });

  testWidgets('a search with no match shows an empty-state message, not a crash or stale list', (tester) async {
    await showSheetWithAreas(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Tìm phường/xã (vd: Vĩnh Hải, Lộc Thọ)'), 'khong-ton-tai-xyz');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Không tìm thấy khu vực phù hợp.'), findsOneWidget);
    // Không còn chip khu vực nào (các ChoiceChip khác trong sheet - Loại việc/Ca làm/Khi nào cần
    // người - không thuộc phạm vi search này nên vẫn hiện bình thường, không kiểm tra ở đây).
    for (final area in manyAreas) {
      expect(find.widgetWithText(ChoiceChip, area.name), findsNothing);
    }
  });

  testWidgets('tapping the 20km chip and applying returns radiusKm=20 in JobFilters', (tester) async {
    JobFilters? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await JobFilterSheet.show(context, initial: JobFilters(), categories: const [], areas: manyAreas);
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, '20 km'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ÁP DỤNG'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.radiusKm, 20.0);
  });

  testWidgets('tapping the 30km chip and applying returns radiusKm=30 in JobFilters', (tester) async {
    JobFilters? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await JobFilterSheet.show(context, initial: JobFilters(), categories: const [], areas: manyAreas);
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, '30 km'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ÁP DỤNG'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.radiusKm, 30.0);
  });

  testWidgets('selecting an area AND a radius together are not mutually exclusive - both land on the result', (tester) async {
    JobFilters? result;
    // GPS lat/lng đã có sẵn từ HomeScreen._useMyLocation() trước khi mở sheet (mô phỏng ở đây
    // bằng initial filters có sẵn latitude/longitude) - JobFilterSheet chỉ set thêm areaId +
    // radiusKm, không được xoá mất lat/lng đã có.
    final initial = JobFilters()
      ..latitude = 12.25
      ..longitude = 109.19;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await JobFilterSheet.show(context, initial: initial, categories: const [], areas: manyAreas);
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Chọn "20 km" trước (nằm ở đầu sheet, luôn sẵn trong viewport) rồi mới cuộn xuống chọn khu
    // vực - tránh việc cuộn xuống Khu vực làm "20 km" bị cuộn ra khỏi viewport trước khi tap.
    await tester.tap(find.widgetWithText(ChoiceChip, '20 km'));
    await tester.pumpAndSettle();
    // ListView nằm trong DraggableScrollableSheet - drag gesture trên nó có thể bị chính
    // DraggableScrollableSheet "nuốt" để đổi kích thước sheet thay vì cuộn nội dung (khác hẳn
    // ListView thường trong Scaffold ở các màn khác). Nhảy thẳng scroll offset qua controller,
    // tăng dần tới khi thấy 'Vĩnh Hải' - tránh nhảy thẳng maxScrollExtent (có thể cuộn quá xa,
    // đẩy 'Khu vực' ra khỏi viewport phía trên do ListView chỉ build lazy quanh viewport).
    final listViewController = tester.widget<ListView>(find.byType(ListView)).controller!;
    for (var fraction = 0.15; fraction <= 1.0; fraction += 0.15) {
      listViewController.jumpTo(listViewController.position.maxScrollExtent * fraction);
      await tester.pumpAndSettle();
      if (find.widgetWithText(ChoiceChip, 'Vĩnh Hải').evaluate().isNotEmpty) break;
    }
    await tester.tap(find.widgetWithText(ChoiceChip, 'Vĩnh Hải'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ÁP DỤNG'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.areaId, 'a7');
    expect(result!.radiusKm, 20.0);
    expect(result!.latitude, 12.25);
    expect(result!.longitude, 109.19);
  });
}
