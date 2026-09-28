/// Message types exchanged over the lobby WebSocket.
///
/// Only the presence/lobby subset (etapa 1 de specs/03-implementation-order.md)
/// is implemented here. Invite and match-relay message types are added in
/// etapa 2.
library;

import 'dart:convert';

enum MessageType {
  hello('hello'),
  welcome('welcome'),
  playerList('player_list');

  const MessageType(this.wireName);

  final String wireName;

  static MessageType fromWireName(String value) {
    return MessageType.values.firstWhere(
      (type) => type.wireName == value,
      orElse: () => throw FormatException('Unknown message type: $value'),
    );
  }
}

/// A player entry as broadcast in [PlayerListMessage].
class PlayerInfo {
  PlayerInfo({required this.id, required this.nickname});

  factory PlayerInfo.fromJson(Map<String, dynamic> json) {
    return PlayerInfo(
      id: json['id'] as String,
      nickname: json['nickname'] as String,
    );
  }

  final String id;
  final String nickname;

  Map<String, dynamic> toJson() => {'id': id, 'nickname': nickname};
}

/// client -> server: first message on connect, registers the nickname.
class HelloMessage {
  HelloMessage({required this.nickname});

  factory HelloMessage.fromJson(Map<String, dynamic> json) {
    return HelloMessage(nickname: json['nickname'] as String);
  }

  final String nickname;
}

/// server -> client: assigns the connection's playerId.
class WelcomeMessage {
  WelcomeMessage({required this.playerId});

  final String playerId;

  Map<String, dynamic> toJson() => {
    'type': MessageType.welcome.wireName,
    'playerId': playerId,
  };
}

/// server -> client (broadcast): current set of online players.
class PlayerListMessage {
  PlayerListMessage({required this.players});

  final List<PlayerInfo> players;

  Map<String, dynamic> toJson() => {
    'type': MessageType.playerList.wireName,
    'players': players.map((p) => p.toJson()).toList(),
  };
}

/// Decodes a raw WebSocket text frame into its `type` field and body.
({MessageType type, Map<String, dynamic> body}) decodeEnvelope(String raw) {
  final json = jsonDecode(raw) as Map<String, dynamic>;
  final type = MessageType.fromWireName(json['type'] as String);
  return (type: type, body: json);
}
