import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Message transport used by lobby/match controllers. Abstracted so tests
/// can substitute a fake instead of opening a real socket.
abstract class LobbyTransport {
  Stream<Map<String, dynamic>> get messages;
  Future<void> connect();
  void send(Map<String, dynamic> message);
  Future<void> close();
}

/// Thin wrapper around a WebSocket connection: decodes incoming JSON text
/// frames into a broadcast stream and encodes outgoing maps back to JSON.
class WebSocketService implements LobbyTransport {
  WebSocketService(this.url);

  final String url;
  WebSocketChannel? _channel;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get messages => _controller.stream;

  @override
  Future<void> connect() async {
    final channel = WebSocketChannel.connect(Uri.parse(url));
    await channel.ready;
    _channel = channel;
    channel.stream.listen(
      (raw) =>
          _controller.add(jsonDecode(raw as String) as Map<String, dynamic>),
      onError: _controller.addError,
      onDone: _controller.close,
    );
  }

  @override
  void send(Map<String, dynamic> message) {
    _channel?.sink.add(jsonEncode(message));
  }

  @override
  Future<void> close() async {
    await _channel?.sink.close();
  }
}
