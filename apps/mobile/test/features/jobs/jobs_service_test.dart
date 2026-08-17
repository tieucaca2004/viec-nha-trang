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
}
