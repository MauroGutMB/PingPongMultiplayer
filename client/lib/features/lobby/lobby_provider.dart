import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/protocol.dart';
import '../../core/websocket_service.dart';

/// Set by the connect screen before the lobby is ever shown — automatic
/// (gist) or manual URL entry both funnel through here.
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
}

final lobbyControllerProvider = NotifierProvider<LobbyController, LobbyState>(
  LobbyController.new,
);
