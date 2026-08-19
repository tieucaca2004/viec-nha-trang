import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:viec_nha_trang/core/auth/session.dart';
import 'package:viec_nha_trang/core/network/api_client.dart';
import 'package:viec_nha_trang/features/auth/data/auth_service.dart';
import 'package:viec_nha_trang/features/profile/data/job_seeker_profile_service.dart';
import 'package:viec_nha_trang/features/profile/presentation/profile_screen.dart';
import '../helpers/in_memory_token_storage.dart';
import '../helpers/json_response.dart';

/// Hotfix: "Hồ sơ tìm việc không hiển thị SĐT" + "Kết nối quá chậm". Root cause thật: /me (SĐT) và
/// /me/job-seeker-profile trước đây được await TUẦN TỰ trong cùng 1 try/catch - profile trước, /me
/// sau - nên 1 request lỗi/chậm làm request kia (dù độc lập, dù backend trả đúng dữ liệu) không
/// bao giờ chạy, khiến SĐT "biến mất". Test này khoá đúng hành vi đã sửa: 2 request chạy song
/// song, 1 cái lỗi không được xoá dữ liệu cái kia đã tải thành công.
void main() {
  Widget buildScreen(ApiClient api) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<Session>.value(value: api.session),
        Provider<JobSeekerProfileService>(create: (_) => JobSeekerProfileService(api)),
        Provider<AuthService>(create: (_) => AuthService(api, api.session)),
      ],
      child: const MaterialApp(home: ProfileScreen()),
    );
  }

  testWidgets('job-seeker-profile fetch fails (500) nhưng /me thành công -> SĐT vẫn hiển thị đúng', (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    await session.setTokens(access: 'test-token', refresh: 'refresh-token', roles: ['JOB_SEEKER']);

    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/me/job-seeker-profile')) {
          return jsonResponse({'message': 'Hệ thống đang bận'}, 500);
        }
        if (request.url.path.endsWith('/me')) {
          return jsonResponse({
            'id': 'user-1',
            'phone': '0912345678',
            'email': null,
            'isPhoneVerified': true,
            'jobSeekerProfile': null,
            'employerProfile': null,
          }, 200);
        }
        return jsonResponse(null, 404);
      }),
    );

    await tester.pumpWidget(buildScreen(api));
    await tester.pumpAndSettle();

    // SĐT phải hiển thị đúng dù request job-seeker-profile lỗi 500 - đây chính là bug thật đã sửa.
    expect(find.text('0912345678'), findsOneWidget);
    expect(find.text('Đã xác minh'), findsOneWidget);
    // Không hiện lỗi chặn toàn màn hình vì /me đã tải thành công (còn dữ liệu để hiển thị).
    expect(find.text('Kết nối quá chậm. Vui lòng thử lại.'), findsNothing);
  });

  testWidgets('cả 2 request đều lỗi -> hiện màn lỗi với nút thử lại (không hiện dữ liệu giả)', (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    await session.setTokens(access: 'test-token', refresh: 'refresh-token', roles: ['JOB_SEEKER']);

    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        return jsonResponse({'message': 'Hệ thống đang bận'}, 500);
      }),
    );

    await tester.pumpWidget(buildScreen(api));
    await tester.pumpAndSettle();

    expect(find.text('Chưa có số điện thoại'), findsNothing); // không hiện fallback text khi thực ra là lỗi tải
    expect(find.textContaining('Hệ thống đang bận'), findsOneWidget);
  });

  testWidgets('cả 2 request thành công -> hiển thị SĐT và hồ sơ đúng', (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    await session.setTokens(access: 'test-token', refresh: 'refresh-token', roles: ['JOB_SEEKER']);

    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/me/job-seeker-profile')) {
          return jsonResponse({'fullName': 'Nguyễn Văn A', 'isSeeking': true, 'isLookingNow': false}, 200);
        }
        if (request.url.path.endsWith('/me')) {
          return jsonResponse({
            'id': 'user-1',
            'phone': '0987654321',
            'email': null,
            'isPhoneVerified': false,
            'jobSeekerProfile': null,
            'employerProfile': null,
          }, 200);
        }
        return jsonResponse(null, 404);
      }),
    );

    await tester.pumpWidget(buildScreen(api));
    await tester.pumpAndSettle();

    expect(find.text('0987654321'), findsOneWidget);
    expect(find.text('Chưa xác minh'), findsOneWidget);
    expect(find.text('Nguyễn Văn A'), findsOneWidget);
  });
}
