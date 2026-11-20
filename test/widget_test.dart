import 'package:flutter_test/flutter_test.dart';
import 'package:flash2mart_admin/main.dart';

void main() {
  testWidgets('Admin smoke test', (WidgetTester tester) async {
    expect(const Flash2MartAdminApp(), isNotNull);
  });
}
