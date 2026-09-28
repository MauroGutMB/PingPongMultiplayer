import 'dart:async';

import '../../core/websocket_service.dart';

/// Sends/receives the in-match messages the server relays verbatim between
/// the two matched sockets (paddle_state, ball_state, score_update).
class GameSyncService {
  GameSyncService(this._transport);

  final LobbyTransport _transport;
  StreamSubscription<Map<String, dynamic>>? _subscription;

  void listen({
    required void Function(double x) onOpponentPaddle,
    required void Function(double x, double y, double vx, double vy) onOpponentBall,
    required void Function() onOpponentScored,
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
      }
    });
  }

  void sendPaddle(double x) {
    _transport.send({'type': 'paddle_state', 'x': x});
  }

  void sendBall(double x, double y, double vx, double vy) {
    _transport.send({'type': 'ball_state', 'x': x, 'y': y, 'vx': vx, 'vy': vy});
  }

  void sendScoreUpdate() {
    _transport.send({'type': 'score_update'});
  }

  void dispose() {
    _subscription?.cancel();
  }
}
