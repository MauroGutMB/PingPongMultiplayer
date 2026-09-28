import 'package:pingpong_server/lobby.dart';
import 'package:pingpong_server/match_room.dart';
import 'package:test/test.dart';

class _Player {
  _Player(this.id, this.nickname);

  final String id;
  final String nickname;
  final List<Map<String, dynamic>> inbox = [];

  late final connection = PlayerConnection(
    id: id,
    nickname: nickname,
    sendJson: inbox.add,
  );
}

void main() {
  late Lobby lobby;
  late MatchService matchService;
  late _Player alice;
  late _Player bob;

  setUp(() {
    lobby = Lobby();
    matchService = MatchService();
    alice = _Player('a', 'Alice');
    bob = _Player('b', 'Bob');
    lobby.register(alice.connection);
    lobby.register(bob.connection);
    alice.inbox.clear();
    bob.inbox.clear();
  });

  test('invite_request is forwarded to the target with the inviter nickname', () {
    matchService.handleInviteRequest(lobby, alice.id, {'toId': bob.id});

    expect(bob.inbox.single, {
      'type': 'invite_request',
      'fromId': 'a',
      'fromNickname': 'Alice',
    });
    expect(alice.inbox, isEmpty);
  });

  test('accepted invite_response starts a match and removes both from the lobby', () {
    matchService.handleInviteResponse(lobby, bob.id, {'toId': alice.id, 'accepted': true});

    expect(alice.inbox, [
      {'type': 'invite_response', 'fromId': 'b', 'accepted': true},
      {'type': 'match_start', 'matchId': anything, 'side': 'bottom'},
    ]);
    // Bob also sees the lobby's player_list update triggered by Alice's
    // removal (she's taken out of the lobby first) before his match_start.
    expect(bob.inbox.last, {
      'type': 'match_start',
      'matchId': anything,
      'side': 'top',
    });
    expect(matchService.isInMatch(alice.id), isTrue);
    expect(matchService.isInMatch(bob.id), isTrue);
  });

  test('rejected invite_response notifies the inviter and starts no match', () {
    matchService.handleInviteResponse(lobby, bob.id, {'toId': alice.id, 'accepted': false});

    expect(alice.inbox.single, {'type': 'invite_response', 'fromId': 'b', 'accepted': false});
    expect(matchService.isInMatch(alice.id), isFalse);
    expect(matchService.isInMatch(bob.id), isFalse);
  });

  test('relay forwards an in-match message verbatim to the opponent only', () {
    matchService.handleInviteResponse(lobby, bob.id, {'toId': alice.id, 'accepted': true});
    alice.inbox.clear();
    bob.inbox.clear();

    matchService.relay(alice.id, {'type': 'paddle_state', 'x': 0.5, 'timestamp': 123});

    expect(bob.inbox.single, {'type': 'paddle_state', 'x': 0.5, 'timestamp': 123});
    expect(alice.inbox, isEmpty);
  });

  test('disconnect tears down the room and notifies the remaining player', () {
    matchService.handleInviteResponse(lobby, bob.id, {'toId': alice.id, 'accepted': true});
    alice.inbox.clear();
    bob.inbox.clear();

    matchService.handleDisconnect(alice.id);

    expect(bob.inbox.single, {'type': 'opponent_disconnected'});
    expect(matchService.isInMatch(alice.id), isFalse);
    expect(matchService.isInMatch(bob.id), isFalse);
  });
}
