import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:viec_nha_trang/core/auth/session.dart';
import 'package:viec_nha_trang/core/network/api_client.dart';
import 'package:viec_nha_trang/features/employer/data/employer_jobs_service.dart';
import '../../helpers/in_memory_token_storage.dart';
import '../../helpers/json_response.dart';

void main() {
  group('EmployerJobsService (đặc tả §19/§21 Phase 3: đăng tin, quản lý ứng viên)', () {
    test('createJob() sends the wizard payload matching backend CreateJobDto field names', () async {
      final session = Session(storage: InMemoryTokenStorage());
      Map<String, dynamic>? sentBody;
      final api = ApiClient(
        session,
        httpClient: MockClient((request) async {
          sentBody = jsonDecode(request.body);
          return jsonResponse({'id': 'job-1', 'status': 'ACTIVE'}, 201);
        }),
      );

      await EmployerJobsService(api).createJob({
        'employerLocationId': 'loc-1',
        'categoryId': 'cat-1',
        'title': 'Phục vụ',
        'headcount': 2,
        'employmentType': 'PART_TIME',
        'shifts': ['EVENING'],
        'salaryMin': 28000,
        'salaryMax': 32000,
        'salaryUnit': 'HOUR',
      });

      // Khớp tên field DTO thật của backend (docs/API.md) - không tự đoán tên field.
      expect(sentBody!['employerLocationId'], 'loc-1');
      expect(sentBody!['salaryMin'], 28000);
      expect(sentBody!['shifts'], ['EVENING']);
    });

    test('updateApplicationStatus() PATCHes the correct status transition (state machine §16 gốc)', () async {
      final session = Session(storage: InMemoryTokenStorage());
      Map<String, dynamic>? sentBody;
      String? path;
      final api = ApiClient(
        session,
        httpClient: MockClient((request) async {
          path = request.url.path;
          sentBody = jsonDecode(request.body);
          return jsonResponse(null, 200);
        }),
      );

      await EmployerJobsService(api).updateApplicationStatus('app-1', 'VIEWED');

      expect(path, endsWith('/applications/app-1/status'));
      expect(sentBody!['status'], 'VIEWED');
    });

    test('applicantsForJob() lists applicants for a specific job', () async {
      final session = Session(storage: InMemoryTokenStorage());
      final api = ApiClient(
        session,
        httpClient: MockClient((request) async {
          return jsonResponse([
            {
              'id': 'app-1',
              'status': 'NEW',
              'jobSeeker': {
                'fullName': 'Ứng viên A',
                'user': {'phone': '0900000003'},
              },
            },
          ], 200);
        }),
      );

      final applicants = await EmployerJobsService(api).applicantsForJob('job-1');
      expect(applicants, hasLength(1));
      expect(applicants.first['jobSeeker']['user']['phone'], '0900000003');
    });
  });
}
