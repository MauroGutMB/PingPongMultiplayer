/// Message shapes exchanged over the lobby/match WebSocket.
library;

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
}

Map<String, dynamic> helloMessage(String nickname) => {
  'type': 'hello',
  'nickname': nickname,
};

Map<String, dynamic> inviteRequestMessage(String toId) => {
  'type': 'invite_request',
  'toId': toId,
};

Map<String, dynamic> inviteResponseMessage(String toId, bool accepted) => {
  'type': 'invite_response',
  'toId': toId,
  'accepted': accepted,
};
