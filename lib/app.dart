import 'package:flutter/material.dart';

import 'ui/shell.dart';
import 'ui/shortcuts.dart';
import 'ui/theme.dart';

class EncoreApp extends StatelessWidget {
  const EncoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Encore',
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      builder: (context, child) => PlayerShortcuts(child: child!),
      home: Shell(key: shellKey),
    );
  }
}
