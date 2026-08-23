import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:viec_nha_trang/core/auth/session.dart';
import 'package:viec_nha_trang/core/network/api_client.dart';
import 'package:viec_nha_trang/features/jobs/data/jobs_service.dart';
import '../../helpers/in_memory_token_storage.dart';
import '../../helpers/json_response.dart';

void main() {
  group('JobsService.search (đặc tả §9 Phase 3: search + filter + pagination)', () {
    test('sends filters as query params and parses paginated response', () async {
      final session = Session(storage: InMemoryTokenStorage());
      late Uri capturedUri;
      final api = ApiClient(
        session,
        httpClient: MockClient((request) async {
          capturedUri = request.url;
          return jsonResponse({
            'data': [
              {
                'id': 'job-1',
                'title': 'Phục vụ nhà hàng',
                'salaryMin': 28000,
                'salaryMax': 32000,
                'salaryUnit': 'HOUR',
                'employmentType': 'PART_TIME',
                'startUrgency': 'IMMEDIATE',
                'isUrgent': true,
                'status': 'ACTIVE',
              },
            ],
            'meta': {'total': 42, 'limit': 20, 'offset': 0},
          }, 200);
        }),
      );

      final filters = JobFilters()
        ..keyword = 'phục vụ'
        ..categoryId = 'cat-1'
        ..employmentType = 'PART_TIME'
        ..isUrgent = true;

      final result = await JobsService(api).search(filters, limit: 20, offset: 0);

      expect(capturedUri.queryParameters['keyword'], 'phục vụ');
      expect(capturedUri.queryParameters['categoryId'], 'cat-1');
      expect(capturedUri.queryParameters['employmentType'], 'PART_TIME');
      expect(capturedUri.queryParameters['isUrgent'], 'true');
      expect(capturedUri.queryParameters['limit'], '20');

      expect(result.jobs, hasLength(1));
      expect(result.jobs.first.title, 'Phục vụ nhà hàng');
      expect(result.total, 42);
      expect(result.hasMore, isTrue); // 1 job loaded so far out of 42 total
    });

    test('JobFilters.copy() produces an independent copy (không ảnh hưởng bộ lọc gốc khi mở filter sheet)', () {
      final original = JobFilters()..keyword = 'a';
      final copy = original.copy()..keyword = 'b';
      expect(original.keyword, 'a');
      expect(copy.keyword, 'b');
    });

    test('sends salaryMin/salaryMax as real query params (sửa lỗi High #9 FULL AUDIT)', () async {
      final session = Session(storage: InMemoryTokenStorage());
      late Uri capturedUri;
      final api = ApiClient(
        session,
        httpClient: MockClient((request) async {
          capturedUri = request.url;
          return jsonResponse({
            'data': <dynamic>[],
            'meta': {'total': 0, 'limit': 20, 'offset': 0},
          }, 200);
        }),
      );

      final filters = JobFilters()
        ..salaryMin = 25000
        ..salaryMax = 50000;

      await JobsService(api).search(filters, limit: 20, offset: 0);

      expect(capturedUri.queryParameters['salaryMin'], '25000');
      expect(capturedUri.queryParameters['salaryMax'], '50000');
    });

    test('JobFilters.copy() carries salaryMin/salaryMax independently', () {
      final original = JobFilters()
        ..salaryMin = 20000
        ..salaryMax = 40000;
      final copy = original.copy()..salaryMax = 60000;
      expect(original.salaryMax, 40000);
      expect(copy.salaryMin, 20000);
      expect(copy.salaryMax, 60000);
    });
  });

  // Regression cho lỗi "Chưa có dữ liệu khu vực." dù backend đã có Area (JobsService là
  // session-lifetime singleton qua ProxyProvider - trước đây _areasCache dùng containsKey() nên
  // 1 lần trả [] bị cache VĨNH VIỄN suốt phiên app, không màn hình/nút THỬ LẠI nào recover được).
  group('JobsService.areas() cache (fix "Chưa có dữ liệu khu vực" dù backend có data)', () {
    ApiClient apiReturning(List<dynamic> Function() responses) {
      final session = Session(storage: InMemoryTokenStorage());
      return ApiClient(
        session,
        httpClient: MockClient((request) async => jsonResponse(responses(), 200)),
      );
    }

    // TEST A: API areas trả về 15 khu vực -> lần gọi trả đúng 15 khu vực.
    test('TEST A: trả đủ danh sách khi API có data', () async {
      final areas = List.generate(15, (i) => {'id': 'area-$i', 'name': 'Khu vực $i'});
      final api = apiReturning(() => areas);
      final result = await JobsService(api).areas();
      expect(result, hasLength(15));
    });

    // TEST B: API areas trả về [] -> service trả về [] (UI tự quyết định hiển thị "Chưa có dữ
    // liệu khu vực." dựa trên list rỗng này - không phải lỗi service).
    test('TEST B: trả về rỗng khi API trả về rỗng', () async {
      final api = apiReturning(() => []);
      final result = await JobsService(api).areas();
      expect(result, isEmpty);
    });

    // TEST D (bug chính đã fix): API trả [] ở lần gọi đầu (vd timing race lúc khởi động), sau đó
    // backend có data thật -> lần gọi tiếp theo (không cần forceRefresh) PHẢI trả về data mới,
    // KHÔNG được kẹt ở cache rỗng vĩnh viễn.
    test('TEST D: KHÔNG cache kết quả rỗng - lần gọi sau tự động lấy được data khi backend đã có', () async {
      var callCount = 0;
      final session = Session(storage: InMemoryTokenStorage());
      final api = ApiClient(
        session,
        httpClient: MockClient((request) async {
          callCount++;
          if (callCount == 1) return jsonResponse([], 200);
          return jsonResponse([
            {'id': 'area-1', 'name': 'Vĩnh Hải'},
          ], 200);
        }),
      );
      final service = JobsService(api);

      final first = await service.areas();
      expect(first, isEmpty);

      // Gọi lại KHÔNG truyền forceRefresh (đúng như 3 call site thật trong app) - phải gọi lại
      // API vì lần trước rỗng không được cache, chứ không được trả cache rỗng cũ.
      final second = await service.areas();
      expect(second, hasLength(1));
      expect(second.first.name, 'Vĩnh Hải');
      expect(callCount, 2);
    });

    // Đối chứng: kết quả KHÔNG rỗng thì VẪN được cache như cũ (không gọi lại API lần 2) - đảm bảo
    // fix không làm mất tối ưu cache hợp lệ đặc tả hotfix §5.
    test('data hợp lệ vẫn được cache bình thường (không gọi lại API khi đã có data)', () async {
      var callCount = 0;
      final session = Session(storage: InMemoryTokenStorage());
      final api = ApiClient(
        session,
        httpClient: MockClient((request) async {
          callCount++;
          return jsonResponse([
            {'id': 'area-1', 'name': 'Vĩnh Hải'},
          ], 200);
        }),
      );
      final service = JobsService(api);
      await service.areas();
      await service.areas();
      expect(callCount, 1);
    });
  });
}
