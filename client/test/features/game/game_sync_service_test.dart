import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pingpong_client/core/websocket_service.dart';
import 'package:pingpong_client/features/game/game_sync_service.dart';

class FakeTransport implements LobbyTransport {
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  final List<Map<String, dynamic>> sent = [];

  @override
  Stream<Map<String, dynamic>> get messages => _controller.stream;

  @override
  Future<void> connect() async {}

  @override
  void send(Map<String, dynamic> message) => sent.add(message);

  @override
  Future<void> close() async => _controller.close();

  void receive(Map<String, dynamic> message) => _controller.add(message);
}

void main() {
  test(
    'dispatches incoming paddle_state/ball_state/score_update/opponent_disconnected to the right callback',
    () async {
      final transport = FakeTransport();
      final sync = GameSyncService(transport);

      double? paddleX;
      (double, double, double, double)? ball;
      var scoredCount = 0;
      var disconnectedCount = 0;

      sync.listen(
        onOpponentPaddle: (x) => paddleX = x,
        onOpponentBall: (x, y, vx, vy) => ball = (x, y, vx, vy),
        onOpponentScored: () => scoredCount++,
        onOpponentDisconnected: () => disconnectedCount++,
      );

      transport.receive({'type': 'paddle_state', 'x': 0.42});
      transport.receive({'type': 'ball_state', 'x': 0.1, 'y': 0.2, 'vx': 0.3, 'vy': 0.4});
      transport.receive({'type': 'score_update'});
      transport.receive({'type': 'opponent_disconnected'});
      await Future<void>.delayed(Duration.zero);

      expect(paddleX, 0.42);
      expect(ball, (0.1, 0.2, 0.3, 0.4));
      expect(scoredCount, 1);
      expect(disconnectedCount, 1);

      sync.dispose();
    },
  );

  test('ignores unrelated message types', () async {
    final transport = FakeTransport();
    final sync = GameSyncService(transport);
    var called = false;

    sync.listen(
      onOpponentPaddle: (_) => called = true,
      onOpponentBall: (_, _, _, _) => called = true,
      onOpponentScored: () => called = true,
      onOpponentDisconnected: () => called = true,
    );

    transport.receive({'type': 'player_list', 'players': []});
    await Future<void>.delayed(Duration.zero);

    expect(called, isFalse);

    sync.dispose();
  });

  test(
    'sendPaddle/sendBall/sendScoreUpdate/sendLeaveMatch produce the expected wire messages',
    () {
      final transport = FakeTransport();
      final sync = GameSyncService(transport);

      sync.sendPaddle(0.5);
      sync.sendBall(0.1, 0.2, 0.3, 0.4);
      sync.sendScoreUpdate();
      sync.sendLeaveMatch();

      expect(transport.sent, [
        {'type': 'paddle_state', 'x': 0.5},
        {'type': 'ball_state', 'x': 0.1, 'y': 0.2, 'vx': 0.3, 'vy': 0.4},
        {'type': 'score_update'},
        {'type': 'leave_match'},
      ]);

      sync.dispose();
    },
  );
}
