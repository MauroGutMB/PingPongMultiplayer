/// Connection defaults, overridable at build time via --dart-define.
library;

const kDefaultServerUrl = String.fromEnvironment(
  'SERVER_WS_URL',
  defaultValue: 'ws://localhost:8080',
);

/// Raw URL of the gist the dev-machine toggle script
/// (scripts/toggle-lan-access.sh) publishes the current server URL to.
const kGistConfigUrl = String.fromEnvironment(
  'SERVER_CONFIG_GIST_URL',
  defaultValue:
      'https://gist.githubusercontent.com/MauroGutMB/c829c5c21afd51a0a3140f633467ba6b/raw/pingpong_server_url.txt',
);
