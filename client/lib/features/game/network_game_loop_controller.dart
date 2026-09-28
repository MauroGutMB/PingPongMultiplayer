import 'dart:async';
import 'dart:math';

import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../lobby/lobby_provider.dart';
import 'game_physics.dart';
import 'game_state.dart';
import 'game_sync_service.dart';
import 'widgets/control_buttons.dart' show MoveDirection;

const _paddleBroadcastInterval = Duration(milliseconds: 50);
const _ballBroadcastInterval = Duration(milliseconds: 50);

/// How long after a serve the authoritative side keeps broadcasting the ball
/// even if it's nominally crossed to the opponent's half. The opponent's
/// screen may still be finishing its own transition into the match (and
/// hasn't subscribed to the socket yet) when the serve first goes out, so a
/// single message can get lost with nobody at fault; repeating it for a
/// short window makes that loss harmless instead of an infinite freeze.
const _serveGracePeriod = Duration(milliseconds: 800);

/// Same game loop as [GameLoopController], but for a real match: the ball is
/// only simulated on our own half (the other half is authoritative on the
/// opponent's device), our paddle and ball are broadcast over the socket
/// already used by the lobby, and the opponent's updates drive their paddle
/// and (when it's their turn) the ball.
class NetworkGameLoopController extends Notifier<GameState> {
  Ticker? _ticker;
  Timer? _matchTimer;
  GameSyncService? _sync;
  Duration _lastElapsed = Duration.zero;
  Duration _sincePaddleBroadcast = Duration.zero;
  Duration _sinceBallBroadcast = Duration.zero;
  Duration _matchAge = Duration.zero;
  MoveDirection? _playerDirection;
  final Random _random = Random();

  // Only one side may own the center-line tie (see advanceGame's
  // authoritativeAtCenter doc) — otherwise both peers independently serve a
  // random ball on every point and fight over it. "bottom" always owns it;
  // "top" starts frozen and waits for bottom's first serve to arrive.
  bool _authoritativeAtCenter = true;

  @override
  GameState build() {
    final side = ref.watch(lobbyControllerProvider.select((s) => s.matchStart?.side));
    _authoritativeAtCenter = side != 'top';

    final transport = ref.watch(lobbyTransportProvider);
    ref.onDispose(_disposeLoop);

    _sync = GameSyncService(transport)
      ..listen(
        onOpponentPaddle: (x) => state = applyOpponentPaddle(state, x),
        onOpponentBall: (x, y, vx, vy) =>
            state = applyOpponentBall(state, x: x, y: y, vx: vx, vy: vy),
        onOpponentScored: () => state = applyOpponentScored(state),
        onOpponentDisconnected: _onOpponentDisconnected,
      );

    _lastElapsed = Duration.zero;
    _ticker = Ticker(_onTick)..start();
    _matchTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickClock());

    const initial = GameState();
    if (!_authoritativeAtCenter) return initial;

    final serve = resetBall(initial, _random);
    // Broadcast the opening serve unconditionally, right now — not on the
    // next tick. If the random direction happens to head straight for the
    // opponent's half, the very first tick's own send-check would already
    // see us as no longer authoritative and skip sending, leaving the other
    // side waiting forever for a serve that never arrives.
    _sync!.sendBall(serve.ballX, serve.ballY, serve.ballVX, serve.ballVY);
    return serve;
  }

  void setPlayerDirection(MoveDirection? direction) {
    _playerDirection = direction;
  }

  /// Tells the server we're backing out of the match (e.g. after tapping
  /// "Voltar" on the match-over screen, or leaving mid-match).
  void leaveMatch() {
    _sync?.sendLeaveMatch();
  }

  void _onOpponentDisconnected() {
    if (state.matchOver) return;
    state = applyOpponentDisconnected(state);
    _ticker?.stop();
  }

  void _tickClock() {
    if (state.matchOver) return;
    final remaining = state.remainingSeconds - 1;
    if (remaining <= 0) {
      state = state.copyWith(remainingSeconds: 0, matchOver: true);
      _ticker?.stop();
    } else {
      state = state.copyWith(remainingSeconds: remaining);
    }
  }

  bool _isMine(double ballY) =>
      _authoritativeAtCenter ? ballY >= 0.5 : ballY > 0.5;

  void _onTick(Duration elapsed) {
    final dtDuration = elapsed - _lastElapsed;
    final dt = dtDuration.inMicroseconds / Duration.microsecondsPerSecond;
    _lastElapsed = elapsed;
    if (dt <= 0) return;

    final scoreTopBefore = state.scoreTop;
    final vyBefore = state.ballVY;

    state = advanceGame(
      state,
      dt,
      playerDirection: _playerDirection,
      random: _random,
      restrictToOwnHalf: true,
      authoritativeAtCenter: _authoritativeAtCenter,
    );

    _sincePaddleBroadcast += dtDuration;
    if (_sincePaddleBroadcast >= _paddleBroadcastInterval) {
      _sincePaddleBroadcast = Duration.zero;
      _sync?.sendPaddle(state.playerPaddleX);
    }

    _matchAge += dtDuration;
    // Only the side that owns the center tie (the server of the opening
    // point) gets the grace-period redundancy — the other side has nothing
    // real to report until it actually receives that serve, and must never
    // broadcast its own still-uninitialized ball back at the server.
    final inServeGracePeriod =
        _authoritativeAtCenter && _matchAge < _serveGracePeriod;
    if (!inServeGracePeriod && !_isMine(state.ballY)) {
      return; // opponent's half: not ours to report on
    }

    final scoredJustNow = state.scoreTop != scoreTopBefore;
    final bouncedJustNow = vyBefore != 0 && state.ballVY.sign != vyBefore.sign;

    _sinceBallBroadcast += dtDuration;
    if (scoredJustNow || bouncedJustNow || _sinceBallBroadcast >= _ballBroadcastInterval) {
      _sinceBallBroadcast = Duration.zero;
      _sync?.sendBall(state.ballX, state.ballY, state.ballVX, state.ballVY);
    }
    if (scoredJustNow) {
      _sync?.sendScoreUpdate();
    }
  }

  void _disposeLoop() {
    _ticker?.dispose();
    _matchTimer?.cancel();
    _sync?.dispose();
  }
}

final networkGameLoopProvider =
    NotifierProvider.autoDispose<NetworkGameLoopController, GameState>(
      NetworkGameLoopController.new,
    );
