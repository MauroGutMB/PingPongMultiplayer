import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pingpong_client/core/websocket_service.dart';
import 'package:pingpong_client/features/game/network_game_loop_controller.dart';
import 'package:pingpong_client/features/lobby/lobby_provider.dart';

/// Two of these, cross-wired, stand in for the server's pure relay: whatever
/// one side sends, the other receives — exactly what MatchService.relay does.
class RelayTransport implements LobbyTransport {
  final _incoming = StreamController<Map<String, dynamic>>.broadcast();
  RelayTransport? peer;
  final List<Map<String, dynamic>> sent = [];

  @override
  Stream<Map<String, dynamic>> get messages => _incoming.stream;

  @override
  Future<void> connect() async {}

  @override
  void send(Map<String, dynamic> message) {
    sent.add(message);
    peer?._incoming.add(message);
  }

  @override
  Future<void> close() async => _incoming.close();
}

class _FixedLobbyController extends LobbyController {
  _FixedLobbyController(this._fixedState);
  final LobbyState _fixedState;

  @override
  LobbyState build() => _fixedState;
}

void main() {
  testWidgets(
    'two networked peers serve, and the ball actually moves for both sides',
    (tester) async {
      final bottomTransport = RelayTransport();
      final topTransport = RelayTransport();
      bottomTransport.peer = topTransport;
      topTransport.peer = bottomTransport;

      final bottomContainer = ProviderContainer(
        overrides: [
          lobbyTransportProvider.overrideWithValue(bottomTransport),
          lobbyControllerProvider.overrideWith(
            () => _FixedLobbyController(
              LobbyState(matchStart: MatchStart(matchId: 'm', side: 'bottom')),
            ),
          ),
        ],
      );
      final topContainer = ProviderContainer(
        overrides: [
          lobbyTransportProvider.overrideWithValue(topTransport),
          lobbyControllerProvider.overrideWith(
            () => _FixedLobbyController(
              LobbyState(matchStart: MatchStart(matchId: 'm', side: 'top')),
            ),
          ),
        ],
      );
      // Triggers build() for both and, since these are autoDispose providers,
      // keeps them alive via a live subscription — exactly what NetworkGameScreen's
      // own ref.watch does while it's mounted in the real app.
      bottomContainer.listen(networkGameLoopProvider, (_, _) {});
      topContainer.listen(networkGameLoopProvider, (_, _) {});

      // Drive real frames for ~1.5s of simulated time so the serve broadcast
      // has time to leave "bottom" and reach "top".
      for (var i = 0; i < 90; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      final bottomState = bottomContainer.read(networkGameLoopProvider);
      final topState = topContainer.read(networkGameLoopProvider);

      expect(
        bottomState.ballY,
        isNot(0.5),
        reason: 'the serving side never moved its own ball',
      );
      expect(
        topState.ballY,
        isNot(0.5),
        reason:
            'the receiving side never got the serve broadcast — ball frozen at center',
      );

      // Dispose explicitly (rather than via addTearDown) so the Ticker/Timer
      // are cancelled before the test framework's end-of-test invariant
      // checks run.
      bottomContainer.dispose();
      topContainer.dispose();
    },
  );
}
