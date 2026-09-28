import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pingpong_client/core/gist_config_service.dart';

void main() {
  test('returns the trimmed URL on a successful fetch', () async {
    final client = MockClient(
      (request) async => http.Response('ws://192.168.0.10:8080\n', 200),
    );
    final service = GistConfigService('https://example.com/gist', client: client);

    final url = await service.fetchServerUrl();

    expect(url, 'ws://192.168.0.10:8080');
  });

  test('throws when the server is marked offline', () async {
    final client = MockClient((request) async => http.Response('offline', 200));
    final service = GistConfigService('https://example.com/gist', client: client);

    await expectLater(service.fetchServerUrl(), throwsA(isA<GistConfigException>()));
  });

  test('throws on a non-200 response', () async {
    final client = MockClient((request) async => http.Response('not found', 404));
    final service = GistConfigService('https://example.com/gist', client: client);

    await expectLater(service.fetchServerUrl(), throwsA(isA<GistConfigException>()));
  });

  test('throws when the request itself fails', () async {
    final client = MockClient((request) async => throw Exception('network down'));
    final service = GistConfigService('https://example.com/gist', client: client);

    await expectLater(service.fetchServerUrl(), throwsA(isA<GistConfigException>()));
  });
}
