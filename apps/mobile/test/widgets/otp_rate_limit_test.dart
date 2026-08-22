import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:viec_nha_trang/core/auth/session.dart';
import 'package:viec_nha_trang/core/network/api_client.dart';
import 'package:viec_nha_trang/core/network/otp_cooldown.dart';
import 'package:viec_nha_trang/features/auth/data/auth_service.dart';
import 'package:viec_nha_trang/features/auth/presentation/email_register_screen.dart';
import 'package:viec_nha_trang/features/auth/presentation/email_verify_screen.dart';
import 'package:viec_nha_trang/features/auth/presentation/login_screen.dart';
import '../helpers/in_memory_token_storage.dart';
import '../helpers/json_response.dart';

/// Regression cho bug THẬT trên Beta APK c8c1798: tài khoản đã tồn tại bấm "GỬI MÃ ĐĂNG NHẬP"
/// nhận "Bạn đã yêu cầu quá nhiều lần. Vui lòng chờ 15 giây rồi thử lại." (HTTP 429).
///
/// Nguyên nhân gốc đã tái hiện bằng HTTP thật với backend thật: route
/// `POST /auth/register/email/request` bị giới hạn 3 request/60s THEO IP (không theo email), và
/// route này TRƯỚC ĐÂY dùng chung cho cả đăng ký lẫn đăng nhập -> các lần bấm ở màn Đăng ký/Gửi
/// lại mã trước đó đã tiêu hết hạn mức của lần bấm Đăng nhập.
///
/// Sửa ĐÚNG NGUYÊN NHÂN (không chỉ vá UI đếm ngược): đăng ký và đăng nhập giờ gọi 2 ROUTE khác
/// nhau (`/auth/register/email/request|verify` vs `/auth/login/email/request|verify`), mỗi route
/// có hạn mức throttle RIÊNG ở backend, và mobile giữ 2 bucket cooldown RIÊNG
/// (OtpCooldown.emailRegister / .emailLogin) - xem otp_cooldown.dart. Suite này khoá lại: (1) một
/// lần bấm = một request, (2) 429 khoá đúng Retry-After giây và không tự động retry, (3) đăng ký
/// và đăng nhập KHÔNG còn ăn chung cooldown/route.
void main() {
  setUp(() {
    OtpCooldown.emailRegister.reset();
    OtpCooldown.emailLogin.reset();
    OtpCooldown.phone.reset();
  });
  tearDown(() {
    OtpCooldown.emailRegister.reset();
    OtpCooldown.emailLogin.reset();
    OtpCooldown.phone.reset();
  });

  Widget wrap(ApiClient api, Session session, Widget child) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<Session>.value(value: session),
        Provider<ApiClient>.value(value: api),
        Provider<AuthService>(create: (_) => AuthService(api, session)),
      ],
      child: MaterialApp(home: child),
    );
  }

  http.Response throttled(int retryAfterSeconds) {
    return http.Response(
      '{"statusCode":429,"message":"ThrottlerException: Too Many Requests"}',
      429,
      headers: {
        'content-type': 'application/json; charset=utf-8',
        'retry-after': '$retryAfterSeconds',
      },
    );
  }

  // ---------- V1. Một lần bấm = ĐÚNG một request, đúng ROUTE đăng nhập ----------

  testWidgets('V1. bấm GỬI MÃ ĐĂNG NHẬP gọi ĐÚNG /auth/login/email/request, không phải route đăng ký', (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    var loginPosts = 0;
    var registerPosts = 0;
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/auth/login/email/request')) {
          loginPosts += 1;
          return jsonResponse({'expiresInSeconds': 600}, 201);
        }
        if (request.url.path.endsWith('/auth/register/email/request')) {
          registerPosts += 1;
          return jsonResponse({'expiresInSeconds': 600}, 201);
        }
        return http.Response('unexpected: ${request.url.path}', 404);
      }),
    );

    await tester.pumpWidget(wrap(api, session, const LoginScreen()));
    await tester.enterText(find.byType(TextField), 'nguoidung@example.com');
    await tester.tap(find.text('GỬI MÃ ĐĂNG NHẬP'));
    await tester.pumpAndSettle();

    expect(loginPosts, 1);
    expect(registerPosts, 0, reason: 'Đăng nhập KHÔNG được gọi route đăng ký');
    expect(find.byType(EmailVerifyScreen), findsOneWidget);
  });

  // ---------- V2. 429 -> khoá nút + đếm ngược ĐÚNG Retry-After, KHÔNG tự gửi lại ----------

  testWidgets('V2. 429 Retry-After=15 -> hiện đúng 15 giây, khoá nút, KHÔNG tự động retry', (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    var posts = 0;
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        posts += 1;
        return throttled(15);
      }),
    );

    await tester.pumpWidget(wrap(api, session, const LoginScreen()));
    await tester.enterText(find.byType(TextField), 'nguoidung@example.com');
    await tester.tap(find.text('GỬI MÃ ĐĂNG NHẬP'));
    await tester.pump();
    await tester.pump();

    // Đúng 1 request: ApiClient KHÔNG tự gửi lại POST khi gặp 429.
    expect(posts, 1);
    expect(find.text('Bạn đã yêu cầu quá nhiều lần. Vui lòng chờ 15 giây rồi thử lại.'), findsOneWidget);
    expect(find.text('GỬI LẠI SAU 15 GIÂY'), findsOneWidget);

    FilledButton button() => tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button().onPressed, isNull, reason: 'nút phải bị khoá trong lúc cooldown');

    // Đếm ngược chạy thật theo từng giây.
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('GỬI LẠI SAU 14 GIÂY'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('GỬI LẠI SAU 9 GIÂY'), findsOneWidget);

    // Chưa hết cooldown mà cố bấm thì tuyệt đối không phát sinh request mới.
    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await tester.pump();
    expect(posts, 1);

    await tester.pump(const Duration(seconds: 9));
    // Hết đếm ngược -> nút trở lại bình thường.
    expect(find.text('GỬI MÃ ĐĂNG NHẬP'), findsOneWidget);
    expect(button().onPressed, isNotNull);
  });

  // ---------- V3. Hết cooldown mới được gửi lại ----------

  testWidgets('V3. hết đếm ngược -> bấm lại được và request mới ĐƯỢC gửi', (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    var posts = 0;
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        posts += 1;
        if (posts == 1) return throttled(3);
        return jsonResponse({'expiresInSeconds': 600}, 201);
      }),
    );

    await tester.pumpWidget(wrap(api, session, const LoginScreen()));
    await tester.enterText(find.byType(TextField), 'nguoidung@example.com');
    await tester.tap(find.text('GỬI MÃ ĐĂNG NHẬP'));
    await tester.pump();
    await tester.pump();
    expect(find.text('GỬI LẠI SAU 3 GIÂY'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('GỬI MÃ ĐĂNG NHẬP'), findsOneWidget);

    await tester.tap(find.text('GỬI MÃ ĐĂNG NHẬP'));
    await tester.pumpAndSettle();
    expect(posts, 2);
    expect(find.byType(EmailVerifyScreen), findsOneWidget);
  });

  // ---------- V4. ĐĂNG KÝ bị 429 KHÔNG còn khoá màn ĐĂNG NHẬP (route + bucket đã tách) ----------

  testWidgets('V4. bị 429 ở màn Đăng ký KHÔNG làm khoá màn Đăng nhập (route/bucket đã tách riêng)', (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    var registerPosts = 0;
    var loginPosts = 0;
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/auth/register/email/request')) {
          registerPosts += 1;
          return throttled(20);
        }
        if (request.url.path.endsWith('/auth/login/email/request')) {
          loginPosts += 1;
          return jsonResponse({'expiresInSeconds': 600}, 201);
        }
        return http.Response('unexpected: ${request.url.path}', 404);
      }),
    );

    await tester.pumpWidget(wrap(api, session, const EmailRegisterScreen()));
    await tester.enterText(find.byType(TextField), 'nguoidung@example.com');
    await tester.tap(find.text('GỬI MÃ XÁC MINH'));
    await tester.pump();
    await tester.pump();
    expect(registerPosts, 1);
    expect(find.text('GỬI LẠI SAU 20 GIÂY'), findsOneWidget);
    expect(OtpCooldown.emailRegister.isActive, isTrue);
    expect(OtpCooldown.emailLogin.isActive, isFalse, reason: 'bucket đăng nhập không bị ảnh hưởng');

    // Người dùng quay ra, mở màn Đăng nhập: route khác, hạn mức khác trên server -> phải bấm
    // được và gửi được request thật ngay, KHÔNG bị khoá lây từ màn Đăng ký.
    await tester.pumpWidget(wrap(api, session, const LoginScreen()));
    await tester.pump();
    expect(find.text('GỬI MÃ ĐĂNG NHẬP'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);

    await tester.enterText(find.byType(TextField), 'nguoidung@example.com');
    await tester.tap(find.text('GỬI MÃ ĐĂNG NHẬP'));
    await tester.pumpAndSettle();
    expect(loginPosts, 1, reason: 'đăng nhập phải gửi được request thật, không bị chặn bởi bucket đăng ký');

    await tester.pump(const Duration(seconds: 20));
  });

  // ---------- V5. 429 KHÔNG có Retry-After -> vẫn khoá, dùng trọn cửa sổ 60s ----------

  testWidgets('V5. 429 thiếu header Retry-After -> vẫn khoá nút (mặc định 60 giây)', (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        return jsonResponse({'statusCode': 429, 'message': 'ThrottlerException: Too Many Requests'}, 429);
      }),
    );

    await tester.pumpWidget(wrap(api, session, const LoginScreen()));
    await tester.enterText(find.byType(TextField), 'nguoidung@example.com');
    await tester.tap(find.text('GỬI MÃ ĐĂNG NHẬP'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Bạn thao tác quá nhanh. Vui lòng thử lại sau ít phút.'), findsOneWidget);
    expect(find.text('GỬI LẠI SAU 60 GIÂY'), findsOneWidget);

    await tester.pump(const Duration(seconds: 60));
  });

  // ---------- V6. Lỗi KHÁC 429 không được khoá nút ----------

  testWidgets('V6. lỗi 500 KHÔNG kích hoạt cooldown - người dùng thử lại ngay được', (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        return jsonResponse({'message': 'Hệ thống đang bận'}, 500);
      }),
    );

    await tester.pumpWidget(wrap(api, session, const LoginScreen()));
    await tester.enterText(find.byType(TextField), 'nguoidung@example.com');
    await tester.tap(find.text('GỬI MÃ ĐĂNG NHẬP'));
    await tester.pumpAndSettle();

    expect(find.text('GỬI MÃ ĐĂNG NHẬP'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
    expect(OtpCooldown.emailLogin.isActive, isFalse);
  });

  // ---------- V7. "Gửi lại mã" ở màn ĐĂNG NHẬP dùng đúng route + bucket đăng nhập ----------

  testWidgets('V7. Gửi lại mã (đăng nhập) gọi route đăng nhập, bị 429 -> khoá đúng bucket emailLogin', (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    var loginPosts = 0;
    var registerPosts = 0;
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/auth/login/email/request')) {
          loginPosts += 1;
          return throttled(30);
        }
        if (request.url.path.endsWith('/auth/register/email/request')) {
          registerPosts += 1;
          return throttled(30);
        }
        return http.Response('unexpected: ${request.url.path}', 404);
      }),
    );

    await tester.pumpWidget(
      wrap(api, session, const EmailVerifyScreen(email: 'nguoidung@example.com', isLogin: true)),
    );
    await tester.tap(find.text('Gửi lại mã'));
    await tester.pump();
    await tester.pump();

    expect(loginPosts, 1);
    expect(registerPosts, 0, reason: '"Gửi lại mã" ở luồng đăng nhập phải gọi route đăng nhập');
    expect(find.text('Gửi lại mã sau 30 giây'), findsOneWidget);
    expect(tester.widget<TextButton>(find.byType(TextButton)).onPressed, isNull);
    expect(OtpCooldown.emailLogin.isActive, isTrue);
    expect(OtpCooldown.emailRegister.isActive, isFalse);

    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Gửi lại mã'), findsOneWidget);
  });

  // ---------- V8. "Gửi lại mã" ở màn ĐĂNG KÝ dùng đúng route + bucket đăng ký ----------

  testWidgets('V8. Gửi lại mã (đăng ký) gọi route đăng ký, không đụng bucket đăng nhập', (tester) async {
    final session = Session(storage: InMemoryTokenStorage());
    var loginPosts = 0;
    var registerPosts = 0;
    final api = ApiClient(
      session,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/auth/register/email/request')) {
          registerPosts += 1;
          return throttled(10);
        }
        if (request.url.path.endsWith('/auth/login/email/request')) {
          loginPosts += 1;
          return jsonResponse({'expiresInSeconds': 600}, 201);
        }
        return http.Response('unexpected: ${request.url.path}', 404);
      }),
    );

    await tester.pumpWidget(
      wrap(api, session, const EmailVerifyScreen(email: 'nguoidung@example.com')),
    );
    await tester.tap(find.text('Gửi lại mã'));
    await tester.pump();
    await tester.pump();

    expect(registerPosts, 1);
    expect(loginPosts, 0);
    expect(OtpCooldown.emailRegister.isActive, isTrue);
    expect(OtpCooldown.emailLogin.isActive, isFalse);

    await tester.pump(const Duration(seconds: 10));
  });
}
