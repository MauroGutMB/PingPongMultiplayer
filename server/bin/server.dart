import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:pingpong_server/lobby.dart';
import 'package:pingpong_server/match_room.dart';
import 'package:pingpong_server/protocol.dart';

const _uuid = Uuid();

void main(List<String> args) async {
  final lobby = Lobby();
  final matchService = MatchService();
  final handler = webSocketHandler((WebSocketChannel channel, String? _) {
    _handleConnection(channel, lobby, matchService);
  });

  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  print('PingPong lobby server listening on ws://${server.address.host}:${server.port}');
}

void _handleConnection(
  WebSocketChannel channel,
  Lobby lobby,
  MatchService matchService,
) {
  String? playerId;

  channel.stream.listen(
    (raw) {
      final envelope = decodeEnvelope(raw as String);

      if (envelope.type == MessageType.hello) {
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
        return;
      }

      final currentId = playerId;
      if (currentId == null) return; // must send hello first

      switch (envelope.type) {
        case MessageType.inviteRequest:
          matchService.handleInviteRequest(lobby, currentId, envelope.body);
        case MessageType.inviteResponse:
          matchService.handleInviteResponse(lobby, currentId, envelope.body);
        case MessageType.paddleState:
        case MessageType.ballState:
        case MessageType.scoreUpdate:
        case MessageType.matchEnd:
          matchService.relay(currentId, envelope.body);
        case MessageType.hello:
        case MessageType.welcome:
        case MessageType.playerList:
        case MessageType.matchStart:
        case MessageType.opponentDisconnected:
          // Server-only outbound message types; ignore if a client sends one.
          break;
      }
    },
    onDone: () => _handleDisconnect(playerId, lobby, matchService),
    onError: (Object _) => _handleDisconnect(playerId, lobby, matchService),
    cancelOnError: true,
  );
}

void _handleDisconnect(String? playerId, Lobby lobby, MatchService matchService) {
  if (playerId == null) return;
  matchService.handleDisconnect(playerId);
  lobby.remove(playerId);
}
