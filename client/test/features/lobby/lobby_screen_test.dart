import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pingpong_client/core/websocket_service.dart';
import 'package:pingpong_client/features/lobby/lobby_provider.dart';
import 'package:pingpong_client/features/lobby/lobby_screen.dart';

class FakeLobbyTransport implements LobbyTransport {
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  final List<Map<String, dynamic>> sent = [];
  bool connected = false;

  @override
  Stream<Map<String, dynamic>> get messages => _controller.stream;

  @override
  Future<void> connect() async {
    connected = true;
  }

  @override
  void send(Map<String, dynamic> message) => sent.add(message);

  @override
  Future<void> close() async {
    await _controller.close();
  }

  void receive(Map<String, dynamic> message) => _controller.add(message);
}

Future<void> _pump(WidgetTester tester) => tester.pumpAndSettle();

Future<void> _enterLobby(
  WidgetTester tester,
  FakeLobbyTransport transport, {
  List<Map<String, dynamic>> players = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [lobbyTransportProvider.overrideWithValue(transport)],
      child: const MaterialApp(home: LobbyScreen()),
    ),
  );

  await tester.enterText(find.byType(TextField), 'Alice');
  await tester.tap(find.text('Entrar'));
  // A single pump, not pumpAndSettle: the brief "connecting" state shows an
  // indeterminate CircularProgressIndicator, whose animation never settles.
  await tester.pump();

  transport.receive({'type': 'welcome', 'playerId': 'me'});
  transport.receive({
    'type': 'player_list',
    'players': [
      {'id': 'me', 'nickname': 'Alice'},
      ...players,
    ],
  });
  await _pump(tester);
}

void main() {
  testWidgets('shows nickname prompt before connecting', (tester) async {
    final transport = FakeLobbyTransport();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [lobbyTransportProvider.overrideWithValue(transport)],
        child: const MaterialApp(home: LobbyScreen()),
      ),
    );

    expect(find.text('Escolha um apelido'), findsOneWidget);
    expect(transport.connected, isFalse);
  });

  testWidgets('connects and lists other online players, excluding self', (
    tester,
  ) async {
    final transport = FakeLobbyTransport();
    await _enterLobby(
      tester,
      transport,
      players: [
        {'id': 'bob', 'nickname': 'Bob'},
      ],
    );

    expect(transport.connected, isTrue);
    expect(transport.sent.single, {'type': 'hello', 'nickname': 'Alice'});
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Alice'), findsNothing);
  });

  testWidgets('tapping a player confirms and sends an invite_request', (
    tester,
  ) async {
    final transport = FakeLobbyTransport();
    await _enterLobby(
      tester,
      transport,
      players: [
        {'id': 'bob', 'nickname': 'Bob'},
      ],
    );

    await tester.tap(find.text('Bob'));
    await _pump(tester);
    expect(find.text('Convidar Bob para uma partida?'), findsOneWidget);

    await tester.tap(find.text('Convidar'));
    // A single pump, not pumpAndSettle: the waiting dialog shows an
    // indeterminate CircularProgressIndicator, whose animation never settles.
    await tester.pump();
    await tester.pump();

    expect(transport.sent.last, {'type': 'invite_request', 'toId': 'bob'});
    expect(find.text('Aguardando resposta de Bob...'), findsOneWidget);

    transport.receive({
      'type': 'invite_response',
      'fromId': 'bob',
      'accepted': true,
    });
    await _pump(tester);

    expect(find.text('Aguardando resposta de Bob...'), findsNothing);
  });

  testWidgets('rejected invite shows a snackbar', (tester) async {
    final transport = FakeLobbyTransport();
    await _enterLobby(
      tester,
      transport,
      players: [
        {'id': 'bob', 'nickname': 'Bob'},
      ],
    );

    await tester.tap(find.text('Bob'));
    await _pump(tester);
    await tester.tap(find.text('Convidar'));
    // A single pump, not pumpAndSettle: the waiting dialog shows an
    // indeterminate CircularProgressIndicator, whose animation never settles.
    await tester.pump();
    await tester.pump();

    transport.receive({
      'type': 'invite_response',
      'fromId': 'bob',
      'accepted': false,
    });
    // Not pumpAndSettle: it would also wait out the SnackBar's auto-dismiss
    // timer, so by the time we assert it would already be gone.
    await tester.pump();
    await tester.pump();

    expect(find.text('Seu convite foi recusado.'), findsOneWidget);
  });

  testWidgets('incoming invite shows accept/reject popup and responds', (
    tester,
  ) async {
    final transport = FakeLobbyTransport();
    await _enterLobby(tester, transport);

    transport.receive({
      'type': 'invite_request',
      'fromId': 'carol',
      'fromNickname': 'Carol',
    });
    await _pump(tester);

    expect(find.text('Carol te convidou para uma partida.'), findsOneWidget);

    await tester.tap(find.text('Aceitar'));
    await _pump(tester);

    expect(transport.sent.last, {
      'type': 'invite_response',
      'toId': 'carol',
      'accepted': true,
    });
  });
}
