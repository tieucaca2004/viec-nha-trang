import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viec_nha_trang/features/auth/presentation/onboarding_screen.dart';
import 'package:viec_nha_trang/features/auth/presentation/phone_login_screen.dart';

void main() {
  group('OnboardingScreen (đặc tả §6 Phase 3)', () {
    testWidgets('shows logo, slogan, and both role choices', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));

      expect(find.text('VIỆC NHA TRANG'), findsOneWidget);
      expect(find.textContaining('Ứng tuyển 1 chạm'), findsOneWidget);
      expect(find.text('TÌM VIỆC'), findsOneWidget);
      expect(find.text('TUYỂN NGƯỜI'), findsOneWidget);
    });

    testWidgets('choosing TÌM VIỆC navigates to login with intendedRole=JOB_SEEKER', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));

      await tester.tap(find.text('TÌM VIỆC'));
      await tester.pumpAndSettle();

      final loginScreen = tester.widget<PhoneLoginScreen>(find.byType(PhoneLoginScreen));
      expect(loginScreen.intendedRole, 'JOB_SEEKER');
    });

    testWidgets('choosing TUYỂN NGƯỜI navigates to login with intendedRole=EMPLOYER', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));

      await tester.tap(find.text('TUYỂN NGƯỜI'));
      await tester.pumpAndSettle();

      final loginScreen = tester.widget<PhoneLoginScreen>(find.byType(PhoneLoginScreen));
      expect(loginScreen.intendedRole, 'EMPLOYER');
    });
  });
}
