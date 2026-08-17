import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:viec_nha_trang/core/auth/session.dart';
import 'package:viec_nha_trang/core/network/api_client.dart';
import 'package:viec_nha_trang/features/saved_jobs/data/saved_jobs_service.dart';
import '../../helpers/in_memory_token_storage.dart';
import '../../helpers/json_response.dart';

void main() {
  group('SavedJobsService (đặc tả §14 Phase 3: lưu/bỏ lưu job)', () {
    test('save() POSTs to /saved-jobs/:jobId', () async {
      final session = Session(storage: InMemoryTokenStorage());
      String? method;
      Uri? uri;
      final api = ApiClient(
        session,
        httpClient: MockClient((request) async {
          method = request.method;
          uri = request.url;
          return jsonResponse(null, 201);
        }),
      );

      await SavedJobsService(api).save('job-1');
      expect(method, 'POST');
      expect(uri!.path, endsWith('/saved-jobs/job-1'));
    });

    test('unsave() DELETEs to /saved-jobs/:jobId', () async {
      final session = Session(storage: InMemoryTokenStorage());
      String? method;
      final api = ApiClient(
        session,
        httpClient: MockClient((request) async {
          method = request.method;
          return jsonResponse(null, 200);
        }),
      );

      await SavedJobsService(api).unsave('job-1');
      expect(method, 'DELETE');
    });

    test('listSaved() parses the saved jobs list', () async {
      final session = Session(storage: InMemoryTokenStorage());
      final api = ApiClient(
        session,
        httpClient: MockClient((request) async {
          return jsonResponse([
            {
              'jobId': 'job-1',
              'job': {'id': 'job-1', 'title': 'Phục vụ'},
            },
          ], 200);
        }),
      );

      final saved = await SavedJobsService(api).listSaved();
      expect(saved, hasLength(1));
      expect(saved.first['job']['title'], 'Phục vụ');
    });
  });
}
