import 'dart:math';

import 'game_constants.dart';
import 'game_state.dart';
import 'widgets/control_buttons.dart' show MoveDirection;

/// Re-centers the ball and launches it in a random direction. Used both for
/// the opening serve and after every point.
GameState resetBall(GameState state, Random random) {
  final horizontal = random.nextDouble() * 0.6 - 0.3;
  final goingDown = random.nextBool();
  return state.copyWith(
    ballX: 0.5,
    ballY: 0.5,
    ballVX: kInitialBallSpeed * horizontal,
    ballVY: kInitialBallSpeed * (goingDown ? 1 : -1),
  );
}

/// Advances the match by [dt] seconds: moves the player paddle, moves the
/// ball, resolves wall/paddle collisions, and awards a point (then re-serves)
/// on a miss. Pure function of its inputs so it can be unit-tested without a
/// running [Ticker].
GameState advanceGame(
  GameState state,
  double dt, {
  MoveDirection? playerDirection,
  required Random random,
}) {
  if (state.matchOver || dt <= 0) return state;

  final halfPaddle = state.paddleWidth / 2;
  var playerX = state.playerPaddleX;
  if (playerDirection == MoveDirection.left) {
    playerX -= kPaddleSpeed * dt;
  } else if (playerDirection == MoveDirection.right) {
    playerX += kPaddleSpeed * dt;
  }
  playerX = playerX.clamp(halfPaddle, 1 - halfPaddle);

  var ballX = state.ballX + state.ballVX * dt;
  var ballY = state.ballY + state.ballVY * dt;
  var vx = state.ballVX;
  var vy = state.ballVY;

  if (ballX <= 0) {
    ballX = 0;
    vx = -vx;
  } else if (ballX >= 1) {
    ballX = 1;
    vx = -vx;
  }

  if (vy < 0 && ballY <= kPaddleBandOffset) {
    if ((ballX - state.opponentPaddleX).abs() <= halfPaddle) {
      ballY = kPaddleBandOffset;
      vy = -vy;
    } else {
      return resetBall(
        state.copyWith(playerPaddleX: playerX, scoreBottom: state.scoreBottom + 1),
        random,
      );
    }
  } else if (vy > 0 && ballY >= 1 - kPaddleBandOffset) {
    if ((ballX - playerX).abs() <= halfPaddle) {
      ballY = 1 - kPaddleBandOffset;
      vy = -vy;
    } else {
      return resetBall(
        state.copyWith(playerPaddleX: playerX, scoreTop: state.scoreTop + 1),
        random,
      );
    }
  }

  return state.copyWith(
    ballX: ballX,
    ballY: ballY,
    ballVX: vx,
    ballVY: vy,
    playerPaddleX: playerX,
  );
}
