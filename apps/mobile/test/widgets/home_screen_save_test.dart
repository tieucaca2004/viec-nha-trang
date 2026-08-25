import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:viec_nha_trang/core/auth/session.dart';
import 'package:viec_nha_trang/core/network/api_client.dart';
import 'package:viec_nha_trang/features/applications/data/applications_service.dart';
import 'package:viec_nha_trang/features/jobs/data/jobs_service.dart';
import 'package:viec_nha_trang/features/jobs/presentation/home_screen.dart';
import 'package:viec_nha_trang/features/saved_jobs/data/saved_jobs_service.dart';
import '../helpers/in_memory_token_storage.dart';
import '../helpers/json_response.dart';

/// Sửa lỗi Critical #1 (FULL AUDIT): trước đây HomeScreen/JobCard không có cách nào lưu việc -
/// SavedJobsService chỉ được gọi từ SavedJobsScreen (chỉ unsave được, không save được). Test này
/// dựng cả HomeScreen thật (không chỉ JobCard tách rời) với các service thật (network giả lập
/// qua MockClient) để chứng minh luồng lưu/bỏ lưu hoạt động từ chính màn hình tìm việc.
void main() {
  testWidgets('user can save a job from HomeScreen, and unsave it again, via real API calls', (tester) async {
    var savedOnServer = <String>{};
    final requestedPaths = <String>[];

    final session = Session(storage: InMemoryTokenStorage());
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        requestedPaths.add('${request.method} ${request.url.path}');

        if (request.url.path.endsWith('/jobs') && request.method == 'GET') {
          return jsonResponse({
            'data': [
              {
                'id': 'job-1',
                'title': 'Phục vụ nhà hàng',
                'employer': {'id': 'e1', 'businessName': 'Quán Test', 'verificationLevel': 'UNVERIFIED'},
                'salaryMin': 20000,
                'salaryMax': 25000,
                'salaryUnit': 'HOUR',
                'employmentType': 'PART_TIME',
                'status': 'ACTIVE',
              },
            ],
            'meta': {'total': 1, 'limit': 20, 'offset': 0},
          }, 200);
        }
        if (request.url.path.endsWith('/applications/me')) {
          return jsonResponse([], 200);
        }
        if (request.url.path.endsWith('/saved-jobs') && request.method == 'GET') {
          return jsonResponse(
            savedOnServer.map((id) => {'jobId': id, 'job': {'id': id}}).toList(),
            200,
          );
        }
        if (request.url.path.endsWith('/saved-jobs/job-1') && request.method == 'POST') {
          savedOnServer.add('job-1');
          return jsonResponse(null, 201);
        }
        if (request.url.path.endsWith('/saved-jobs/job-1') && request.method == 'DELETE') {
          savedOnServer.remove('job-1');
          return jsonResponse(null, 200);
        }
        if (request.url.path.endsWith('/categories') || request.url.path.endsWith('/areas')) {
          return jsonResponse([], 200);
        }
        return http.Response('not found: ${request.url.path}', 404);
      }),
    );

    await session.setTokens(access: 'fake-access', refresh: 'fake-refresh', roles: ['JOB_SEEKER']);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<Session>.value(value: session),
        Provider<ApiClient>(create: (_) => api),
        Provider<JobsService>(create: (_) => JobsService(api)),
        Provider<ApplicationsService>(create: (_) => ApplicationsService(api)),
        Provider<SavedJobsService>(create: (_) => SavedJobsService(api)),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ));
    await tester.pumpAndSettle();

    // Ban đầu chưa lưu - icon rỗng.
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
    expect(find.byIcon(Icons.bookmark), findsNothing);

    // SAVE: bấm icon -> gọi POST /saved-jobs/job-1 thật, icon chuyển sang đã lưu.
    await tester.tap(find.byIcon(Icons.bookmark_border));
    await tester.pumpAndSettle();

    expect(requestedPaths, contains('POST /api/v1/saved-jobs/job-1'));
    expect(savedOnServer, contains('job-1'));
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_border), findsNothing);

    // UNSAVE: bấm lại -> gọi DELETE /saved-jobs/job-1 thật, icon quay lại trạng thái chưa lưu.
    await tester.tap(find.byIcon(Icons.bookmark));
    await tester.pumpAndSettle();

    expect(requestedPaths, contains('DELETE /api/v1/saved-jobs/job-1'));
    expect(savedOnServer, isNot(contains('job-1')));
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
    expect(find.byIcon(Icons.bookmark), findsNothing);
  });

  testWidgets('a job already saved on the server shows as saved when HomeScreen first loads', (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/jobs') && request.method == 'GET') {
          return jsonResponse({
            'data': [
              {
                'id': 'job-1',
                'title': 'Phục vụ nhà hàng',
                'employer': {'id': 'e1', 'businessName': 'Quán Test', 'verificationLevel': 'UNVERIFIED'},
                'salaryMin': 20000,
                'salaryMax': 25000,
                'salaryUnit': 'HOUR',
                'employmentType': 'PART_TIME',
                'status': 'ACTIVE',
              },
            ],
            'meta': {'total': 1, 'limit': 20, 'offset': 0},
          }, 200);
        }
        if (request.url.path.endsWith('/applications/me')) {
          return jsonResponse([], 200);
        }
        if (request.url.path.endsWith('/saved-jobs') && request.method == 'GET') {
          return jsonResponse([
            {'jobId': 'job-1', 'job': {'id': 'job-1'}},
          ], 200);
        }
        if (request.url.path.endsWith('/categories') || request.url.path.endsWith('/areas')) {
          return jsonResponse([], 200);
        }
        return http.Response('not found: ${request.url.path}', 404);
      }),
    );

    await session.setTokens(access: 'fake-access', refresh: 'fake-refresh', roles: ['JOB_SEEKER']);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<Session>.value(value: session),
        Provider<ApiClient>(create: (_) => api),
        Provider<JobsService>(create: (_) => JobsService(api)),
        Provider<ApplicationsService>(create: (_) => ApplicationsService(api)),
        Provider<SavedJobsService>(create: (_) => SavedJobsService(api)),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_border), findsNothing);
  });

  // Phần H (phase QA Job Seeker): double-tap nút lưu trên JobCard ở Home chỉ được gửi ĐÚNG 1
  // request - không giống JobDetailScreen._toggleSave() (đã có chốt _togglingSave) hay
  // SavedJobsScreen._unsave() (tự an toàn vì xoá khỏi list ngay lập tức trước khi await),
  // HomeScreen._toggleSave() không có chốt nào, nút bookmark vẫn bấm được trong lúc request đầu
  // còn đang treo.
  testWidgets('double-tap nút lưu trên JobCard (Home) chỉ gửi ĐÚNG 1 POST /saved-jobs/job-1', (tester) async {
    var saveCallCount = 0;
    final saveGate = Completer<void>();
    final session = Session(storage: InMemoryTokenStorage());
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/jobs') && request.method == 'GET') {
          return jsonResponse({
            'data': [
              {
                'id': 'job-1',
                'title': 'Phục vụ nhà hàng',
                'employer': {'id': 'e1', 'businessName': 'Quán Test', 'verificationLevel': 'UNVERIFIED'},
                'salaryMin': 20000,
                'salaryMax': 25000,
                'salaryUnit': 'HOUR',
                'employmentType': 'PART_TIME',
                'status': 'ACTIVE',
              },
            ],
            'meta': {'total': 1, 'limit': 20, 'offset': 0},
          }, 200);
        }
        if (request.url.path.endsWith('/applications/me')) return jsonResponse([], 200);
        if (request.url.path.endsWith('/saved-jobs') && request.method == 'GET') return jsonResponse([], 200);
        if (request.url.path.endsWith('/saved-jobs/job-1') && request.method == 'POST') {
          saveCallCount += 1;
          await saveGate.future;
          return jsonResponse(null, 201);
        }
        if (request.url.path.endsWith('/categories') || request.url.path.endsWith('/areas')) {
          return jsonResponse([], 200);
        }
        return http.Response('not found: ${request.url.path}', 404);
      }),
    );

    await session.setTokens(access: 'fake-access', refresh: 'fake-refresh', roles: ['JOB_SEEKER']);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<Session>.value(value: session),
        Provider<ApiClient>(create: (_) => api),
        Provider<JobsService>(create: (_) => JobsService(api)),
        Provider<ApplicationsService>(create: (_) => ApplicationsService(api)),
        Provider<SavedJobsService>(create: (_) => SavedJobsService(api)),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ));
    await tester.pumpAndSettle();

    final saveButton = find.byIcon(Icons.bookmark_border);
    await tester.tap(saveButton);
    await tester.tap(saveButton, warnIfMissed: false);
    await tester.pump();

    expect(saveCallCount, 1, reason: 'double-tap nút lưu không được gửi 2 request POST /saved-jobs');

    saveGate.complete();
    await tester.pumpAndSettle();
    expect(saveCallCount, 1);
  });
}
