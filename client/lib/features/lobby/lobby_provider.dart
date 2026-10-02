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
  IncomingInvite({required this.fromId, required this.fromNickname});

  final String fromId;
  final String fromNickname;
}

class MatchStart {
  MatchStart({required this.matchId, required this.side});

  final String matchId;
  final String side;
}

class LobbyState {
  const LobbyState({
    this.status = LobbyStatus.disconnected,
    this.myId,
    this.players = const [],
    this.incomingInvite,
    this.outgoingInviteToId,
    this.inviteRejected = false,
    this.inviteTargetLeft = false,
    this.matchStart,
  });

  final LobbyStatus status;
  final String? myId;
  final List<PlayerInfo> players;
  final IncomingInvite? incomingInvite;
  final String? outgoingInviteToId;
  final bool inviteRejected;

  /// True instead of [inviteRejected] when the invite went unanswered
  /// because the invited player disconnected, rather than an actual reject.
  final bool inviteTargetLeft;

  final MatchStart? matchStart;

  List<PlayerInfo> get otherPlayers =>
      players.where((p) => p.id != myId).toList();

  LobbyState copyWith({
    LobbyStatus? status,
    String? myId,
    List<PlayerInfo>? players,
    IncomingInvite? incomingInvite,
    bool clearIncomingInvite = false,
    String? outgoingInviteToId,
    bool clearOutgoingInvite = false,
    bool? inviteRejected,
    bool? inviteTargetLeft,
    MatchStart? matchStart,
  }) {
    return LobbyState(
      status: status ?? this.status,
      myId: myId ?? this.myId,
      players: players ?? this.players,
      incomingInvite: clearIncomingInvite
          ? null
          : (incomingInvite ?? this.incomingInvite),
      outgoingInviteToId: clearOutgoingInvite
          ? null
          : (outgoingInviteToId ?? this.outgoingInviteToId),
      inviteRejected: inviteRejected ?? this.inviteRejected,
      inviteTargetLeft: inviteTargetLeft ?? this.inviteTargetLeft,
      matchStart: matchStart ?? this.matchStart,
    );
  }
}

class LobbyController extends Notifier<LobbyState> {
  late final LobbyTransport _transport;
  Completer<void>? _pendingRefresh;

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
        _pendingRefresh?.complete();
        _pendingRefresh = null;
      case 'invite_request':
        state = state.copyWith(
          incomingInvite: IncomingInvite(
            fromId: json['fromId'] as String,
            fromNickname: json['fromNickname'] as String,
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
          ),
        );
    }
  }

  /// Triggered by pull-to-refresh on the player list. The server already
  /// pushes the roster on every join/leave, so this is a fallback for a
  /// broadcast that was somehow missed, not the normal update path.
  Future<void> refreshPlayers() {
    final completer = Completer<void>();
    _pendingRefresh = completer;
    _transport.send(requestPlayerListMessage());
    return completer.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () => _pendingRefresh = null,
    );
  }

  void sendInvite(String toId) {
    state = state.copyWith(outgoingInviteToId: toId);
    _transport.send(inviteRequestMessage(toId));
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

  /// Lets the nickname prompt show up again after a failed connection
  /// attempt, instead of leaving the user stuck on the error screen.
  void retry() {
    state = const LobbyState();
  }
}

final lobbyControllerProvider = NotifierProvider<LobbyController, LobbyState>(
  LobbyController.new,
);
