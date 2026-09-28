import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pingpong_client/core/theme.dart';
import 'package:pingpong_client/features/game/game_screen.dart';
import 'package:pingpong_client/features/game/widgets/ball_widget.dart';
import 'package:pingpong_client/features/game/widgets/paddle_widget.dart';

void main() {
  Future<void> pumpGameScreen(WidgetTester tester) {
    return tester.pumpWidget(
      MaterialApp(theme: appTheme, home: const GameScreen()),
    );
  }

  testWidgets('shows one ball and two paddles (opponent on top, own on bottom)', (
    tester,
  ) async {
    await pumpGameScreen(tester);

    expect(find.byType(BallWidget), findsOneWidget);
    expect(find.byType(PaddleWidget), findsNWidgets(2));

    final positions = find
        .byType(PaddleWidget)
        .evaluate()
        .map((e) => tester.getCenter(find.byWidget(e.widget)))
        .toList();
    expect(positions[0].dy, lessThan(positions[1].dy));
  });

  testWidgets('control buttons highlight while pressed and reset on release', (
    tester,
  ) async {
    await pumpGameScreen(tester);

    final leftButtonFinder = find.ancestor(
      of: find.byIcon(Icons.arrow_left),
      matching: find.byType(Container),
    );

    Color? colorOf(Finder finder) =>
        (tester.widget<Container>(finder).color);

    expect(colorOf(leftButtonFinder), AppColors.purple);

    final gesture = await tester.startGesture(tester.getCenter(leftButtonFinder));
    await tester.pump();
    expect(colorOf(leftButtonFinder), AppColors.purpleLight);

    await gesture.up();
    await tester.pump();
    expect(colorOf(leftButtonFinder), AppColors.purple);
  });
}
