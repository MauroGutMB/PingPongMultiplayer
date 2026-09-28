import 'protocol.dart';

/// A connected, registered lobby member.
///
/// Takes a [sendJson] callback rather than a raw socket/channel so the lobby
/// logic can be unit-tested without a real WebSocket connection.
class PlayerConnection {
  PlayerConnection({
    required this.id,
    required this.nickname,
    required void Function(Map<String, dynamic>) sendJson,
  }) : _sendJson = sendJson;

  final String id;
  final String nickname;
  final void Function(Map<String, dynamic>) _sendJson;

  void send(Map<String, dynamic> message) => _sendJson(message);
}

/// Tracks online players and broadcasts presence changes to everyone.
class Lobby {
  final Map<String, PlayerConnection> _players = {};

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

  void _broadcastPlayerList() {
    final message = PlayerListMessage(
      players: _players.values
          .map((p) => PlayerInfo(id: p.id, nickname: p.nickname))
          .toList(),
    ).toJson();
    for (final player in _players.values) {
      player.send(message);
    }
  }
}
