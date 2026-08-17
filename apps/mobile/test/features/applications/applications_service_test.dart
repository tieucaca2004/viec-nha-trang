import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:viec_nha_trang/core/auth/session.dart';
import 'package:viec_nha_trang/core/network/api_client.dart';
import 'package:viec_nha_trang/features/applications/data/applications_service.dart';
import '../../helpers/in_memory_token_storage.dart';
import '../../helpers/json_response.dart';

void main() {
  group('ApplicationsService (đặc tả §12/§13 Phase 3: ứng tuyển 1 chạm, theo dõi trạng thái)', () {
    test('apply() posts to /jobs/:id/apply and returns the created application', () async {
      final session = Session(storage: InMemoryTokenStorage());
      Uri? capturedUri;
      final api = ApiClient(
        session,
        httpClient: MockClient((request) async {
          capturedUri = request.url;
          return jsonResponse({'id': 'app-1', 'jobId': 'job-1', 'status': 'NEW'}, 201);
        }),
      );

      final application = await ApplicationsService(api).apply('job-1');

      expect(capturedUri!.path, endsWith('/jobs/job-1/apply'));
      expect(application.id, 'app-1');
      expect(application.status, 'NEW');
    });

    test('listMine() parses applications grouped by status for the Applications tabs', () async {
      final session = Session(storage: InMemoryTokenStorage());
      final api = ApiClient(
        session,
        httpClient: MockClient((request) async {
          return jsonResponse([
            {'id': 'a1', 'status': 'NEW'},
            {'id': 'a2', 'status': 'HIRED'},
          ], 200);
        }),
      );

      final applications = await ApplicationsService(api).listMine();

      expect(applications.map((a) => a.status), ['NEW', 'HIRED']);
      expect(applications.firstWhere((a) => a.status == 'HIRED').statusLabel, 'Đã nhận');
    });
  });
}
