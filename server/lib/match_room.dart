import 'package:uuid/uuid.dart';

import 'lobby.dart';
import 'protocol.dart';

const _uuid = Uuid();

/// Two matched players and their assigned sides, plus whatever spectators are
/// currently watching and the last known game state. The server never
/// inspects gameplay traffic to run physics; the cached ball/paddle/score
/// fields below are only ever *copied* from values the clients themselves
/// already computed, as messages are relayed through — purely so a spectator
/// who joins mid-match can be handed a sensible starting snapshot instead of
/// a stale "everything at 0.5/0/0" screen.
class MatchRoom {
  MatchRoom({
    required this.matchId,
    required this.bottom,
    required this.top,
    this.config = const MatchConfig(),
  }) : startedAt = DateTime.now();

  final String matchId;
  final PlayerConnection bottom;
  final PlayerConnection top;
  final MatchConfig config;
  final DateTime startedAt;

  /// Keyed by spectator playerId, so joining twice (e.g. a reconnect) can
  /// never produce two entries for the same person.
  final Map<String, PlayerConnection> spectators = {};

  double ballX = 0.5;
  double ballY = 0.5;
  double ballVX = 0;
  double ballVY = 0;
  double paddleBottomX = 0.5;
  double paddleTopX = 0.5;
  int scoreBottom = 0;
  int scoreTop = 0;

  PlayerConnection? other(String playerId) {
    if (playerId == bottom.id) return top;
    if (playerId == top.id) return bottom;
    return null;
  }

  bool contains(String playerId) => playerId == bottom.id || playerId == top.id;

  /// "bottom" or "top" if [playerId] is one of the two players, else null —
  /// used to know which (unmirrored) half a relayed message came from.
  String? sideOf(String playerId) {
    if (playerId == bottom.id) return 'bottom';
    if (playerId == top.id) return 'top';
    return null;
  }

  int remainingSeconds() {
    final elapsed = DateTime.now().difference(startedAt).inSeconds;
    final remaining = config.durationSeconds - elapsed;
    return remaining > 0 ? remaining : 0;
  }
}

/// Handles the invite handshake, match creation, in-match message relay,
/// spectating, and mid-match disconnect cleanup.
class MatchService {
  final Map<String, MatchRoom> _roomByPlayer = {};

  /// spectatorId -> matchId, so a spectator can be found and removed in O(1)
  /// (on an explicit leave, a disconnect, or before joining a different
  /// match) without scanning every room.
  final Map<String, String> _matchIdBySpectator = {};

  /// toId -> the pending invite naming them, not yet accepted/rejected. Only
  /// one pending invite per target is tracked, matching the client's own
  /// "one invite dialog at a time" UI. Carries the sanitized match config
  /// alongside the inviter's id so it survives from invite_request all the
  /// way to the match_start both sides receive if it's accepted — the
  /// invitee's client never gets a vote on these settings, only the
  /// inviter's original (sanitized) choice ever reaches either side.
  final Map<String, _PendingInvite> _pendingInviteFromByTarget = {};

  bool isInMatch(String playerId) => _roomByPlayer.containsKey(playerId);

  /// True while [playerId] is waiting on an invite they sent, or has one
  /// pending from someone else. Lets the lobby roster mark them unavailable
  /// instead of letting a second player race the first invite.
  bool hasPendingInvite(String playerId) =>
      _pendingInviteFromByTarget.containsKey(playerId) ||
      _pendingInviteFromByTarget.values.any((p) => p.fromId == playerId);

  void handleInviteRequest(Lobby lobby, String fromId, Map<String, dynamic> body) {
    if (isInMatch(fromId)) return;
    final invite = InviteRequestMessage.fromJson(body);
    final inviter = lobby[fromId];
    final target = lobby[invite.toId];
    if (inviter == null || target == null || isInMatch(invite.toId)) return;
    // Sanitized once, here, and never re-validated or re-derived again —
    // every later step (the notification below, and match_start if accepted)
    // just forwards this same already-safe value.
    final config = invite.config.sanitized();
    _pendingInviteFromByTarget[invite.toId] = _PendingInvite(fromId: fromId, config: config);
    target.send(
      InviteRequestNotification(
        fromId: fromId,
        fromNickname: inviter.nickname,
        config: config,
      ).toJson(),
    );
  }

  void handleInviteResponse(Lobby lobby, String fromId, Map<String, dynamic> body) {
    final response = InviteResponseMessage.fromJson(body);
    final pending = _pendingInviteFromByTarget.remove(fromId);
    final responder = lobby[fromId];
    final inviter = lobby[response.toId];
    if (responder == null || inviter == null) return;

    inviter.send(
      InviteResponseNotification(fromId: fromId, accepted: response.accepted).toJson(),
    );

    if (response.accepted && !isInMatch(fromId) && !isInMatch(response.toId)) {
      _startMatch(
        lobby,
        inviter: inviter,
        invitee: responder,
        config: pending?.config ?? const MatchConfig(),
      );
    }
  }

  /// Called when [playerId] disconnects while a lobby-level invite naming
  /// them is still unanswered, so nobody is left waiting forever:
  ///  - if they were the *target* of a pending invite, the inviter is told
  ///    (as an implicit rejection) instead of waiting on a reply that will
  ///    never come;
  ///  - if they were the *inviter*, the pending record is just dropped —
  ///    the target's own invite dialog has Accept/Reject either way and
  ///    isn't blocking anything.
  void cancelPendingInvitesFor(Lobby lobby, String playerId) {
    final pending = _pendingInviteFromByTarget.remove(playerId);
    if (pending != null) {
      lobby[pending.fromId]?.send(
        InviteResponseNotification(
          fromId: playerId,
          accepted: false,
          disconnected: true,
        ).toJson(),
      );
    }
    _pendingInviteFromByTarget.removeWhere((_, invite) => invite.fromId == playerId);
  }

  void _startMatch(
    Lobby lobby, {
    required PlayerConnection inviter,
    required PlayerConnection invitee,
    MatchConfig config = const MatchConfig(),
  }) {
    // Either side might currently be watching some other match — accepting
    // an invite always takes priority, so drop that spectate slot instead of
    // leaving a phantom entry nobody will ever clean up.
    removeSpectator(inviter.id);
    removeSpectator(invitee.id);

    final room = MatchRoom(
      matchId: _uuid.v4(),
      bottom: inviter,
      top: invitee,
      config: config,
    );
    _roomByPlayer[inviter.id] = room;
    _roomByPlayer[invitee.id] = room;

    // Matched players stop appearing in the lobby's player_list.
    lobby.remove(inviter.id);
    lobby.remove(invitee.id);

    // Both sides get the exact same (already sanitized) config the inviter
    // picked — neither client decides this locally, since the half-court
    // netcode requires both halves to simulate with identical numbers.
    inviter.send(
      MatchStartMessage(matchId: room.matchId, side: 'bottom', config: config).toJson(),
    );
    invitee.send(
      MatchStartMessage(matchId: room.matchId, side: 'top', config: config).toJson(),
    );
  }

  /// Every in-progress match, for the lobby's "Partidas iniciadas" list.
  List<MatchSummary> listActiveMatches() {
    final seen = <String>{};
    final summaries = <MatchSummary>[];
    for (final room in _roomByPlayer.values) {
      if (!seen.add(room.matchId)) continue; // each room is keyed twice
      summaries.add(
        MatchSummary(
          matchId: room.matchId,
          bottomId: room.bottom.id,
          bottomNickname: room.bottom.nickname,
          topId: room.top.id,
          topNickname: room.top.nickname,
          spectatorCount: room.spectators.length,
        ),
      );
    }
    return summaries;
  }

  void sendMatchListTo(Lobby lobby, String playerId) {
    lobby[playerId]?.send(MatchListMessage(matches: listActiveMatches()).toJson());
  }

  /// Looks a player's connection up in the lobby first (the common case),
  /// falling back to their own match room — a player currently in a match
  /// was already removed from the lobby's roster when that match started,
  /// but still needs a reply when their own spectate_request is rejected.
  PlayerConnection? _connectionFor(Lobby lobby, String playerId) {
    final inLobby = lobby[playerId];
    if (inLobby != null) return inLobby;
    final room = _roomByPlayer[playerId];
    if (room == null) return null;
    return playerId == room.bottom.id ? room.bottom : room.top;
  }

  MatchRoom? _roomById(String matchId) {
    for (final room in _roomByPlayer.values) {
      if (room.matchId == matchId) return room;
    }
    return null;
  }

  /// Validates and processes a spectate_request. Every rule here is enforced
  /// on the server, never just by hiding buttons on the client: the client is
  /// not a trusted boundary, so a modified or scripted client could otherwise
  /// send spectate_request for a finished match, or send paddle_state/
  /// ball_state while only "spectating" and corrupt a match it has no
  /// business touching. Hiding the option in the UI is a convenience for
  /// honest clients, not a security control.
  void handleSpectateRequest(Lobby lobby, String spectatorId, Map<String, dynamic> body) {
    final spectator = _connectionFor(lobby, spectatorId);
    if (spectator == null) return;
    final request = SpectateRequestMessage.fromJson(body);
    final room = _roomById(request.matchId);

    if (room == null) {
      spectator.send(
        SpectateErrorMessage(reason: 'Esta partida não está mais em andamento.').toJson(),
      );
      return;
    }
    if (room.contains(spectatorId)) {
      spectator.send(
        SpectateErrorMessage(reason: 'Você já é jogador desta partida.').toJson(),
      );
      return;
    }
    if (isInMatch(spectatorId)) {
      spectator.send(
        SpectateErrorMessage(
          reason: 'Saia da sua partida atual antes de espectar outra.',
        ).toJson(),
      );
      return;
    }

    // A spectator only ever watches one match at a time: switching to a new
    // one (or re-sending the same request, e.g. after a reconnect) replaces
    // the old entry instead of stacking a second one under the same id.
    removeSpectator(spectatorId);

    room.spectators[spectatorId] = spectator;
    _matchIdBySpectator[spectatorId] = room.matchId;

    // One full snapshot right now, then only incremental relay messages from
    // here on — never a second snapshot. Two independently-timed "full
    // truths" could disagree with each other (and with the incremental
    // updates already in flight), which is exactly the inconsistency a
    // snapshot-then-delta model avoids.
    spectator.send(
      SpectateSnapshotMessage(
        matchId: room.matchId,
        bottomId: room.bottom.id,
        bottomNickname: room.bottom.nickname,
        topId: room.top.id,
        topNickname: room.top.nickname,
        ballX: room.ballX,
        ballY: room.ballY,
        ballVX: room.ballVX,
        ballVY: room.ballVY,
        paddleBottomX: room.paddleBottomX,
        paddleTopX: room.paddleTopX,
        scoreBottom: room.scoreBottom,
        scoreTop: room.scoreTop,
        remainingSeconds: room.remainingSeconds(),
        spectatorCount: room.spectators.length,
      ).toJson(),
    );

    _broadcastSpectatorCount(room);
  }

  /// Removes [playerId] from whatever match they're spectating, if any — a
  /// no-op otherwise. Called on an explicit leave_spectate, on disconnect,
  /// and before adding someone as a spectator or player elsewhere (so the
  /// same person never ends up counted twice).
  void removeSpectator(String playerId) {
    final matchId = _matchIdBySpectator.remove(playerId);
    if (matchId == null) return;
    final room = _roomById(matchId);
    if (room == null) return;
    if (room.spectators.remove(playerId) != null) {
      _broadcastSpectatorCount(room);
    }
  }

  /// The server is the single source of truth for the spectator count — it
  /// owns the one `spectators` map a room has, so there's nothing for two
  /// clients to disagree about. Two people spectating "at the same time"
  /// still arrive as two separate, sequential spectate_request messages on
  /// this single-threaded event loop, so there's no race to resolve: each
  /// is handled to completion (map insert, then this broadcast) before the
  /// next one is read off the socket.
  void _broadcastSpectatorCount(MatchRoom room) {
    final message = SpectatorCountMessage(
      matchId: room.matchId,
      count: room.spectators.length,
    ).toJson();
    room.bottom.send(message);
    room.top.send(message);
    for (final spectator in room.spectators.values) {
      spectator.send(message);
    }
  }

  /// Forwards an in-match message verbatim to the sender's opponent, exactly
  /// as before, and additionally fans a tagged copy out to every spectator
  /// while caching the values onto the room for the next spectator's
  /// snapshot. Used for paddle_state, ball_state and score_update.
  void relay(String fromId, Map<String, dynamic> body) {
    final room = _roomByPlayer[fromId];
    if (room == null) return;
    room.other(fromId)?.send(body);
    _cacheAndFanOutToSpectators(room, fromId, body);
  }

  void _cacheAndFanOutToSpectators(
    MatchRoom room,
    String fromId,
    Map<String, dynamic> body,
  ) {
    final fromBottom = fromId == room.bottom.id;
    switch (body['type']) {
      case 'ball_state':
        final x = (body['x'] as num).toDouble();
        final y = (body['y'] as num).toDouble();
        final vx = (body['vx'] as num).toDouble();
        final vy = (body['vy'] as num).toDouble();
        room.ballX = x;
        // Each player's own x/y is egocentric ("my half" is always y >= 0.5);
        // only the bottom player's frame already matches the neutral
        // top/bottom frame a spectator needs, so the top player's y and vy
        // get flipped — the same transform applyOpponentBall does on the
        // client when one player's update reaches the other's screen.
        room.ballY = fromBottom ? y : 1 - y;
        room.ballVX = vx;
        room.ballVY = fromBottom ? vy : -vy;
      case 'paddle_state':
        final x = (body['x'] as num).toDouble();
        // Paddle x isn't mirrored between the two egocentric views, so it
        // needs no flip either way.
        if (fromBottom) {
          room.paddleBottomX = x;
        } else {
          room.paddleTopX = x;
        }
      case 'score_update':
      case 'match_end':
        // The sender computes these as absolute (neutral) values itself —
        // see GameSyncService.sendScoreUpdate on the client — so the server
        // just copies them instead of re-deriving who scored from a
        // payload-less event, which the wire format can't tell apart.
        // match_end carries the same two fields as its final tally.
        final scoreBottom = body['scoreBottom'];
        final scoreTop = body['scoreTop'];
        if (scoreBottom is num) room.scoreBottom = scoreBottom.toInt();
        if (scoreTop is num) room.scoreTop = scoreTop.toInt();
    }

    if (room.spectators.isEmpty) return;
    final tagged = {...body, 'from': fromBottom ? 'bottom' : 'top'};
    for (final spectator in room.spectators.values) {
      spectator.send(tagged);
    }
  }

  /// Called when a player's client reports the match naturally finished (its
  /// local clock ran out). Forwards the final score to the opponent like any
  /// other in-match message, tells spectators the match is over, and tears
  /// the room down. Safe to call twice — both clients run their own timer
  /// and may each report this independently — since the second call simply
  /// finds no room left under [fromId].
  void handleMatchEnd(String fromId, Map<String, dynamic> body) {
    final room = _roomByPlayer[fromId];
    if (room == null) return;
    relay(fromId, body);
    _roomByPlayer.remove(room.bottom.id);
    _roomByPlayer.remove(room.top.id);
    _notifySpectatorsRoomEnded(room, reason: 'finished');
  }

  /// Cleans up the match room and notifies the remaining player, if any.
  void handleDisconnect(String playerId) {
    _teardownRoom(playerId, reason: 'player_left');
  }

  /// Called when a player intentionally leaves an in-progress match (as
  /// opposed to a real disconnect). Tears down the room and notifies the
  /// opponent the same way [handleDisconnect] does, then returns the leaving
  /// player's own connection so the caller can put them back in the lobby.
  PlayerConnection? leaveMatch(String playerId) {
    final room = _teardownRoom(playerId, reason: 'player_left');
    if (room == null) return null;
    return playerId == room.bottom.id ? room.bottom : room.top;
  }

  MatchRoom? _teardownRoom(String playerId, {required String reason}) {
    final room = _roomByPlayer.remove(playerId);
    if (room == null) return null;
    final other = room.other(playerId);
    if (other != null) {
      _roomByPlayer.remove(other.id);
      other.send(OpponentDisconnectedMessage().toJson());
    }
    _notifySpectatorsRoomEnded(room, reason: reason);
    return room;
  }

  void _notifySpectatorsRoomEnded(MatchRoom room, {required String reason}) {
    if (room.spectators.isEmpty) return;
    final ended = MatchEndedMessage(
      matchId: room.matchId,
      scoreBottom: room.scoreBottom,
      scoreTop: room.scoreTop,
      reason: reason,
    ).toJson();
    for (final spectatorId in room.spectators.keys.toList()) {
      room.spectators[spectatorId]!.send(ended);
      _matchIdBySpectator.remove(spectatorId);
    }
    room.spectators.clear();
  }
}

/// A not-yet-answered invite: who sent it, and the match settings it would
/// start with if accepted.
class _PendingInvite {
  _PendingInvite({required this.fromId, required this.config});

  final String fromId;
  final MatchConfig config;
}
