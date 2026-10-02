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
    ip: '127.0.0.1',
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

  const defaultConfig = {
    'ballSpeedMultiplier': 1.0,
    'winningScore': 0,
    'durationSeconds': 120,
  };

  test('invite_request is forwarded to the target with the inviter nickname', () {
    matchService.handleInviteRequest(lobby, alice.id, {'toId': bob.id});

    expect(bob.inbox.single, {
      'type': 'invite_request',
      'fromId': 'a',
      'fromNickname': 'Alice',
      'config': defaultConfig,
    });
    expect(alice.inbox, isEmpty);
  });

  test('invite_request carries a sanitized version of an out-of-range config', () {
    matchService.handleInviteRequest(lobby, alice.id, {
      'toId': bob.id,
      'config': {'ballSpeedMultiplier': 50.0, 'winningScore': -3, 'durationSeconds': 999999},
    });

    expect((bob.inbox.single['config'] as Map)['ballSpeedMultiplier'], 2.0);
    expect((bob.inbox.single['config'] as Map)['winningScore'], 0);
    expect((bob.inbox.single['config'] as Map)['durationSeconds'], 600);
  });

  test('accepted invite_response starts a match and removes both from the lobby', () {
    final sentConfig = {'ballSpeedMultiplier': 1.4, 'winningScore': 11, 'durationSeconds': 180};
    matchService.handleInviteRequest(lobby, alice.id, {'toId': bob.id, 'config': sentConfig});

    matchService.handleInviteResponse(lobby, bob.id, {'toId': alice.id, 'accepted': true});

    expect(alice.inbox, [
      {'type': 'invite_response', 'fromId': 'b', 'accepted': true, 'disconnected': false},
      {'type': 'match_start', 'matchId': anything, 'side': 'bottom', 'config': sentConfig},
    ]);
    // Bob also sees the lobby's player_list update triggered by Alice's
    // removal (she's taken out of the lobby first) before his match_start —
    // on top of the invite_request notification from the setup above.
    expect(bob.inbox.last, {
      'type': 'match_start',
      'matchId': anything,
      'side': 'top',
      'config': sentConfig,
    });
    expect(matchService.isInMatch(alice.id), isTrue);
    expect(matchService.isInMatch(bob.id), isTrue);
  });

  test('accepted invite_response with no prior invite_request falls back to default config', () {
    matchService.handleInviteResponse(lobby, bob.id, {'toId': alice.id, 'accepted': true});

    expect(alice.inbox.last, {
      'type': 'match_start',
      'matchId': anything,
      'side': 'bottom',
      'config': defaultConfig,
    });
  });

  test('rejected invite_response notifies the inviter and starts no match', () {
    matchService.handleInviteResponse(lobby, bob.id, {'toId': alice.id, 'accepted': false});

    expect(alice.inbox.single, {
      'type': 'invite_response',
      'fromId': 'b',
      'accepted': false,
      'disconnected': false,
    });
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

  test(
    'leaveMatch tears down the room, notifies the opponent, and returns the leaver\'s own connection',
    () {
      matchService.handleInviteResponse(lobby, bob.id, {'toId': alice.id, 'accepted': true});
      alice.inbox.clear();
      bob.inbox.clear();

      final leaver = matchService.leaveMatch(alice.id);

      expect(leaver, same(alice.connection));
      expect(bob.inbox.single, {'type': 'opponent_disconnected'});
      expect(matchService.isInMatch(alice.id), isFalse);
      expect(matchService.isInMatch(bob.id), isFalse);
    },
  );

  test('leaveMatch is a no-op for a player who is not in a match', () {
    expect(matchService.leaveMatch(alice.id), isNull);
    expect(alice.inbox, isEmpty);
  });

  group('cancelPendingInvitesFor', () {
    test(
      'notifies the inviter when the invited player disconnects before responding',
      () {
        matchService.handleInviteRequest(lobby, alice.id, {'toId': bob.id});
        bob.inbox.clear();

        matchService.cancelPendingInvitesFor(lobby, bob.id);

        expect(alice.inbox.single, {
          'type': 'invite_response',
          'fromId': 'b',
          'accepted': false,
          'disconnected': true,
        });
      },
    );

    test('a later real response from the target is unaffected by a stale cancel', () {
      matchService.handleInviteRequest(lobby, alice.id, {'toId': bob.id});
      matchService.handleInviteResponse(lobby, bob.id, {
        'toId': alice.id,
        'accepted': true,
      });
      alice.inbox.clear();

      // Some other, unrelated disconnect happening afterwards must not
      // re-notify alice about an invite that was already resolved.
      matchService.cancelPendingInvitesFor(lobby, bob.id);

      expect(alice.inbox, isEmpty);
    });

    test('is a no-op when the disconnecting player has no pending invite', () {
      matchService.cancelPendingInvitesFor(lobby, alice.id);

      expect(alice.inbox, isEmpty);
      expect(bob.inbox, isEmpty);
    });

    test(
      'drops the pending record when the inviter (not the target) disconnects',
      () {
        matchService.handleInviteRequest(lobby, alice.id, {'toId': bob.id});
        bob.inbox.clear();

        // Mirrors what bin/server.dart's _handleDisconnect does on a real
        // disconnect: cancel bookkeeping, then remove from the lobby.
        matchService.cancelPendingInvitesFor(lobby, alice.id);
        lobby.remove(alice.id);
        bob.inbox.clear(); // discard the player_list broadcast from removing alice

        // If bob now responds anyway, the server just finds no live inviter
        // in the lobby and drops it — no match, no crash.
        matchService.handleInviteResponse(lobby, bob.id, {
          'toId': alice.id,
          'accepted': true,
        });

        expect(bob.inbox, isEmpty);
        expect(matchService.isInMatch(bob.id), isFalse);
      },
    );
  });

  group('spectating', () {
    late _Player carol;

    setUp(() {
      carol = _Player('c', 'Carol');
      lobby.register(carol.connection);
      carol.inbox.clear();
    });

    test('rejects spectating a match that does not exist', () {
      matchService.handleSpectateRequest(lobby, carol.id, {'matchId': 'nope'});

      expect(carol.inbox.single, {
        'type': 'spectate_error',
        'reason': 'Esta partida não está mais em andamento.',
      });
    });

    test('a joined spectator gets a snapshot and both players see the count', () {
      matchService.handleInviteResponse(lobby, bob.id, {'toId': alice.id, 'accepted': true});
      final matchId = (alice.inbox.last['matchId']) as String;
      alice.inbox.clear();
      bob.inbox.clear();
      // Clears the player_list broadcasts triggered by alice/bob leaving the
      // lobby when their match started, which carol (still in the lobby)
      // also received.
      carol.inbox.clear();

      matchService.handleSpectateRequest(lobby, carol.id, {'matchId': matchId});

      // Carol gets the snapshot first, then the spectator_count broadcast
      // that follows it (she counts herself).
      expect(carol.inbox, hasLength(2));
      expect(carol.inbox.first['type'], 'spectate_snapshot');
      expect(carol.inbox.first['bottomId'], alice.id);
      expect(carol.inbox.first['topId'], bob.id);
      expect(carol.inbox.first['spectatorCount'], 1);
      expect(carol.inbox.last, {'type': 'spectator_count', 'matchId': matchId, 'count': 1});
      expect(alice.inbox.single, {'type': 'spectator_count', 'matchId': matchId, 'count': 1});
      expect(bob.inbox.single, {'type': 'spectator_count', 'matchId': matchId, 'count': 1});
    });

    test('a player cannot spectate their own match', () {
      matchService.handleInviteResponse(lobby, bob.id, {'toId': alice.id, 'accepted': true});
      final matchId = (alice.inbox.last['matchId']) as String;
      alice.inbox.clear();
      bob.inbox.clear();

      matchService.handleSpectateRequest(lobby, alice.id, {'matchId': matchId});

      expect(alice.inbox.single, {
        'type': 'spectate_error',
        'reason': 'Você já é jogador desta partida.',
      });
    });

    test('a player already in another match cannot spectate', () {
      matchService.handleInviteResponse(lobby, bob.id, {'toId': alice.id, 'accepted': true});
      final matchId = (alice.inbox.last['matchId']) as String;
      final dave = _Player('d', 'Dave');
      final erin = _Player('e', 'Erin');
      lobby.register(dave.connection);
      lobby.register(erin.connection);
      matchService.handleInviteResponse(lobby, erin.id, {'toId': dave.id, 'accepted': true});
      dave.inbox.clear();

      matchService.handleSpectateRequest(lobby, dave.id, {'matchId': matchId});

      expect(dave.inbox.single, {
        'type': 'spectate_error',
        'reason': 'Saia da sua partida atual antes de espectar outra.',
      });
    });

    test('paddle_state and ball_state are relayed to spectators tagged with the sender side', () {
      matchService.handleInviteResponse(lobby, bob.id, {'toId': alice.id, 'accepted': true});
      final matchId = (alice.inbox.last['matchId']) as String;
      matchService.handleSpectateRequest(lobby, carol.id, {'matchId': matchId});
      carol.inbox.clear();

      matchService.relay(alice.id, {'type': 'paddle_state', 'x': 0.3});
      matchService.relay(bob.id, {'type': 'ball_state', 'x': 0.4, 'y': 0.9, 'vx': 0.1, 'vy': 0.2});

      expect(carol.inbox, [
        {'type': 'paddle_state', 'x': 0.3, 'from': 'bottom'},
        {'type': 'ball_state', 'x': 0.4, 'y': 0.9, 'vx': 0.1, 'vy': 0.2, 'from': 'top'},
      ]);
    });

    test('leaving spectate removes the spectator and updates the count', () {
      matchService.handleInviteResponse(lobby, bob.id, {'toId': alice.id, 'accepted': true});
      final matchId = (alice.inbox.last['matchId']) as String;
      matchService.handleSpectateRequest(lobby, carol.id, {'matchId': matchId});
      alice.inbox.clear();
      bob.inbox.clear();

      matchService.removeSpectator(carol.id);

      expect(alice.inbox.single, {'type': 'spectator_count', 'matchId': matchId, 'count': 0});
      expect(bob.inbox.single, {'type': 'spectator_count', 'matchId': matchId, 'count': 0});
    });

    test('a disconnect that ends the match notifies spectators and clears them', () {
      matchService.handleInviteResponse(lobby, bob.id, {'toId': alice.id, 'accepted': true});
      final matchId = (alice.inbox.last['matchId']) as String;
      matchService.handleSpectateRequest(lobby, carol.id, {'matchId': matchId});
      carol.inbox.clear();

      matchService.handleDisconnect(alice.id);

      expect(carol.inbox.single, {
        'type': 'match_ended',
        'matchId': matchId,
        'scoreBottom': 0,
        'scoreTop': 0,
        'reason': 'player_left',
      });

      // The match is gone, so a late spectate_request against it just fails
      // instead of attaching to a room nobody will ever tear down.
      matchService.handleSpectateRequest(lobby, carol.id, {'matchId': matchId});
      expect(carol.inbox.last['type'], 'spectate_error');
    });

    test('match_end from a player relays the score, notifies spectators and ends the room', () {
      matchService.handleInviteResponse(lobby, bob.id, {'toId': alice.id, 'accepted': true});
      final matchId = (alice.inbox.last['matchId']) as String;
      matchService.handleSpectateRequest(lobby, carol.id, {'matchId': matchId});
      alice.inbox.clear();
      bob.inbox.clear();
      carol.inbox.clear();

      matchService.handleMatchEnd(alice.id, {
        'type': 'match_end',
        'scoreBottom': 3,
        'scoreTop': 1,
      });

      expect(bob.inbox.single, {'type': 'match_end', 'scoreBottom': 3, 'scoreTop': 1});
      expect(carol.inbox, [
        {'type': 'match_end', 'scoreBottom': 3, 'scoreTop': 1, 'from': 'bottom'},
        {'type': 'match_ended', 'matchId': matchId, 'scoreBottom': 3, 'scoreTop': 1, 'reason': 'finished'},
      ]);
      expect(matchService.isInMatch(alice.id), isFalse);
      expect(matchService.isInMatch(bob.id), isFalse);

      // A second report of the same timeout (the other client's own local
      // clock) is a harmless no-op, not a crash.
      matchService.handleMatchEnd(bob.id, {'type': 'match_end'});
    });

    test('accepting an invite while spectating drops the old spectate slot', () {
      matchService.handleInviteResponse(lobby, bob.id, {'toId': alice.id, 'accepted': true});
      final matchId = (alice.inbox.last['matchId']) as String;
      final dave = _Player('d', 'Dave');
      final erin = _Player('e', 'Erin');
      lobby.register(dave.connection);
      lobby.register(erin.connection);
      matchService.handleSpectateRequest(lobby, dave.id, {'matchId': matchId});
      alice.inbox.clear();
      bob.inbox.clear();

      matchService.handleInviteResponse(lobby, erin.id, {'toId': dave.id, 'accepted': true});

      expect(matchService.isInMatch(dave.id), isTrue);
      // Dave counts as a player now, not a spectator of Alice/Bob's match.
      expect(alice.inbox.where((m) => m['type'] == 'spectator_count'), [
        {'type': 'spectator_count', 'matchId': matchId, 'count': 0},
      ]);
    });

    test('listActiveMatches reports one summary per match with the current spectator count', () {
      expect(matchService.listActiveMatches(), isEmpty);

      matchService.handleInviteResponse(lobby, bob.id, {'toId': alice.id, 'accepted': true});
      matchService.handleSpectateRequest(lobby, carol.id, {
        'matchId': matchService.listActiveMatches().single.matchId,
      });

      final summaries = matchService.listActiveMatches();
      expect(summaries, hasLength(1));
      expect(summaries.single.bottomNickname, 'Alice');
      expect(summaries.single.topNickname, 'Bob');
      expect(summaries.single.spectatorCount, 1);
    });
  });

  group('hasPendingInvite', () {
    test('is true for both the inviter and the target while unanswered', () {
      matchService.handleInviteRequest(lobby, alice.id, {'toId': bob.id});

      expect(matchService.hasPendingInvite(alice.id), isTrue);
      expect(matchService.hasPendingInvite(bob.id), isTrue);
      expect(matchService.hasPendingInvite('c'), isFalse);
    });

    test('clears once the invite is answered', () {
      matchService.handleInviteRequest(lobby, alice.id, {'toId': bob.id});
      matchService.handleInviteResponse(lobby, bob.id, {'toId': alice.id, 'accepted': false});

      expect(matchService.hasPendingInvite(alice.id), isFalse);
      expect(matchService.hasPendingInvite(bob.id), isFalse);
    });
  });
}
