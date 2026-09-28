/// Tuning values for the local game loop.
library;

const double kPaddleWidthFraction = 0.3;
const double kPaddleBandOffset = 0.06;
const double kPaddleSpeed = 0.9;
const double kInitialBallSpeed = 0.55;
const int kMatchDurationSeconds = 120;

/// How much of the paddle's own velocity carries into the ball on a hit.
const double kPaddleSpinFactor = 0.5;

/// Speed the ball retains (per axis) when it hits a stationary paddle.
const double kStationaryHitDamping = 0.9;

/// Hard cap on horizontal speed so repeated spin hits can't run away.
const double kMaxBallSpeed = 1.5;

/// How eagerly the opponent's paddle/ball glide toward their real, networked
/// position (per second). Higher closes the gap faster (more responsive,
/// closer to instant) but a snappier catch-up is more visible; lower reads
/// smoother but lags further behind during fast movement.
const double kOpponentSmoothingRate = 15.0;
