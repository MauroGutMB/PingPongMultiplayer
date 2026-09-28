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
///
/// With [restrictToOwnHalf], the ball is only simulated (and can only score)
/// while it's on the player's own half — the half where a real networked
/// opponent is the authority just extrapolates the ball's last known
/// trajectory instead of colliding it with anything, since the opponent's
/// own device is the one resolving that side of the court.
///
/// The center line (y == 0.5) is where a serve or re-serve always starts,
/// and both peers compute it independently — without a tie-break, both
/// would claim authority simultaneously and broadcast conflicting
/// trajectories. [authoritativeAtCenter] resolves that: exactly one side
/// (conventionally "bottom") should pass `true` and own the tie, while the
/// other ("top") passes `false` and defers until it receives the serve.
GameState advanceGame(
  GameState state,
  double dt, {
  MoveDirection? playerDirection,
  required Random random,
  bool restrictToOwnHalf = false,
  bool authoritativeAtCenter = true,
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

  final isOwnHalf = authoritativeAtCenter ? state.ballY >= 0.5 : state.ballY > 0.5;
  if (restrictToOwnHalf && !isOwnHalf) {
    return state.copyWith(
      ballX: (state.ballX + state.ballVX * dt).clamp(0.0, 1.0),
      ballY: state.ballY + state.ballVY * dt,
      playerPaddleX: playerX,
    );
  }

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

/// Applies the opponent's paddle_state (their horizontal position only —
/// their paddle's on-screen row never changes).
GameState applyOpponentPaddle(GameState state, double x) {
  return state.copyWith(opponentPaddleX: x);
}

/// Applies the opponent's ball_state. Each player's [GameState] is
/// egocentric — "my" half is always y >= 0.5 — so the sender's coordinates
/// (their own egocentric view, mirrored top/bottom from ours) need a Y-flip
/// before they mean anything on our side. X isn't mirrored between the two
/// views, so it passes through unchanged.
GameState applyOpponentBall(
  GameState state, {
  required double x,
  required double y,
  required double vx,
  required double vy,
}) {
  return state.copyWith(ballX: x, ballY: 1 - y, ballVX: vx, ballVY: -vy);
}

/// Applies an incoming score_update: the sender just missed on their own
/// half, so the point is ours.
GameState applyOpponentScored(GameState state) {
  return state.copyWith(scoreBottom: state.scoreBottom + 1);
}

/// Applies an incoming opponent_disconnected: the match can't continue.
GameState applyOpponentDisconnected(GameState state) {
  return state.copyWith(opponentLeft: true, matchOver: true);
}
