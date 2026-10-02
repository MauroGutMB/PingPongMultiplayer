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
      {'id': 'me', 'nickname': 'Alice', 'ip': '127.0.0.1'},
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
        {'id': 'bob', 'nickname': 'Bob', 'ip': '10.0.0.2'},
      ],
    );

    expect(transport.connected, isTrue);
    expect(transport.sent.single, {'type': 'hello', 'nickname': 'Alice'});
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Alice'), findsNothing);
    expect(find.text('10.0.0.2'), findsOneWidget);
  });

  testWidgets('tapping a player confirms and sends an invite_request', (
    tester,
  ) async {
    final transport = FakeLobbyTransport();
    await _enterLobby(
      tester,
      transport,
      players: [
        {'id': 'bob', 'nickname': 'Bob', 'ip': '10.0.0.2'},
      ],
    );

    await tester.tap(find.text('Bob'));
    await _pump(tester);
    expect(find.text('Convidar Bob para uma partida'), findsOneWidget);

    await tester.tap(find.text('Convidar'));
    // A single pump, not pumpAndSettle: the waiting dialog shows an
    // indeterminate CircularProgressIndicator, whose animation never settles.
    await tester.pump();
    await tester.pump();

    expect(transport.sent.last, {
      'type': 'invite_request',
      'toId': 'bob',
      'config': {'ballSpeedMultiplier': 1.0, 'winningScore': 0, 'durationSeconds': 120},
    });
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
        {'id': 'bob', 'nickname': 'Bob', 'ip': '10.0.0.2'},
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

  testWidgets(
    'invite target disconnecting before responding shows a distinct message '
    'and unblocks the waiting dialog',
    (tester) async {
      final transport = FakeLobbyTransport();
      await _enterLobby(
        tester,
        transport,
        players: [
          {'id': 'bob', 'nickname': 'Bob', 'ip': '10.0.0.2'},
        ],
      );

      await tester.tap(find.text('Bob'));
      await _pump(tester);
      await tester.tap(find.text('Convidar'));
      // A single pump, not pumpAndSettle: the waiting dialog shows an
      // indeterminate CircularProgressIndicator, whose animation never settles.
      await tester.pump();
      await tester.pump();
      expect(find.text('Aguardando resposta de Bob...'), findsOneWidget);

      transport.receive({
        'type': 'invite_response',
        'fromId': 'bob',
        'accepted': false,
        'disconnected': true,
      });
      // Not pumpAndSettle: it would also wait out the SnackBar's auto-dismiss
      // timer, so by the time we assert it would already be gone.
      await tester.pump();
      await tester.pump();

      expect(find.text('Aguardando resposta de Bob...'), findsNothing);
      expect(find.text('O jogador saiu antes de responder.'), findsOneWidget);
      expect(find.text('Seu convite foi recusado.'), findsNothing);
    },
  );

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

    expect(
      find.text('Carol te convidou para uma partida.\nBola Normal, sem limite de pontos, 2 min.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Aceitar'));
    await _pump(tester);

    expect(transport.sent.last, {
      'type': 'invite_response',
      'toId': 'carol',
      'accepted': true,
    });
  });

  testWidgets(
    'declining an incoming invite closes the popup cleanly and leaves the '
    'lobby fully visible and interactive',
    (tester) async {
      final transport = FakeLobbyTransport();
      await _enterLobby(
        tester,
        transport,
        players: [
          {'id': 'bob', 'nickname': 'Bob', 'ip': '10.0.0.2'},
        ],
      );

      transport.receive({
        'type': 'invite_request',
        'fromId': 'carol',
        'fromNickname': 'Carol',
      });
      await _pump(tester);
      const inviteText =
          'Carol te convidou para uma partida.\nBola Normal, sem limite de pontos, 2 min.';
      expect(find.text(inviteText), findsOneWidget);

      await tester.tap(find.text('Recusar'));
      await _pump(tester);

      expect(transport.sent.last, {
        'type': 'invite_response',
        'toId': 'carol',
        'accepted': false,
      });
      // The popup is gone and the ordinary lobby is back — no leftover
      // barrier, no stuck black overlay, nothing else covering the screen.
      expect(find.text(inviteText), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Bob'), findsOneWidget);

      // The lobby is still fully functional afterwards — tapping another
      // player still works normally.
      await tester.tap(find.text('Bob'));
      await _pump(tester);
      expect(find.text('Convidar Bob para uma partida'), findsOneWidget);
    },
  );

  testWidgets('refresh button sends both list requests and disables while in flight', (
    tester,
  ) async {
    final transport = FakeLobbyTransport();
    await _enterLobby(tester, transport);
    transport.sent.clear();

    final refreshButtonFinder = find.widgetWithIcon(IconButton, Icons.refresh);
    await tester.tap(refreshButtonFinder);
    await tester.pump();

    expect(transport.sent, [
      {'type': 'request_player_list'},
      {'type': 'request_match_list'},
    ]);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    transport.receive({'type': 'player_list', 'players': []});
    transport.receive({'type': 'match_list', 'matches': []});
    await _pump(tester);

    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(tester.widget<IconButton>(refreshButtonFinder).onPressed, isNotNull);
  });

  testWidgets('a player with a pending invite is shown disabled with a reason', (
    tester,
  ) async {
    final transport = FakeLobbyTransport();
    await _enterLobby(
      tester,
      transport,
      players: [
        {'id': 'bob', 'nickname': 'Bob', 'ip': '10.0.0.2', 'pendingInvite': true},
      ],
    );

    expect(find.text('Convite pendente'), findsOneWidget);
    await tester.tap(find.text('Bob'));
    await _pump(tester);
    // Disabled: tapping it never opens the invite confirmation dialog.
    expect(find.text('Convidar Bob para uma partida'), findsNothing);
  });

  testWidgets('lists in-progress matches and spectating sends a spectate_request', (
    tester,
  ) async {
    final transport = FakeLobbyTransport();
    await _enterLobby(tester, transport);

    transport.receive({
      'type': 'match_list',
      'matches': [
        {
          'matchId': 'm1',
          'bottomId': 'bob',
          'bottomNickname': 'Bob',
          'topId': 'carol',
          'topNickname': 'Carol',
          'spectatorCount': 2,
        },
      ],
    });
    await _pump(tester);

    expect(find.text('Bob x Carol'), findsOneWidget);
    expect(find.text('2 espectadores'), findsOneWidget);

    await tester.tap(find.text('Bob x Carol'));
    await _pump(tester);

    expect(transport.sent.last, {'type': 'spectate_request', 'matchId': 'm1'});
  });

  testWidgets('an empty match list shows a friendly message', (tester) async {
    final transport = FakeLobbyTransport();
    await _enterLobby(tester, transport);

    expect(find.text('Nenhuma partida em andamento no momento.'), findsOneWidget);
  });
}
