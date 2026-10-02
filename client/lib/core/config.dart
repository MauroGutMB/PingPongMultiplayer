/// Connection defaults, overridable at build time via --dart-define.
library;

// Points at the Render deployment by default; override at build time for
// local dev, e.g.:
//   flutter run --dart-define=SERVER_WS_URL=ws://localhost:8080
const kDefaultServerUrl = String.fromEnvironment(
  'SERVER_WS_URL',
  defaultValue: 'wss://pingpong-server-b567.onrender.com',
);
