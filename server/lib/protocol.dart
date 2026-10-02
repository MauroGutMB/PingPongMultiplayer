/// Message types exchanged over the lobby/match WebSocket.
library;

import 'dart:convert';

enum MessageType {
  hello('hello'),
  welcome('welcome'),
  playerList('player_list'),
  requestPlayerList('request_player_list'),
  inviteRequest('invite_request'),
  inviteResponse('invite_response'),
  matchStart('match_start'),
  paddleState('paddle_state'),
  ballState('ball_state'),
  scoreUpdate('score_update'),
  matchEnd('match_end'),
  opponentDisconnected('opponent_disconnected'),
  leaveMatch('leave_match'),
  requestMatchList('request_match_list'),
  matchList('match_list'),
  spectateRequest('spectate_request'),
  spectateSnapshot('spectate_snapshot'),
  spectateError('spectate_error'),
  leaveSpectate('leave_spectate'),
  spectatorCount('spectator_count'),
  matchEnded('match_ended');

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
  PlayerInfo({
    required this.id,
    required this.nickname,
    required this.ip,
    this.pendingInvite = false,
  });

  factory PlayerInfo.fromJson(Map<String, dynamic> json) {
    return PlayerInfo(
      id: json['id'] as String,
      nickname: json['nickname'] as String,
      ip: json['ip'] as String,
      pendingInvite: json['pendingInvite'] as bool? ?? false,
    );
  }

  final String id;
  final String nickname;
  final String ip;

  /// True while this player is either waiting on an invite they sent, or has
  /// just been asked by someone else and hasn't answered yet. Surfaced so
  /// other clients can grey the player out instead of letting a second
  /// inviter race the first one.
  final bool pendingInvite;

  Map<String, dynamic> toJson() => {
    'id': id,
    'nickname': nickname,
    'ip': ip,
    'pendingInvite': pendingInvite,
  };
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

/// Match settings the inviter picks when sending an invite: how fast the
/// ball moves, how many points end the match early (0 disables this and
/// falls back to the timer alone, matching the game's original behavior),
/// and how long the match runs. Chosen once by the inviter and carried
/// verbatim through invite_request -> match_start, never re-decided by the
/// invitee's own client — the half-court authority netcode requires both
/// sides to simulate with the exact same numbers, so there can only ever be
/// one source for them per match.
class MatchConfig {
  const MatchConfig({
    this.ballSpeedMultiplier = 1.0,
    this.winningScore = 0,
    this.durationSeconds = 120,
  });

  factory MatchConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const MatchConfig();
    return MatchConfig(
      ballSpeedMultiplier: (json['ballSpeedMultiplier'] as num?)?.toDouble() ?? 1.0,
      winningScore: json['winningScore'] as int? ?? 0,
      durationSeconds: json['durationSeconds'] as int? ?? 120,
    );
  }

  final double ballSpeedMultiplier;
  final int winningScore;
  final int durationSeconds;

  /// Clamps every field to a sane range before it's ever stored or relayed.
  /// The inviter's client only ever offers a few fixed presets, but the
  /// server is the only party that can't be bypassed, so it never trusts
  /// those presets arrived unmodified — a multiplier of 0 would freeze the
  /// ball in place forever, a negative or absurdly high winning score would
  /// end (or never end) the match instantly, and an unbounded duration would
  /// make a match that never times out.
  MatchConfig sanitized() {
    return MatchConfig(
      ballSpeedMultiplier: ballSpeedMultiplier.clamp(0.5, 2.0),
      winningScore: winningScore.clamp(0, 21),
      durationSeconds: durationSeconds.clamp(30, 600),
    );
  }

  Map<String, dynamic> toJson() => {
    'ballSpeedMultiplier': ballSpeedMultiplier,
    'winningScore': winningScore,
    'durationSeconds': durationSeconds,
  };
}

/// client -> server: request to invite [toId] into a match, with the
/// settings the inviter picked (or the defaults, if they didn't change any).
class InviteRequestMessage {
  InviteRequestMessage({required this.toId, this.config = const MatchConfig()});

  factory InviteRequestMessage.fromJson(Map<String, dynamic> json) {
    return InviteRequestMessage(
      toId: json['toId'] as String,
      config: MatchConfig.fromJson(json['config'] as Map<String, dynamic>?),
    );
  }

  final String toId;
  final MatchConfig config;
}

/// server -> client: notifies [toId] that [fromId] ([fromNickname]) invited
/// them, with the (already sanitized) match settings they'd be accepting.
class InviteRequestNotification {
  InviteRequestNotification({
    required this.fromId,
    required this.fromNickname,
    this.config = const MatchConfig(),
  });

  final String fromId;
  final String fromNickname;
  final MatchConfig config;

  Map<String, dynamic> toJson() => {
    'type': MessageType.inviteRequest.wireName,
    'fromId': fromId,
    'fromNickname': fromNickname,
    'config': config.toJson(),
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

/// server -> client: forwards [fromId]'s accept/reject decision to the
/// inviter — or, if [disconnected] is true, tells the inviter that [fromId]
/// left before ever responding (so a pending invite doesn't wait forever).
class InviteResponseNotification {
  InviteResponseNotification({
    required this.fromId,
    required this.accepted,
    this.disconnected = false,
  });

  final String fromId;
  final bool accepted;
  final bool disconnected;

  Map<String, dynamic> toJson() => {
    'type': MessageType.inviteResponse.wireName,
    'fromId': fromId,
    'accepted': accepted,
    'disconnected': disconnected,
  };
}

/// server -> client: a match was created; tells the client which side it
/// plays and the settings (already sanitized) both sides must simulate with.
class MatchStartMessage {
  MatchStartMessage({
    required this.matchId,
    required this.side,
    this.config = const MatchConfig(),
  });

  final String matchId;
  final String side; // "top" | "bottom"
  final MatchConfig config;

  Map<String, dynamic> toJson() => {
    'type': MessageType.matchStart.wireName,
    'matchId': matchId,
    'side': side,
    'config': config.toJson(),
  };
}

/// server -> client: the opponent's socket dropped mid-match.
class OpponentDisconnectedMessage {
  Map<String, dynamic> toJson() => {
    'type': MessageType.opponentDisconnected.wireName,
  };
}

/// A match currently in progress, as summarized for lobby clients deciding
/// whether to spectate it.
class MatchSummary {
  MatchSummary({
    required this.matchId,
    required this.bottomId,
    required this.bottomNickname,
    required this.topId,
    required this.topNickname,
    required this.spectatorCount,
  });

  final String matchId;
  final String bottomId;
  final String bottomNickname;
  final String topId;
  final String topNickname;
  final int spectatorCount;

  Map<String, dynamic> toJson() => {
    'matchId': matchId,
    'bottomId': bottomId,
    'bottomNickname': bottomNickname,
    'topId': topId,
    'topNickname': topNickname,
    'spectatorCount': spectatorCount,
  };
}

/// server -> client: the current set of in-progress matches, for the lobby's
/// "Partidas iniciadas" list. Sent right after welcome, in response to
/// request_match_list, and whenever a match starts, ends, or its spectator
/// count changes.
class MatchListMessage {
  MatchListMessage({required this.matches});

  final List<MatchSummary> matches;

  Map<String, dynamic> toJson() => {
    'type': MessageType.matchList.wireName,
    'matches': matches.map((m) => m.toJson()).toList(),
  };
}

/// client -> server: ask to join [matchId] as a read-only spectator.
class SpectateRequestMessage {
  SpectateRequestMessage({required this.matchId});

  factory SpectateRequestMessage.fromJson(Map<String, dynamic> json) {
    return SpectateRequestMessage(matchId: json['matchId'] as String);
  }

  final String matchId;
}

/// server -> client: the full current state of a match, sent once right
/// after a spectate_request is accepted so the spectator's screen starts in
/// sync. After this, incremental paddle_state/ball_state/score_update
/// messages (tagged with `from`) keep it in sync — never a second full
/// snapshot — which is what prevents the spectator from ever reconciling two
/// different "full truths" against each other.
class SpectateSnapshotMessage {
  SpectateSnapshotMessage({
    required this.matchId,
    required this.bottomId,
    required this.bottomNickname,
    required this.topId,
    required this.topNickname,
    required this.ballX,
    required this.ballY,
    required this.ballVX,
    required this.ballVY,
    required this.paddleBottomX,
    required this.paddleTopX,
    required this.scoreBottom,
    required this.scoreTop,
    required this.remainingSeconds,
    required this.spectatorCount,
  });

  final String matchId;
  final String bottomId;
  final String bottomNickname;
  final String topId;
  final String topNickname;
  final double ballX;
  final double ballY;
  final double ballVX;
  final double ballVY;
  final double paddleBottomX;
  final double paddleTopX;
  final int scoreBottom;
  final int scoreTop;
  final int remainingSeconds;
  final int spectatorCount;

  Map<String, dynamic> toJson() => {
    'type': MessageType.spectateSnapshot.wireName,
    'matchId': matchId,
    'bottomId': bottomId,
    'bottomNickname': bottomNickname,
    'topId': topId,
    'topNickname': topNickname,
    'ballX': ballX,
    'ballY': ballY,
    'ballVX': ballVX,
    'ballVY': ballVY,
    'paddleBottomX': paddleBottomX,
    'paddleTopX': paddleTopX,
    'scoreBottom': scoreBottom,
    'scoreTop': scoreTop,
    'remainingSeconds': remainingSeconds,
    'spectatorCount': spectatorCount,
  };
}

/// server -> client: rejects a spectate_request with a human readable reason.
/// Sent instead of a snapshot whenever the request fails any server side
/// rule, since the server is the only party ever trusted to decide this.
class SpectateErrorMessage {
  SpectateErrorMessage({required this.reason});

  final String reason;

  Map<String, dynamic> toJson() => {
    'type': MessageType.spectateError.wireName,
    'reason': reason,
  };
}

/// server -> client (broadcast to a match's two players and every current
/// spectator): the spectator count changed. The server is the only party
/// that ever counts, so every recipient always agrees on the same number.
class SpectatorCountMessage {
  SpectatorCountMessage({required this.matchId, required this.count});

  final String matchId;
  final int count;

  Map<String, dynamic> toJson() => {
    'type': MessageType.spectatorCount.wireName,
    'matchId': matchId,
    'count': count,
  };
}

/// server -> spectators only: the match they were watching has ended (either
/// it finished naturally or one of the players left), with the last known
/// score, so their screen can show the result and return them to the lobby.
class MatchEndedMessage {
  MatchEndedMessage({
    required this.matchId,
    required this.scoreBottom,
    required this.scoreTop,
    required this.reason,
  });

  final String matchId;
  final int scoreBottom;
  final int scoreTop;

  /// "finished" (clock ran out) or "player_left" (disconnect or leave_match).
  final String reason;

  Map<String, dynamic> toJson() => {
    'type': MessageType.matchEnded.wireName,
    'matchId': matchId,
    'scoreBottom': scoreBottom,
    'scoreTop': scoreTop,
    'reason': reason,
  };
}

/// Decodes a raw WebSocket text frame into its `type` field and body.
({MessageType type, Map<String, dynamic> body}) decodeEnvelope(String raw) {
  final json = jsonDecode(raw) as Map<String, dynamic>;
  final type = MessageType.fromWireName(json['type'] as String);
  return (type: type, body: json);
}
