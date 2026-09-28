import 'game_constants.dart';

/// Snapshot of the local match: ball, both paddles, score and clock. All
/// positions are normalized (0.0-1.0) fractions of the field, independent of
/// screen size.
class GameState {
  const GameState({
    this.ballX = 0.5,
    this.ballY = 0.5,
    this.ballVX = 0,
    this.ballVY = 0,
    this.paddleWidth = kPaddleWidthFraction,
    this.opponentPaddleX = 0.5,
    this.playerPaddleX = 0.5,
    this.scoreTop = 0,
    this.scoreBottom = 0,
    this.remainingSeconds = kMatchDurationSeconds,
    this.matchOver = false,
    this.opponentLeft = false,
  });

  final double ballX;
  final double ballY;
  final double ballVX;
  final double ballVY;
  final double paddleWidth;
  final double opponentPaddleX;
  final double playerPaddleX;
  final int scoreTop;
  final int scoreBottom;
  final int remainingSeconds;
  final bool matchOver;

  /// Only meaningful for networked matches: the opponent's socket dropped
  /// (or they intentionally left) before the match timer ran out.
  final bool opponentLeft;

  GameState copyWith({
    double? ballX,
    double? ballY,
    double? ballVX,
    double? ballVY,
    double? opponentPaddleX,
    double? playerPaddleX,
    int? scoreTop,
    int? scoreBottom,
    int? remainingSeconds,
    bool? matchOver,
    bool? opponentLeft,
  }) {
    return GameState(
      ballX: ballX ?? this.ballX,
      ballY: ballY ?? this.ballY,
      ballVX: ballVX ?? this.ballVX,
      ballVY: ballVY ?? this.ballVY,
      paddleWidth: paddleWidth,
      opponentPaddleX: opponentPaddleX ?? this.opponentPaddleX,
      playerPaddleX: playerPaddleX ?? this.playerPaddleX,
      scoreTop: scoreTop ?? this.scoreTop,
      scoreBottom: scoreBottom ?? this.scoreBottom,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      matchOver: matchOver ?? this.matchOver,
      opponentLeft: opponentLeft ?? this.opponentLeft,
    );
  }
}
