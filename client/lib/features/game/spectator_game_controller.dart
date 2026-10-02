import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/protocol.dart';
import '../lobby/lobby_provider.dart';
import 'game_state.dart';

/// Read only counterpart to [NetworkGameLoopController]: no physics, no
/// paddle control, no ticker driving a simulation — it only applies whatever
/// the server relays (paddle_state/ball_state/score_update, each tagged with
/// `from` so the egocentric "bottom"/"top" view they were sent in can be
/// turned into the neutral bottom/top frame this screen renders) onto the
/// snapshot the spectate_request was answered with. [GameState]'s existing
/// player/opponent fields are reused as-is for bottom/top: the neutral frame
/// this controller renders in already places "player" at the bottom row and
/// "opponent" at the top row, exactly like the existing field layout.
class SpectatorGameController extends Notifier<GameState> {
  StreamSubscription<Map<String, dynamic>>? _subscription;
  Timer? _clock;

  @override
  GameState build() {
    final session = ref.read(lobbyControllerProvider).spectateSession;
    final transport = ref.watch(lobbyTransportProvider);
    ref.onDispose(_dispose);

    if (session == null) {
      // Shouldn't happen — this screen is only ever pushed right after a
      // spectate_snapshot arrives — but failing into an already-over state
      // is safer than crashing on a null session.
      return const GameState(matchOver: true);
    }

    _subscription = transport.messages.listen(_onMessage);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _tickClock());

    return GameState(
      ballX: session.ballX,
      ballY: session.ballY,
      ballVX: session.ballVX,
      ballVY: session.ballVY,
      opponentPaddleX: session.paddleTopX,
      opponentPaddleTargetX: session.paddleTopX,
      playerPaddleX: session.paddleBottomX,
      scoreTop: session.scoreTop,
      scoreBottom: session.scoreBottom,
      remainingSeconds: session.remainingSeconds,
      spectatorCount: session.spectatorCount,
    );
  }

  void _onMessage(Map<String, dynamic> message) {
    switch (message['type']) {
      case 'ball_state':
        final fromBottom = message['from'] == 'bottom';
        final x = (message['x'] as num).toDouble();
        final y = (message['y'] as num).toDouble();
        final vx = (message['vx'] as num).toDouble();
        final vy = (message['vy'] as num).toDouble();
        state = state.copyWith(
          ballX: x,
          ballY: fromBottom ? y : 1 - y,
          ballVX: vx,
          ballVY: fromBottom ? vy : -vy,
        );
      case 'paddle_state':
        final fromBottom = message['from'] == 'bottom';
        final x = (message['x'] as num).toDouble();
        state = fromBottom
            ? state.copyWith(playerPaddleX: x)
            : state.copyWith(opponentPaddleX: x, opponentPaddleTargetX: x);
      case 'score_update':
        state = state.copyWith(
          scoreBottom: message['scoreBottom'] as int,
          scoreTop: message['scoreTop'] as int,
        );
      case 'spectator_count':
        state = state.copyWith(spectatorCount: message['count'] as int);
      case 'match_ended':
        state = state.copyWith(
          matchOver: true,
          scoreBottom: message['scoreBottom'] as int,
          scoreTop: message['scoreTop'] as int,
        );
        _clock?.cancel();
    }
  }

  /// Local-only countdown mirroring what each player's own client already
  /// does; the server never runs the clock, so this is our best estimate
  /// between snapshots, not a source of truth.
  void _tickClock() {
    if (state.matchOver) return;
    final remaining = state.remainingSeconds - 1;
    state = state.copyWith(remainingSeconds: remaining > 0 ? remaining : 0);
  }

  /// Tells the server we're done watching, so it drops us from the
  /// spectator count right away instead of only noticing on a disconnect
  /// that may never come (the socket itself stays open after leaving this
  /// screen — we're still in the lobby).
  void leaveSpectate() {
    ref.read(lobbyTransportProvider).send(leaveSpectateMessage());
  }

  void _dispose() {
    _subscription?.cancel();
    _clock?.cancel();
  }
}

final spectatorGameProvider =
    NotifierProvider.autoDispose<SpectatorGameController, GameState>(
      SpectatorGameController.new,
    );
