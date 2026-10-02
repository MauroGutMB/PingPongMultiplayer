import 'protocol.dart';

/// A connected, registered lobby member.
///
/// Takes a [sendJson] callback rather than a raw socket/channel so the lobby
/// logic can be unit-tested without a real WebSocket connection.
class PlayerConnection {
  PlayerConnection({
    required this.id,
    required this.nickname,
    required this.ip,
    required void Function(Map<String, dynamic>) sendJson,
  }) : _sendJson = sendJson;

  final String id;
  final String nickname;
  final String ip;
  final void Function(Map<String, dynamic>) _sendJson;

  void send(Map<String, dynamic> message) => _sendJson(message);
}

/// Tracks online players and broadcasts presence changes to everyone.
class Lobby {
  Lobby({bool Function(String playerId)? isPending})
    : _isPending = isPending ?? ((_) => false);

  /// Reports whether a player has a pending invite (sent or received), so the
  /// broadcast roster can mark them unavailable. Defaults to "never pending"
  /// so existing callers that build a bare `Lobby()` keep working unchanged.
  final bool Function(String playerId) _isPending;

  final Map<String, PlayerConnection> _players = {};

  /// Every currently connected player, for broadcasts that aren't tied to a
  /// membership change (e.g. the match list, which lives in [MatchService]).
  Iterable<PlayerConnection> get all => _players.values;

  void register(PlayerConnection connection) {
    _players[connection.id] = connection;
    _broadcastPlayerList();
  }

  void remove(String playerId) {
    if (_players.remove(playerId) != null) {
      _broadcastPlayerList();
    }
  }

  PlayerConnection? operator [](String playerId) => _players[playerId];

  /// Re-sends the current roster to a single player — used for a manual
  /// pull-to-refresh, since normally the list only reaches clients via the
  /// broadcast this class sends on every join/leave.
  void sendPlayerListTo(String playerId) {
    final player = _players[playerId];
    if (player != null) player.send(_playerListMessage());
  }

  /// Re-broadcasts the roster with no membership change — used when a
  /// per-player attribute it exposes (currently just [PlayerInfo.pendingInvite])
  /// changes without anyone joining or leaving.
  void refreshPresence() => _broadcastPlayerList();

  void _broadcastPlayerList() {
    final message = _playerListMessage();
    for (final player in _players.values) {
      player.send(message);
    }
  }

  Map<String, dynamic> _playerListMessage() {
    return PlayerListMessage(
      players: _players.values
          .map(
            (p) => PlayerInfo(
              id: p.id,
              nickname: p.nickname,
              ip: p.ip,
              pendingInvite: _isPending(p.id),
            ),
          )
          .toList(),
    ).toJson();
  }
}
