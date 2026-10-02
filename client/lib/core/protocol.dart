/// Message shapes exchanged over the lobby/match WebSocket.
library;

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
  /// just been asked by someone else and hasn't answered yet.
  final bool pendingInvite;
}

/// A match currently in progress, as listed in the lobby's "Partidas
/// iniciadas" container.
class MatchSummary {
  MatchSummary({
    required this.matchId,
    required this.bottomId,
    required this.bottomNickname,
    required this.topId,
    required this.topNickname,
    required this.spectatorCount,
  });

  factory MatchSummary.fromJson(Map<String, dynamic> json) {
    return MatchSummary(
      matchId: json['matchId'] as String,
      bottomId: json['bottomId'] as String,
      bottomNickname: json['bottomNickname'] as String,
      topId: json['topId'] as String,
      topNickname: json['topNickname'] as String,
      spectatorCount: json['spectatorCount'] as int,
    );
  }

  final String matchId;
  final String bottomId;
  final String bottomNickname;
  final String topId;
  final String topNickname;
  final int spectatorCount;
}

/// Match settings the inviter picks when sending an invite: ball speed,
/// points needed to win early (0 = no limit, just play out the clock), and
/// match duration. The invitee never picks their own copy — the server
/// echoes back whatever the inviter sent (sanitized) in match_start, so both
/// sides of the half-court netcode always simulate with identical numbers.
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

  Map<String, dynamic> toJson() => {
    'ballSpeedMultiplier': ballSpeedMultiplier,
    'winningScore': winningScore,
    'durationSeconds': durationSeconds,
  };
}

Map<String, dynamic> helloMessage(String nickname) => {
  'type': 'hello',
  'nickname': nickname,
};

Map<String, dynamic> requestPlayerListMessage() => {
  'type': 'request_player_list',
};

Map<String, dynamic> requestMatchListMessage() => {
  'type': 'request_match_list',
};

Map<String, dynamic> inviteRequestMessage(String toId, [MatchConfig config = const MatchConfig()]) => {
  'type': 'invite_request',
  'toId': toId,
  'config': config.toJson(),
};

Map<String, dynamic> inviteResponseMessage(String toId, bool accepted) => {
  'type': 'invite_response',
  'toId': toId,
  'accepted': accepted,
};

Map<String, dynamic> spectateRequestMessage(String matchId) => {
  'type': 'spectate_request',
  'matchId': matchId,
};

Map<String, dynamic> leaveSpectateMessage() => {'type': 'leave_spectate'};
