import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:pingpong_server/lobby.dart';
import 'package:pingpong_server/match_room.dart';
import 'package:pingpong_server/protocol.dart';

const _uuid = Uuid();

// shelf_web_socket's onConnection callback only gets the channel, not the
// originating Request — so the client's IP is threaded through via a Zone
// value set on the request handler that wraps it, one per HTTP upgrade.
const _remoteIpKey = #remoteIp;

void main(List<String> args) {
  // Belt-and-suspenders alongside the try/catch in _handleConnection: any
  // stray uncaught async error anywhere in the server (this isolate has no
  // other supervisor) is logged instead of killing the whole process — on
  // Render that would mean every connected player getting dropped at once.
  runZonedGuarded(
    () async {
      final lobby = Lobby();
      final matchService = MatchService();
      final wsHandler = webSocketHandler((WebSocketChannel channel, String? _) {
        final ip = Zone.current[_remoteIpKey] as String? ?? 'desconhecido';
        _handleConnection(channel, lobby, matchService, ip);
      });

      FutureOr<Response> handler(Request request) {
        final connectionInfo =
            request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
        final ip = connectionInfo?.remoteAddress.address;
        return runZoned(
          () => wsHandler(request),
          zoneValues: {_remoteIpKey: ip},
        );
      }

      final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
      final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
      print('PingPong lobby server listening on ws://${server.address.host}:${server.port}');
    },
    (error, stackTrace) {
      print('Erro não tratado: $error\n$stackTrace');
    },
  );
}

void _handleConnection(
  WebSocketChannel channel,
  Lobby lobby,
  MatchService matchService,
  String remoteIp,
) {
  String? playerId;

  channel.stream.listen(
    (raw) {
      // A malformed frame or an unrecognized message type (e.g. a client
      // built against a newer/older protocol version than this server) must
      // never escape as an uncaught async error: this callback runs outside
      // shelf's own per-request error handling (the HTTP upgrade already
      // completed), so an uncaught throw here would take down the whole
      // isolate — every connected player, not just this one.
      try {
        final envelope = decodeEnvelope(raw as String);

        if (envelope.type == MessageType.hello) {
          if (playerId != null) return; // already registered
          final hello = HelloMessage.fromJson(envelope.body);
          playerId = _uuid.v4();
          final connection = PlayerConnection(
            id: playerId!,
            nickname: hello.nickname,
            ip: remoteIp,
            sendJson: (message) => channel.sink.add(jsonEncode(message)),
          );
          lobby.register(connection);
          connection.send(WelcomeMessage(playerId: playerId!).toJson());
          return;
        }

        final currentId = playerId;
        if (currentId == null) return; // must send hello first

        switch (envelope.type) {
          case MessageType.requestPlayerList:
            lobby.sendPlayerListTo(currentId);
          case MessageType.inviteRequest:
            matchService.handleInviteRequest(lobby, currentId, envelope.body);
          case MessageType.inviteResponse:
            matchService.handleInviteResponse(lobby, currentId, envelope.body);
          case MessageType.paddleState:
          case MessageType.ballState:
          case MessageType.scoreUpdate:
          case MessageType.matchEnd:
            matchService.relay(currentId, envelope.body);
          case MessageType.leaveMatch:
            final connection = matchService.leaveMatch(currentId);
            if (connection != null) lobby.register(connection);
          case MessageType.hello:
          case MessageType.welcome:
          case MessageType.playerList:
          case MessageType.matchStart:
          case MessageType.opponentDisconnected:
            // Server-only outbound message types; ignore if a client sends one.
            break;
        }
      } catch (e) {
        print('Mensagem inválida ignorada de $remoteIp: $e');
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
  matchService.cancelPendingInvitesFor(lobby, playerId);
  lobby.remove(playerId);
}
