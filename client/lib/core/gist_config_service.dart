import 'package:http/http.dart' as http;

/// Thrown when the automatic (gist-based) server discovery fails or reports
/// the dev server as offline.
class GistConfigException implements Exception {
  GistConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Fetches the server's ws:// URL from a raw gist URL, as published by
/// scripts/toggle-lan-access.sh on the developer's machine.
class GistConfigService {
  GistConfigService(this.rawUrl, {http.Client? client})
    : _client = client ?? http.Client();

  final String rawUrl;
  final http.Client _client;

  Future<String> fetchServerUrl() async {
    final http.Response response;
    try {
      response = await _client
          .get(Uri.parse(rawUrl))
          .timeout(const Duration(seconds: 6));
    } catch (_) {
      throw GistConfigException('Não foi possível buscar a configuração automática.');
    }

    if (response.statusCode != 200) {
      throw GistConfigException(
        'Configuração automática indisponível (HTTP ${response.statusCode}).',
      );
    }

    final content = response.body.trim();
    if (content.isEmpty || content == 'offline') {
      throw GistConfigException('O servidor está offline no momento.');
    }
    return content;
  }
}
