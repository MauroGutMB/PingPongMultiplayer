import 'dart:math';

import 'game_constants.dart';
import 'game_state.dart';
import 'widgets/control_buttons.dart' show MoveDirection;

/// Re-centers the ball and launches it in a random direction. Used both for
/// the opening serve and after every point. [speedMultiplier] comes from the
/// match's configured ball speed (see MatchConfig) — 1.0 for the local
/// practice screen, which has no invite and so no configuration at all.
GameState resetBall(GameState state, Random random, {double speedMultiplier = 1.0}) {
  final horizontal = random.nextDouble() * 0.6 - 0.3;
  final goingDown = random.nextBool();
  final speed = kInitialBallSpeed * speedMultiplier;
  return state.copyWith(
    ballX: 0.5,
    ballY: 0.5,
    ballVX: speed * horizontal,
    ballVY: speed * (goingDown ? 1 : -1),
    // Keep the dead-reckoning target in sync with the real position — see
    // the note in advanceGame's authoritative branch for why this matters.
    ballTargetX: 0.5,
    ballTargetY: 0.5,
  );
}

/// Resolves a ball/paddle bounce. A paddle moving at the time of impact
/// pushes the ball's horizontal velocity toward its own direction of travel;
/// a stationary paddle just reflects the ball, dampening its speed a little.
({double vx, double vy}) _bounce({
  required double vx,
  required double vy,
  required double paddleVelocity,
  required double maxSpeed,
}) {
  final bouncedVy = -vy;
  if (paddleVelocity == 0) {
    return (vx: vx * kStationaryHitDamping, vy: bouncedVy * kStationaryHitDamping);
  }
  final pushedVx = (vx + paddleVelocity * kPaddleSpinFactor).clamp(-maxSpeed, maxSpeed);
  return (vx: pushedVx, vy: bouncedVy);
}

/// Fraction of the remaining gap to a network target closed this tick, for a
/// framerate-independent exponential "chase" (see [kOpponentSmoothingRate]).
double _smoothingFactor(double dt) => 1 - exp(-kOpponentSmoothingRate * dt);

/// Advances the match by [dt] seconds: moves the player paddle, moves the
/// ball, resolves wall/paddle collisions, and awards a point (then re-serves)
/// on a miss. Pure function of its inputs so it can be unit-tested without a
/// running [Ticker].
///
/// With [restrictToOwnHalf], the ball is only simulated (and can only score)
/// while it's on the player's own half — the half where a real networked
/// opponent is the authority just dead-reckons the ball's last known
/// trajectory (via [GameState.ballTargetX]/[GameState.ballTargetY]) instead
/// of colliding it with anything, since the opponent's own device is the one
/// resolving that side of the court. The displayed [GameState.ballX]/
/// [GameState.ballY] smoothly chase that target rather than snapping to each
/// network update — see [applyOpponentBall].
///
/// The opponent's paddle is handled the same way: [GameState.opponentPaddleX]
/// always glides toward [GameState.opponentPaddleTargetX] rather than
/// teleporting on every [applyOpponentPaddle] call.
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
  double ballSpeedMultiplier = 1.0,
  int winningScore = 0,
}) {
  if (state.matchOver || dt <= 0) return state;
  final maxSpeed = kMaxBallSpeed * ballSpeedMultiplier;

  final smoothing = _smoothingFactor(dt);
  state = state.copyWith(
    opponentPaddleX:
        state.opponentPaddleX +
        (state.opponentPaddleTargetX - state.opponentPaddleX) * smoothing,
  );

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
    final targetX = (state.ballTargetX + state.ballVX * dt).clamp(0.0, 1.0);
    final targetY = state.ballTargetY + state.ballVY * dt;
    return state.copyWith(
      ballX: state.ballX + (targetX - state.ballX) * smoothing,
      ballY: state.ballY + (targetY - state.ballY) * smoothing,
      ballTargetX: targetX,
      ballTargetY: targetY,
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
      final bounce = _bounce(
        vx: vx,
        vy: vy,
        paddleVelocity: opponentVelocity,
        maxSpeed: maxSpeed,
      );
      vx = bounce.vx;
      vy = bounce.vy;
    } else {
      final scored = state.copyWith(playerPaddleX: playerX, scoreBottom: state.scoreBottom + 1);
      // A configured winning score (see MatchConfig) ends the match the
      // instant it's reached, instead of re-serving and playing on until the
      // clock runs out — 0 keeps the original time-only behavior, so the
      // local practice screen (which never sets this) is unaffected.
      if (winningScore > 0 && scored.scoreBottom >= winningScore) {
        return scored.copyWith(matchOver: true);
      }
      return resetBall(scored, random, speedMultiplier: ballSpeedMultiplier);
    }
  } else if (vy > 0 && ballY >= 1 - kPaddleBandOffset) {
    if ((ballX - playerX).abs() <= halfPaddle) {
      ballY = 1 - kPaddleBandOffset;
      final bounce = _bounce(
        vx: vx,
        vy: vy,
        paddleVelocity: playerVelocity,
        maxSpeed: maxSpeed,
      );
      vx = bounce.vx;
      vy = bounce.vy;
    } else {
      final scored = state.copyWith(playerPaddleX: playerX, scoreTop: state.scoreTop + 1);
      if (winningScore > 0 && scored.scoreTop >= winningScore) {
        return scored.copyWith(matchOver: true);
      }
      return resetBall(scored, random, speedMultiplier: ballSpeedMultiplier);
    }
  }

  return state.copyWith(
    ballX: ballX,
    ballY: ballY,
    ballVX: vx,
    ballVY: vy,
    // Mirror our own true position into the dead-reckoning target while
    // we're authoritative. If we didn't, the target could be stale by
    // several rallies' worth of motion (it's only otherwise written when
    // *not* authoritative) — then the instant the ball crosses into the
    // opponent's half, the extrapolate branch above would start dead
    // reckoning from that stale point instead of from here, and the ball
    // would visibly jump to a wrong position.
    ballTargetX: ballX,
    ballTargetY: ballY,
    playerPaddleX: playerX,
  );
}

/// Applies the opponent's paddle_state (their horizontal position only —
/// their paddle's on-screen row never changes). Only updates the *target*;
/// [GameState.opponentPaddleX] glides toward it in [advanceGame] instead of
/// snapping, so movement reads as smooth rather than teleporting.
GameState applyOpponentPaddle(GameState state, double x) {
  return state.copyWith(opponentPaddleTargetX: x);
}

/// Applies the opponent's ball_state. Each player's [GameState] is
/// egocentric — "my" half is always y >= 0.5 — so the sender's coordinates
/// (their own egocentric view, mirrored top/bottom from ours) need a Y-flip
/// before they mean anything on our side. X isn't mirrored between the two
/// views, so it passes through unchanged.
///
/// Only sets the ball's *target* and velocity; [GameState.ballX]/
/// [GameState.ballY] glide toward the target in [advanceGame] instead of
/// snapping straight to it.
GameState applyOpponentBall(
  GameState state, {
  required double x,
  required double y,
  required double vx,
  required double vy,
}) {
  return state.copyWith(
    ballTargetX: x,
    ballTargetY: 1 - y,
    ballVX: vx,
    ballVY: -vy,
  );
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
