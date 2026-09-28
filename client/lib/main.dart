import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'features/connect/connect_screen.dart';

void main() {
  // Flutter's default release-mode error widget renders as a blank grey box,
  // which against this app's all-black theme is indistinguishable from a
  // frozen/black screen — showing nothing to go on if a build ever throws.
  // Make the failure visible instead, in every build mode.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Text(
        'Erro inesperado:\n${details.exceptionAsString()}',
        style: const TextStyle(color: Colors.redAccent, fontSize: 14),
        textAlign: TextAlign.center,
      ),
    );
  };
  runApp(const ProviderScope(child: PingPongApp()));
}

class PingPongApp extends StatelessWidget {
  const PingPongApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IPing Pong',
      themeMode: ThemeMode.dark,
      darkTheme: appTheme,
      theme: appTheme,
      home: const ConnectScreen(),
    );
  }
}
