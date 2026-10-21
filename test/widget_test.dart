import 'package:flutter_test/flutter_test.dart';

import 'package:shadowing_mobile/main.dart';

void main() {
  testWidgets('Home screen displays app title and button', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SoundLanguageStudioApp());

    expect(find.text('Sound Language Studio'), findsOneWidget);
    expect(find.text('Изучайте языки на слух'), findsOneWidget);
    expect(find.text('Мои наборы'), findsOneWidget);
  });
}
