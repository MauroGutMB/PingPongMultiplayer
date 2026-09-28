/// Message types exchanged over the lobby/match WebSocket.
///
/// See specs/01-protocol.md for the authoritative description of each type.
library;

import 'dart:convert';

enum MessageType {
  hello('hello'),
  welcome('welcome'),
  playerList('player_list'),
  inviteRequest('invite_request'),
  inviteResponse('invite_response'),
  matchStart('match_start'),
  paddleState('paddle_state'),
  ballState('ball_state'),
  scoreUpdate('score_update'),
  matchEnd('match_end'),
  opponentDisconnected('opponent_disconnected');

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

/// client -> server: request to invite [toId] into a match.
class InviteRequestMessage {
  InviteRequestMessage({required this.toId});

  factory InviteRequestMessage.fromJson(Map<String, dynamic> json) {
    return InviteRequestMessage(toId: json['toId'] as String);
  }

  final String toId;
}

/// server -> client: notifies [toId] that [fromId] ([fromNickname]) invited them.
class InviteRequestNotification {
  InviteRequestNotification({required this.fromId, required this.fromNickname});

  final String fromId;
  final String fromNickname;

  Map<String, dynamic> toJson() => {
    'type': MessageType.inviteRequest.wireName,
    'fromId': fromId,
    'fromNickname': fromNickname,
  };
}

/// client -> server: accept/reject the invite from [toId] (the original inviter).
class InviteResponseMessage {
  InviteResponseMessage({required this.toId, required this.accepted});

  factory InviteResponseMessage.fromJson(Map<String, dynamic> json) {
    return InviteResponseMessage(
      toId: json['toId'] as String,
      accepted: json['accepted'] as bool,
    );
  }

  final String toId;
  final bool accepted;
}

/// server -> client: forwards [fromId]'s accept/reject decision to the inviter.
class InviteResponseNotification {
  InviteResponseNotification({required this.fromId, required this.accepted});

  final String fromId;
  final bool accepted;

  Map<String, dynamic> toJson() => {
    'type': MessageType.inviteResponse.wireName,
    'fromId': fromId,
    'accepted': accepted,
  };
}

/// server -> client: a match was created; tells the client which side it plays.
class MatchStartMessage {
  MatchStartMessage({required this.matchId, required this.side});

  final String matchId;
  final String side; // "top" | "bottom"

  Map<String, dynamic> toJson() => {
    'type': MessageType.matchStart.wireName,
    'matchId': matchId,
    'side': side,
  };
}

/// server -> client: the opponent's socket dropped mid-match.
class OpponentDisconnectedMessage {
  Map<String, dynamic> toJson() => {
    'type': MessageType.opponentDisconnected.wireName,
  };
}

/// Decodes a raw WebSocket text frame into its `type` field and body.
({MessageType type, Map<String, dynamic> body}) decodeEnvelope(String raw) {
  final json = jsonDecode(raw) as Map<String, dynamic>;
  final type = MessageType.fromWireName(json['type'] as String);
  return (type: type, body: json);
}
