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
  MoveDirection? _playerDirection;
  final Random _random = Random();

  @override
  GameState build() {
    final transport = ref.watch(lobbyTransportProvider);
    ref.onDispose(_disposeLoop);

    _sync = GameSyncService(transport)
      ..listen(
        onOpponentPaddle: (x) => state = applyOpponentPaddle(state, x),
        onOpponentBall: (x, y, vx, vy) =>
            state = applyOpponentBall(state, x: x, y: y, vx: vx, vy: vy),
        onOpponentScored: () => state = applyOpponentScored(state),
      );

    _lastElapsed = Duration.zero;
    _ticker = Ticker(_onTick)..start();
    _matchTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickClock());

    return resetBall(const GameState(), _random);
  }

  void setPlayerDirection(MoveDirection? direction) {
    _playerDirection = direction;
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
    );

    _sincePaddleBroadcast += dtDuration;
    if (_sincePaddleBroadcast >= _paddleBroadcastInterval) {
      _sincePaddleBroadcast = Duration.zero;
      _sync?.sendPaddle(state.playerPaddleX);
    }

    if (state.ballY < 0.5) return; // opponent's half: not ours to report on

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
