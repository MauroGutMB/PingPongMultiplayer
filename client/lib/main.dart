import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'features/connect/connect_screen.dart';

void main() {
  runApp(const ProviderScope(child: PingPongApp()));
}

class PingPongApp extends StatelessWidget {
  const PingPongApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PingPong Multiplayer',
      themeMode: ThemeMode.dark,
      darkTheme: appTheme,
      theme: appTheme,
      home: const ConnectScreen(),
    );
  }
}
