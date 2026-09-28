import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:pingpong_server/lobby.dart';
import 'package:pingpong_server/protocol.dart';

const _uuid = Uuid();

void main(List<String> args) async {
  final lobby = Lobby();
  final handler = webSocketHandler((WebSocketChannel channel, String? _) {
    _handleConnection(channel, lobby);
  });

  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  print('PingPong lobby server listening on ws://${server.address.host}:${server.port}');
}

void _handleConnection(WebSocketChannel channel, Lobby lobby) {
  String? playerId;

  channel.stream.listen(
    (raw) {
      final envelope = decodeEnvelope(raw as String);
      switch (envelope.type) {
        case MessageType.hello:
          if (playerId != null) return; // already registered
          final hello = HelloMessage.fromJson(envelope.body);
          playerId = _uuid.v4();
          final connection = PlayerConnection(
            id: playerId!,
            nickname: hello.nickname,
            sendJson: (message) => channel.sink.add(jsonEncode(message)),
          );
          lobby.register(connection);
          connection.send(WelcomeMessage(playerId: playerId!).toJson());
        case MessageType.welcome:
        case MessageType.playerList:
          // Server-only outbound message types; ignore if a client sends one.
          break;
      }
    },
    onDone: () {
      if (playerId != null) lobby.remove(playerId!);
    },
    onError: (Object _) {
      if (playerId != null) lobby.remove(playerId!);
    },
    cancelOnError: true,
  );
}
