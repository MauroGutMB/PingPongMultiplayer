import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/protocol.dart';
import '../../core/websocket_service.dart';

/// Lets the nickname prompt point at a different server than
/// [kDefaultServerUrl] (e.g. localhost during development), without a
/// rebuild.
class ServerUrlOverride extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String url) => state = url;
}

final serverUrlOverrideProvider = NotifierProvider<ServerUrlOverride, String?>(
  ServerUrlOverride.new,
);

final serverUrlProvider = Provider<String>((ref) {
  return ref.watch(serverUrlOverrideProvider) ?? kDefaultServerUrl;
});

final lobbyTransportProvider = Provider<LobbyTransport>((ref) {
  return WebSocketService(ref.watch(serverUrlProvider));
});

enum LobbyStatus { disconnected, connecting, connected, error }

class IncomingInvite {
  IncomingInvite({
    required this.fromId,
    required this.fromNickname,
    this.config = const MatchConfig(),
  });

  final String fromId;
  final String fromNickname;
  final MatchConfig config;
}

class MatchStart {
  MatchStart({required this.matchId, required this.side, this.config = const MatchConfig()});

  final String matchId;
  final String side;
  final MatchConfig config;
}

/// The full initial state handed to a newly accepted spectator — see
/// SpectateSnapshotMessage on the server. Carried once through [LobbyState]
/// just long enough to trigger navigation into the spectator screen, which
/// reads it to seed its own controller.
class SpectateSession {
  SpectateSession({
    required this.matchId,
    required this.bottomNickname,
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
  final String bottomNickname;
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
}

class LobbyState {
  const LobbyState({
    this.status = LobbyStatus.disconnected,
    this.myId,
    this.players = const [],
    this.matches = const [],
    this.incomingInvite,
    this.outgoingInviteToId,
    this.inviteRejected = false,
    this.inviteTargetLeft = false,
    this.matchStart,
    this.spectateSession,
    this.spectateError,
    this.isRefreshing = false,
    this.refreshFailed = false,
  });

  final LobbyStatus status;
  final String? myId;
  final List<PlayerInfo> players;

  /// Matches currently in progress, for the "Partidas iniciadas" container.
  final List<MatchSummary> matches;

  final IncomingInvite? incomingInvite;
  final String? outgoingInviteToId;
  final bool inviteRejected;

  /// True instead of [inviteRejected] when the invite went unanswered
  /// because the invited player disconnected, rather than an actual reject.
  final bool inviteTargetLeft;

  final MatchStart? matchStart;

  /// Set once a spectate_request is accepted; the lobby screen listens for
  /// this to navigate into the spectator screen, same pattern as
  /// [matchStart].
  final SpectateSession? spectateSession;

  /// A human readable reason the last spectate_request was rejected, shown
  /// once as a snackbar.
  final String? spectateError;

  /// True while the manual refresh button's request is in flight.
  final bool isRefreshing;

  /// True if the last manual refresh timed out without a server reply.
  final bool refreshFailed;

  List<PlayerInfo> get otherPlayers =>
      players.where((p) => p.id != myId).toList();

  LobbyState copyWith({
    LobbyStatus? status,
    String? myId,
    List<PlayerInfo>? players,
    List<MatchSummary>? matches,
    IncomingInvite? incomingInvite,
    bool clearIncomingInvite = false,
    String? outgoingInviteToId,
    bool clearOutgoingInvite = false,
    bool? inviteRejected,
    bool? inviteTargetLeft,
    MatchStart? matchStart,
    SpectateSession? spectateSession,
    bool clearSpectateSession = false,
    String? spectateError,
    bool clearSpectateError = false,
    bool? isRefreshing,
    bool? refreshFailed,
  }) {
    return LobbyState(
      status: status ?? this.status,
      myId: myId ?? this.myId,
      players: players ?? this.players,
      matches: matches ?? this.matches,
      incomingInvite: clearIncomingInvite
          ? null
          : (incomingInvite ?? this.incomingInvite),
      outgoingInviteToId: clearOutgoingInvite
          ? null
          : (outgoingInviteToId ?? this.outgoingInviteToId),
      inviteRejected: inviteRejected ?? this.inviteRejected,
      inviteTargetLeft: inviteTargetLeft ?? this.inviteTargetLeft,
      matchStart: matchStart ?? this.matchStart,
      spectateSession: clearSpectateSession
          ? null
          : (spectateSession ?? this.spectateSession),
      spectateError: clearSpectateError
          ? null
          : (spectateError ?? this.spectateError),
      isRefreshing: isRefreshing ?? this.isRefreshing,
      refreshFailed: refreshFailed ?? this.refreshFailed,
    );
  }
}

class LobbyController extends Notifier<LobbyState> {
  late final LobbyTransport _transport;
  Completer<void>? _pendingPlayerListRefresh;
  Completer<void>? _pendingMatchListRefresh;

  @override
  LobbyState build() {
    _transport = ref.watch(lobbyTransportProvider);
    ref.onDispose(_transport.close);
    return const LobbyState();
  }

  Future<void> connect(String nickname) async {
    state = state.copyWith(status: LobbyStatus.connecting);
    try {
      await _transport.connect();
      _transport.messages.listen(
        _onMessage,
        onError: (Object _) {
          state = state.copyWith(status: LobbyStatus.error);
        },
      );
      _transport.send(helloMessage(nickname));
    } catch (_) {
      state = state.copyWith(status: LobbyStatus.error);
    }
  }

  void _onMessage(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'welcome':
        state = state.copyWith(
          status: LobbyStatus.connected,
          myId: json['playerId'] as String,
        );
      case 'player_list':
        final players = (json['players'] as List)
            .map((p) => PlayerInfo.fromJson(p as Map<String, dynamic>))
            .toList();
        state = state.copyWith(players: players);
        _pendingPlayerListRefresh?.complete();
        _pendingPlayerListRefresh = null;
      case 'match_list':
        final matches = (json['matches'] as List)
            .map((m) => MatchSummary.fromJson(m as Map<String, dynamic>))
            .toList();
        state = state.copyWith(matches: matches);
        _pendingMatchListRefresh?.complete();
        _pendingMatchListRefresh = null;
      case 'invite_request':
        state = state.copyWith(
          incomingInvite: IncomingInvite(
            fromId: json['fromId'] as String,
            fromNickname: json['fromNickname'] as String,
            config: MatchConfig.fromJson(json['config'] as Map<String, dynamic>?),
          ),
        );
      case 'invite_response':
        final accepted = json['accepted'] as bool;
        final disconnected = json['disconnected'] as bool? ?? false;
        state = state.copyWith(
          clearOutgoingInvite: true,
          inviteRejected: !accepted && !disconnected,
          inviteTargetLeft: !accepted && disconnected,
        );
      case 'match_start':
        state = state.copyWith(
          matchStart: MatchStart(
            matchId: json['matchId'] as String,
            side: json['side'] as String,
            config: MatchConfig.fromJson(json['config'] as Map<String, dynamic>?),
          ),
        );
      case 'spectate_snapshot':
        state = state.copyWith(
          spectateSession: SpectateSession(
            matchId: json['matchId'] as String,
            bottomNickname: json['bottomNickname'] as String,
            topNickname: json['topNickname'] as String,
            ballX: (json['ballX'] as num).toDouble(),
            ballY: (json['ballY'] as num).toDouble(),
            ballVX: (json['ballVX'] as num).toDouble(),
            ballVY: (json['ballVY'] as num).toDouble(),
            paddleBottomX: (json['paddleBottomX'] as num).toDouble(),
            paddleTopX: (json['paddleTopX'] as num).toDouble(),
            scoreBottom: json['scoreBottom'] as int,
            scoreTop: json['scoreTop'] as int,
            remainingSeconds: json['remainingSeconds'] as int,
            spectatorCount: json['spectatorCount'] as int,
          ),
        );
      case 'spectate_error':
        state = state.copyWith(spectateError: json['reason'] as String);
    }
  }

  /// Triggered by pull-to-refresh on the player list. The server already
  /// pushes the roster on every join/leave, so this is a fallback for a
  /// broadcast that was somehow missed, not the normal update path. Always
  /// completes (never throws) so RefreshIndicator's spinner stops promptly
  /// even on a timeout; use [refreshAll] where a failure needs to be shown.
  Future<void> refreshPlayers() async {
    await _awaitPlayerListReply();
  }

  /// Same idea as [refreshPlayers] but for the "Partidas iniciadas"
  /// container's own pull-to-refresh.
  Future<void> refreshMatches() async {
    await _awaitMatchListReply();
  }

  Future<bool> _awaitPlayerListReply() async {
    final completer = Completer<void>();
    _pendingPlayerListRefresh = completer;
    _transport.send(requestPlayerListMessage());
    try {
      await completer.future.timeout(const Duration(seconds: 3));
      return true;
    } on TimeoutException {
      _pendingPlayerListRefresh = null;
      return false;
    }
  }

  Future<bool> _awaitMatchListReply() async {
    final completer = Completer<void>();
    _pendingMatchListRefresh = completer;
    _transport.send(requestMatchListMessage());
    try {
      await completer.future.timeout(const Duration(seconds: 3));
      return true;
    } on TimeoutException {
      _pendingMatchListRefresh = null;
      return false;
    }
  }

  /// Manual refresh button (Feature 1): reloads both the online players and
  /// the in-progress matches, without touching the socket connection itself.
  /// Unlike reloading the whole screen/app, this keeps the live WebSocket
  /// session (and with it, the player's spot in the lobby) intact, and only
  /// re-fetches the two lists that can go stale — a full reconnect would be
  /// slower and would briefly drop the player from everyone else's roster
  /// for no reason.
  Future<void> refreshAll() async {
    if (state.isRefreshing) return; // guards a double tap beyond the disabled button
    state = state.copyWith(isRefreshing: true, refreshFailed: false);
    final results = await Future.wait([
      _awaitPlayerListReply(),
      _awaitMatchListReply(),
    ]);
    final succeeded = results.every((ok) => ok);
    state = state.copyWith(isRefreshing: false, refreshFailed: !succeeded);
  }

  void acknowledgeRefreshFailure() {
    state = state.copyWith(refreshFailed: false);
  }

  void sendInvite(String toId, [MatchConfig config = const MatchConfig()]) {
    state = state.copyWith(outgoingInviteToId: toId);
    _transport.send(inviteRequestMessage(toId, config));
  }

  void respondToInvite(bool accepted) {
    final invite = state.incomingInvite;
    if (invite == null) return;
    _transport.send(inviteResponseMessage(invite.fromId, accepted));
    state = state.copyWith(clearIncomingInvite: true);
  }

  void acknowledgeRejection() {
    state = state.copyWith(inviteRejected: false, inviteTargetLeft: false);
  }

  /// Sends a spectate_request for [matchId]. The server is the only judge of
  /// whether this succeeds (see MatchService.handleSpectateRequest) — a
  /// spectate_snapshot or a spectate_error comes back either way, never a
  /// client-side guess.
  void requestSpectate(String matchId) {
    _transport.send(spectateRequestMessage(matchId));
  }

  void acknowledgeSpectateSession() {
    state = state.copyWith(clearSpectateSession: true);
  }

  void acknowledgeSpectateError() {
    state = state.copyWith(clearSpectateError: true);
  }

  /// Lets the nickname prompt show up again after a failed connection
  /// attempt, instead of leaving the user stuck on the error screen.
  void retry() {
    state = const LobbyState();
  }
}

final lobbyControllerProvider = NotifierProvider<LobbyController, LobbyState>(
  LobbyController.new,
);
