import 'package:flutter_test/flutter_test.dart';
import 'package:masjid_subscription_app/models/auth_models.dart';
import 'package:masjid_subscription_app/models/block_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:masjid_subscription_app/main.dart';

void main() {
  testWidgets('shows sign in screen on launch', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(const MasjidSubscriptionApp());
    await tester.pumpAndSettle();

    expect(find.text('Sign in to continue'), findsOneWidget);
    expect(find.text('Login details'), findsOneWidget);
  });

  test('normalizes staff block assignments', () {
    final staff = StaffUser.fromFirestore(<String, dynamic>{
      'fullName': 'Collector',
      'username': 'collector',
      'password': 'secret123',
      'blocks': <String>[' a ', 'B', 'a', ''],
    });

    expect(staff.blocks, <String>['A', 'B']);
    expect(normalizeBlockCodes(<String>[' c ', 'C', 'd']), <String>['C', 'D']);
  });
}
