import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pingpong_client/core/websocket_service.dart';
import 'package:pingpong_client/features/game/game_screen.dart';
import 'package:pingpong_client/features/lobby/lobby_provider.dart';

class FakeLobbyTransport implements LobbyTransport {
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
  Future<FakeLobbyTransport> pumpNetworkGameScreen(WidgetTester tester) async {
    final transport = FakeLobbyTransport();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [lobbyTransportProvider.overrideWithValue(transport)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NetworkGameScreen()),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // Not pumpAndSettle: the game loop's Ticker never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return transport;
  }

  Future<void> teardown(WidgetTester tester) {
    return tester.pumpWidget(const SizedBox());
  }

  testWidgets('popping the match screen sends leave_match to the server', (
    tester,
  ) async {
    final transport = await pumpNetworkGameScreen(tester);

    final context = tester.element(find.byType(NetworkGameScreen));
    Navigator.of(context).pop();
    await tester.pump();

    expect(transport.sent.last, {'type': 'leave_match'});

    await teardown(tester);
  });

  testWidgets('shows an opponent-left message when the opponent disconnects', (
    tester,
  ) async {
    final transport = await pumpNetworkGameScreen(tester);

    transport.receive({'type': 'opponent_disconnected'});
    await tester.pump();

    expect(find.text('O adversário desconectou'), findsOneWidget);
    expect(find.text('Fim de partida'), findsNothing);

    await teardown(tester);
  });
}
