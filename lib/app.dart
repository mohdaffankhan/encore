import 'package:flutter/material.dart';

import 'services/settings.dart';
import 'ui/shell.dart';
import 'ui/shortcuts.dart';
import 'ui/theme.dart';

class EncoreApp extends StatefulWidget {
  const EncoreApp({super.key});

  @override
  State<EncoreApp> createState() => _EncoreAppState();
}

class _EncoreAppState extends State<EncoreApp> {
  @override
  void initState() {
    super.initState();
    _applyTheme();
    settings.theme.addListener(_themeChanged);
  }

  @override
  void dispose() {
    settings.theme.removeListener(_themeChanged);
    super.dispose();
  }

  /// The chosen theme's colours (an unknown name: the first theme).
  void _applyTheme() => EncoreColors.theme = encoreThemes.firstWhere(
    (t) => t.name == settings.theme.value,
    orElse: () => encoreThemes.first,
  );

  void _themeChanged() {
    _applyTheme();
    // Every widget redraws with the new colours, where it is.
    setState(() {});
    redrawAll(context);
  }

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
