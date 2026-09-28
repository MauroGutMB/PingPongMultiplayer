import 'package:uuid/uuid.dart';

import 'lobby.dart';
import 'protocol.dart';

const _uuid = Uuid();

/// Two matched players and their assigned sides. The server never inspects
/// gameplay traffic beyond routing it to whichever of these two is not the
/// sender; physics stays entirely client-side.
class MatchRoom {
  MatchRoom({required this.matchId, required this.bottom, required this.top});

  final String matchId;
  final PlayerConnection bottom;
  final PlayerConnection top;

  PlayerConnection? other(String playerId) {
    if (playerId == bottom.id) return top;
    if (playerId == top.id) return bottom;
    return null;
  }

  bool contains(String playerId) => playerId == bottom.id || playerId == top.id;
}

/// Handles the invite handshake, match creation, in-match message relay, and
/// mid-match disconnect cleanup.
class MatchService {
  final Map<String, MatchRoom> _roomByPlayer = {};

  bool isInMatch(String playerId) => _roomByPlayer.containsKey(playerId);

  void handleInviteRequest(Lobby lobby, String fromId, Map<String, dynamic> body) {
    if (isInMatch(fromId)) return;
    final invite = InviteRequestMessage.fromJson(body);
    final inviter = lobby[fromId];
    final target = lobby[invite.toId];
    if (inviter == null || target == null || isInMatch(invite.toId)) return;
    target.send(
      InviteRequestNotification(fromId: fromId, fromNickname: inviter.nickname).toJson(),
    );
  }

  void handleInviteResponse(Lobby lobby, String fromId, Map<String, dynamic> body) {
    final response = InviteResponseMessage.fromJson(body);
    final responder = lobby[fromId];
    final inviter = lobby[response.toId];
    if (responder == null || inviter == null) return;

    inviter.send(
      InviteResponseNotification(fromId: fromId, accepted: response.accepted).toJson(),
    );

    if (response.accepted && !isInMatch(fromId) && !isInMatch(response.toId)) {
      _startMatch(lobby, inviter: inviter, invitee: responder);
    }
  }

  void _startMatch(
    Lobby lobby, {
    required PlayerConnection inviter,
    required PlayerConnection invitee,
  }) {
    final room = MatchRoom(matchId: _uuid.v4(), bottom: inviter, top: invitee);
    _roomByPlayer[inviter.id] = room;
    _roomByPlayer[invitee.id] = room;

    // Matched players stop appearing in the lobby's player_list.
    lobby.remove(inviter.id);
    lobby.remove(invitee.id);

    inviter.send(MatchStartMessage(matchId: room.matchId, side: 'bottom').toJson());
    invitee.send(MatchStartMessage(matchId: room.matchId, side: 'top').toJson());
  }

  /// Forwards an in-match message verbatim to the sender's opponent.
  /// Used for paddle_state, ball_state, score_update, match_end.
  void relay(String fromId, Map<String, dynamic> body) {
    final room = _roomByPlayer[fromId];
    room?.other(fromId)?.send(body);
  }

  /// Cleans up the match room and notifies the remaining player, if any.
  void handleDisconnect(String playerId) {
    final room = _roomByPlayer.remove(playerId);
    if (room == null) return;
    final other = room.other(playerId);
    if (other != null) {
      _roomByPlayer.remove(other.id);
      other.send(OpponentDisconnectedMessage().toJson());
    }
  }
}
