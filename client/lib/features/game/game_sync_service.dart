import 'dart:async';

import '../../core/websocket_service.dart';

/// Sends/receives the in-match messages the server relays verbatim between
/// the two matched sockets (paddle_state, ball_state, score_update,
/// match_end), plus the opponent_disconnected and spectator_count
/// notifications and our own leave_match request.
class GameSyncService {
  GameSyncService(this._transport);

  final LobbyTransport _transport;
  StreamSubscription<Map<String, dynamic>>? _subscription;

  void listen({
    required void Function(double x) onOpponentPaddle,
    required void Function(double x, double y, double vx, double vy) onOpponentBall,
    required void Function() onOpponentScored,
    required void Function() onOpponentDisconnected,
    void Function(int count)? onSpectatorCount,
  }) {
    _subscription = _transport.messages.listen((message) {
      switch (message['type']) {
        case 'paddle_state':
          onOpponentPaddle((message['x'] as num).toDouble());
        case 'ball_state':
          onOpponentBall(
            (message['x'] as num).toDouble(),
            (message['y'] as num).toDouble(),
            (message['vx'] as num).toDouble(),
            (message['vy'] as num).toDouble(),
          );
        case 'score_update':
          onOpponentScored();
        case 'opponent_disconnected':
          onOpponentDisconnected();
        case 'spectator_count':
          onSpectatorCount?.call(message['count'] as int);
      }
    });
  }

  void sendPaddle(double x) {
    _transport.send({'type': 'paddle_state', 'x': x});
  }

  void sendBall(double x, double y, double vx, double vy) {
    _transport.send({'type': 'ball_state', 'x': x, 'y': y, 'vx': vx, 'vy': vy});
  }

  /// [scoreBottom]/[scoreTop] are the absolute, side-labelled scores (not
  /// "mine"/"theirs") computed by the caller — see
  /// NetworkGameLoopController._neutralScoreBottom/_neutralScoreTop — so that
  /// anyone reading the relay without the sender's own egocentric context
  /// (the server, caching it for spectators; a spectator's own client) can
  /// use them directly without first having to know who sent the message.
  void sendScoreUpdate({required int scoreBottom, required int scoreTop}) {
    _transport.send({
      'type': 'score_update',
      'scoreBottom': scoreBottom,
      'scoreTop': scoreTop,
    });
  }

  /// Tells the server (and, through it, the opponent and any spectators) that
  /// our local clock ran out and the match is over, with the final score.
  void sendMatchEnd({required int scoreBottom, required int scoreTop}) {
    _transport.send({
      'type': 'match_end',
      'scoreBottom': scoreBottom,
      'scoreTop': scoreTop,
    });
  }

  /// Tells the server we're intentionally leaving an in-progress match, so it
  /// can notify the opponent and put us back in the lobby.
  void sendLeaveMatch() {
    _transport.send({'type': 'leave_match'});
  }

  void dispose() {
    _subscription?.cancel();
  }
}
