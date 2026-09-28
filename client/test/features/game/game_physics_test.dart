import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pingpong_client/features/game/game_physics.dart';
import 'package:pingpong_client/features/game/game_state.dart';
import 'package:pingpong_client/features/game/widgets/control_buttons.dart';

/// Deterministic stand-in for dart:math's Random, so ball-reset launches are
/// predictable in tests.
class FixedRandom implements Random {
  FixedRandom({required this.doubleValue, required this.boolValue});

  final double doubleValue;
  final bool boolValue;

  @override
  double nextDouble() => doubleValue;

  @override
  bool nextBool() => boolValue;

  @override
  int nextInt(int max) => 0;
}

void main() {
  final random = FixedRandom(doubleValue: 0.5, boolValue: true);

  test('player paddle moves left/right and clamps within field bounds', () {
    const state = GameState(playerPaddleX: 0.5);

    final movedLeft = advanceGame(
      state,
      0.1,
      playerDirection: MoveDirection.left,
      random: random,
    );
    expect(movedLeft.playerPaddleX, lessThan(0.5));

    final movedRight = advanceGame(
      state,
      0.1,
      playerDirection: MoveDirection.right,
      random: random,
    );
    expect(movedRight.playerPaddleX, greaterThan(0.5));

    // Pushed hard enough for long enough that it must clamp at the edge.
    final clamped = advanceGame(
      state,
      10,
      playerDirection: MoveDirection.right,
      random: random,
    );
    expect(clamped.playerPaddleX, 1 - state.paddleWidth / 2);
  });

  test('ball bounces off the left wall and reverses horizontal velocity', () {
    const state = GameState(
      ballX: 0.02,
      ballY: 0.5,
      ballVX: -1.0,
      ballVY: 0.0,
    );

    final next = advanceGame(state, 0.1, random: random);

    expect(next.ballX, 0.0);
    expect(next.ballVX, 1.0);
  });

  test('ball bounces off the right wall and reverses horizontal velocity', () {
    const state = GameState(
      ballX: 0.98,
      ballY: 0.5,
      ballVX: 1.0,
      ballVY: 0.0,
    );

    final next = advanceGame(state, 0.1, random: random);

    expect(next.ballX, 1.0);
    expect(next.ballVX, -1.0);
  });

  test(
    'ball keeps its trajectory (but loses some speed) hitting a stationary paddle',
    () {
      final state = GameState(
        ballX: 0.5,
        ballY: 0.93,
        ballVX: 0.2,
        ballVY: 1.0,
        playerPaddleX: 0.5,
      );

      // No playerDirection passed: the paddle isn't moving.
      final next = advanceGame(state, 0.05, random: random);

      expect(next.ballVY, closeTo(-1.0 * 0.9, 1e-9));
      expect(next.ballVX, closeTo(0.2 * 0.9, 1e-9));
      expect(next.scoreTop, 0);
      expect(next.scoreBottom, 0);
    },
  );

  test('ball is pushed toward the direction a moving paddle hits it with', () {
    final state = GameState(
      ballX: 0.5,
      ballY: 0.93,
      ballVX: 0.0,
      ballVY: 1.0,
      playerPaddleX: 0.5,
    );

    final next = advanceGame(
      state,
      0.05,
      playerDirection: MoveDirection.right,
      random: random,
    );

    expect(next.ballVY, -1.0); // no damping: the paddle was moving
    expect(next.ballVX, greaterThan(0)); // pushed rightward with the paddle
  });

  test('opponent scores when the ball passes the player paddle unblocked', () {
    final state = GameState(
      ballX: 0.5,
      ballY: 0.93,
      ballVX: 0.0,
      ballVY: 1.0,
      playerPaddleX: 0.9, // paddle is far from where the ball crosses
    );

    final next = advanceGame(state, 0.05, random: random);

    expect(next.scoreTop, 1);
    expect(next.scoreBottom, 0);
    // Ball re-serves from the center after the point.
    expect(next.ballX, 0.5);
    expect(next.ballY, 0.5);
  });

  test('player scores when the ball passes the static opponent paddle unblocked', () {
    final state = GameState(
      ballX: 0.9, // opponent paddle stays centered at 0.5
      ballY: 0.07,
      ballVX: 0.0,
      ballVY: -1.0,
    );

    final next = advanceGame(state, 0.05, random: random);

    expect(next.scoreBottom, 1);
    expect(next.scoreTop, 0);
  });

  test('advanceGame is a no-op once the match is over', () {
    const state = GameState(matchOver: true, ballX: 0.3);

    final next = advanceGame(
      state,
      1,
      playerDirection: MoveDirection.left,
      random: random,
    );

    expect(next, same(state));
  });

  test('resetBall re-centers the ball and applies the random launch angle', () {
    const state = GameState(ballX: 0.1, ballY: 0.9, ballVX: 5, ballVY: 5);

    final next = resetBall(state, FixedRandom(doubleValue: 1.0, boolValue: false));

    expect(next.ballX, 0.5);
    expect(next.ballY, 0.5);
    expect(next.ballVX, closeTo(0.55 * 0.3, 1e-9));
    expect(next.ballVY, -0.55);
  });

  group('restrictToOwnHalf (networked match)', () {
    test('ball on the opponent half just extrapolates, ignoring collisions', () {
      final state = GameState(
        ballX: 0.5,
        ballY: 0.05, // deep in the opponent's half
        ballVX: 0.3,
        ballVY: -1.0,
        opponentPaddleX: 0.9, // far from the ball: would "score" if simulated
      );

      final next = advanceGame(
        state,
        0.05,
        random: random,
        restrictToOwnHalf: true,
      );

      // Straight-line motion, no bounce, no score — the opponent's device
      // owns physics over there.
      expect(next.ballX, closeTo(0.5 + 0.3 * 0.05, 1e-9));
      expect(next.ballY, closeTo(0.05 - 1.0 * 0.05, 1e-9));
      expect(next.ballVX, 0.3);
      expect(next.ballVY, -1.0);
      expect(next.scoreTop, 0);
      expect(next.scoreBottom, 0);
    });

    test('ball on our own half still collides and scores normally', () {
      final state = GameState(
        ballX: 0.5,
        ballY: 0.93,
        ballVX: 0.0,
        ballVY: 1.0,
        playerPaddleX: 0.9, // far from the ball: a real miss
      );

      final next = advanceGame(
        state,
        0.05,
        random: random,
        restrictToOwnHalf: true,
      );

      expect(next.scoreTop, 1);
      expect(next.ballY, 0.5); // re-served after the point
    });

    test('the player paddle still moves on the opponent half', () {
      final state = GameState(ballY: 0.1, playerPaddleX: 0.5);

      final next = advanceGame(
        state,
        0.1,
        playerDirection: MoveDirection.left,
        random: random,
        restrictToOwnHalf: true,
      );

      expect(next.playerPaddleX, lessThan(0.5));
    });
  });

  group('applying opponent updates', () {
    test('applyOpponentPaddle sets the opponent paddle position', () {
      const state = GameState(opponentPaddleX: 0.5);

      final next = applyOpponentPaddle(state, 0.8);

      expect(next.opponentPaddleX, 0.8);
    });

    test('applyOpponentBall mirrors the sender\'s egocentric coordinates', () {
      const state = GameState();

      final next = applyOpponentBall(state, x: 0.7, y: 0.9, vx: 0.2, vy: 0.4);

      // x/vx pass through; y/vy flip since the sender's "their own half" is
      // our "opponent's half".
      expect(next.ballX, 0.7);
      expect(next.ballY, closeTo(0.1, 1e-9));
      expect(next.ballVX, 0.2);
      expect(next.ballVY, -0.4);
    });

    test('applyOpponentScored awards us the point', () {
      const state = GameState(scoreBottom: 2, scoreTop: 5);

      final next = applyOpponentScored(state);

      expect(next.scoreBottom, 3);
      expect(next.scoreTop, 5);
    });
  });
}
