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

/// Resolves a ball/paddle bounce. A paddle moving at the time of impact
/// pushes the ball's horizontal velocity toward its own direction of travel;
/// a stationary paddle just reflects the ball, dampening its speed a little.
({double vx, double vy}) _bounce({
  required double vx,
  required double vy,
  required double paddleVelocity,
}) {
  final bouncedVy = -vy;
  if (paddleVelocity == 0) {
    return (vx: vx * kStationaryHitDamping, vy: bouncedVy * kStationaryHitDamping);
  }
  final pushedVx = (vx + paddleVelocity * kPaddleSpinFactor).clamp(
    -kMaxBallSpeed,
    kMaxBallSpeed,
  );
  return (vx: pushedVx, vy: bouncedVy);
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
  final playerVelocity = switch (playerDirection) {
    MoveDirection.left => -kPaddleSpeed,
    MoveDirection.right => kPaddleSpeed,
    null => 0.0,
  };
  playerX = (playerX + playerVelocity * dt).clamp(halfPaddle, 1 - halfPaddle);

  // The opponent paddle doesn't move on its own yet, so it always counts as
  // stationary until a real opponent drives it over the network.
  const opponentVelocity = 0.0;

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
      final bounce = _bounce(vx: vx, vy: vy, paddleVelocity: opponentVelocity);
      vx = bounce.vx;
      vy = bounce.vy;
    } else {
      return resetBall(
        state.copyWith(playerPaddleX: playerX, scoreBottom: state.scoreBottom + 1),
        random,
      );
    }
  } else if (vy > 0 && ballY >= 1 - kPaddleBandOffset) {
    if ((ballX - playerX).abs() <= halfPaddle) {
      ballY = 1 - kPaddleBandOffset;
      final bounce = _bounce(vx: vx, vy: vy, paddleVelocity: playerVelocity);
      vx = bounce.vx;
      vy = bounce.vy;
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
