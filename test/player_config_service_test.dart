import 'package:flutter_test/flutter_test.dart';
import 'package:shadowing_mobile/main.dart';

void main() {
  testWidgets('Player screen displays title and controls', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SoundLanguageStudioApp());

    // Ждём завершения асинхронной загрузки конфигурации.
    await tester.pumpAndSettle();

    expect(find.text('Sound Language Studio'), findsOneWidget);
    expect(find.text('Сценарий'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Проверить звук'), findsOneWidget);
  });
}
