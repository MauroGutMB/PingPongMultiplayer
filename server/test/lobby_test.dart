import 'package:pingpong_server/lobby.dart';
import 'package:test/test.dart';

PlayerConnection _fakePlayer(
  String id,
  String nickname,
  List<Map<String, dynamic>> inbox,
) {
  return PlayerConnection(
    id: id,
    nickname: nickname,
    ip: '127.0.0.1',
    sendJson: inbox.add,
  );
}

void main() {
  test('register broadcasts the updated player list to everyone', () {
    final lobby = Lobby();
    final aliceInbox = <Map<String, dynamic>>[];
    final bobInbox = <Map<String, dynamic>>[];

    lobby.register(_fakePlayer('a', 'Alice', aliceInbox));
    expect(aliceInbox.single['players'], hasLength(1));

    lobby.register(_fakePlayer('b', 'Bob', bobInbox));

    expect(aliceInbox.last['players'], hasLength(2));
    expect(bobInbox.single['players'], hasLength(2));
  });

  test('remove broadcasts the player list without the removed player', () {
    final lobby = Lobby();
    final aliceInbox = <Map<String, dynamic>>[];
    final bobInbox = <Map<String, dynamic>>[];

    lobby.register(_fakePlayer('a', 'Alice', aliceInbox));
    lobby.register(_fakePlayer('b', 'Bob', bobInbox));
    lobby.remove('a');

    final lastListForBob = bobInbox.last['players'] as List;
    expect(lastListForBob, hasLength(1));
    expect(lastListForBob.single['id'], 'b');
  });

  test('remove is a no-op for an unknown playerId', () {
    final lobby = Lobby();
    final aliceInbox = <Map<String, dynamic>>[];
    lobby.register(_fakePlayer('a', 'Alice', aliceInbox));

    lobby.remove('unknown');

    expect(aliceInbox, hasLength(1)); // only the register broadcast
  });
}
