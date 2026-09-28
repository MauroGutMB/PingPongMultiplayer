import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pingpong_client/core/theme.dart';
import 'package:pingpong_client/features/game/game_screen.dart';
import 'package:pingpong_client/features/game/widgets/ball_widget.dart';
import 'package:pingpong_client/features/game/widgets/paddle_widget.dart';

void main() {
  Future<void> pumpGameScreen(WidgetTester tester) {
    return tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: appTheme, home: const GameScreen()),
      ),
    );
  }

  // Unmounts the screen so the autoDispose game loop provider tears down its
  // Ticker/Timer before the test ends (otherwise flutter_test flags them as
  // leaked pending timers).
  Future<void> teardown(WidgetTester tester) {
    return tester.pumpWidget(const SizedBox());
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

    await teardown(tester);
  });

  testWidgets('control buttons highlight while pressed and reset on release', (
    tester,
  ) async {
    await pumpGameScreen(tester);

    final leftButtonFinder = find.ancestor(
      of: find.byIcon(Icons.arrow_left),
      matching: find.byType(Container),
    );

    Color? colorOf(Finder finder) => tester.widget<Container>(finder).color;

    expect(colorOf(leftButtonFinder), AppColors.purple);

    final gesture = await tester.startGesture(
      tester.getCenter(leftButtonFinder),
    );
    await tester.pump();
    expect(colorOf(leftButtonFinder), AppColors.purpleLight);

    await gesture.up();
    await tester.pump();
    expect(colorOf(leftButtonFinder), AppColors.purple);

    await teardown(tester);
  });
}
