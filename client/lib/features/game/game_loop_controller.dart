import 'dart:async';
import 'dart:math';

import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'game_physics.dart';
import 'game_state.dart';
import 'widgets/control_buttons.dart' show MoveDirection;

/// Overridable in tests for deterministic ball launches.
final gameRandomProvider = Provider.autoDispose<Random>((ref) => Random());

class GameLoopController extends Notifier<GameState> {
  Ticker? _ticker;
  Timer? _matchTimer;
  Duration _lastElapsed = Duration.zero;
  MoveDirection? _playerDirection;
  late Random _random;

  @override
  GameState build() {
    _random = ref.watch(gameRandomProvider);
    ref.onDispose(_disposeLoop);
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
    final dt =
        (elapsed - _lastElapsed).inMicroseconds / Duration.microsecondsPerSecond;
    _lastElapsed = elapsed;
    if (dt <= 0) return;
    state = advanceGame(
      state,
      dt,
      playerDirection: _playerDirection,
      random: _random,
    );
  }

  void _disposeLoop() {
    _ticker?.dispose();
    _matchTimer?.cancel();
  }
}

final gameLoopProvider =
    NotifierProvider.autoDispose<GameLoopController, GameState>(
      GameLoopController.new,
    );
