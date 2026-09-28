import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pingpong_client/core/gist_config_service.dart';
import 'package:pingpong_client/features/connect/connect_screen.dart';
import 'package:pingpong_client/features/lobby/lobby_provider.dart';
import 'package:pingpong_client/features/lobby/lobby_screen.dart';

class _FakeGistConfigService implements GistConfigService {
  _FakeGistConfigService(this._result);

  final Future<String> Function() _result;

  @override
  String get rawUrl => 'https://example.com/gist';

  @override
  Future<String> fetchServerUrl() => _result();
}

void main() {
  testWidgets('automatic mode fetches the gist URL and opens the lobby', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        gistConfigServiceProvider.overrideWithValue(
          _FakeGistConfigService(() async => 'ws://192.168.0.10:8080'),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ConnectScreen()),
      ),
    );

    await tester.tap(find.text('Conectar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Automática'));
    await tester.pumpAndSettle();

    expect(find.byType(LobbyScreen), findsOneWidget);
    expect(
      container.read(serverUrlProvider),
      'ws://192.168.0.10:8080',
    );
  });

  testWidgets('automatic mode shows an error when the server is offline', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        gistConfigServiceProvider.overrideWithValue(
          _FakeGistConfigService(
            () async => throw GistConfigException('O servidor está offline no momento.'),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ConnectScreen()),
      ),
    );

    await tester.tap(find.text('Conectar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Automática'));
    await tester.pumpAndSettle();

    expect(find.text('O servidor está offline no momento.'), findsOneWidget);
    expect(find.byType(LobbyScreen), findsNothing);
  });

  testWidgets('manual mode uses the typed URL and opens the lobby', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ConnectScreen()),
      ),
    );

    await tester.tap(find.text('Conectar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usar URL manual'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'ws://10.0.0.5:9000');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Conectar'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LobbyScreen), findsOneWidget);
    expect(container.read(serverUrlProvider), 'ws://10.0.0.5:9000');
  });
}
