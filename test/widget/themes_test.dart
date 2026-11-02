import 'dart:io';

import 'package:encore/services/settings.dart';
import 'package:encore/services/storage.dart';
import 'package:encore/ui/shell.dart';
import 'package:encore/ui/theme.dart';
import 'package:encore/ui/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shell_test.dart' show pumpApp;

// There was one look only: named themes (all dark) change the accent, the
// brand gradient and a tint in the background layers.

void main() {
  tearDown(() => settings.theme.value = 'Ember');

  test('every theme has its own name and accent', () {
    expect(
      encoreThemes.map((t) => t.name).toSet(),
      hasLength(encoreThemes.length),
    );
    expect(
      encoreThemes.map((t) => t.accent).toSet(),
      hasLength(encoreThemes.length),
    );
    expect(encoreThemes.first.name, 'Ember', reason: 'the default');
  });

  test('the theme is there the next time', () async {
    final dir = await Directory.systemTemp.createTemp('encore_theme');
    addTearDown(() => dir.delete(recursive: true));
    useDataDir(dir);
    final before = Settings();
    await before.load();
    before.theme.value = 'Forest';
    await before.saved;
    final after = Settings();
    await after.load();
    expect(after.theme.value, 'Forest');
  });

  testWidgets('a theme picked in Settings recolours the app, in place', (
    tester,
  ) async {
    await pumpApp(tester, const Size(1400, 900));
    openSettings();
    await tester.pumpAndSettle();
    expect(EncoreColors.accent, encoreThemes.first.accent);
    final emberBackground = EncoreColors.background;

    await tester.tap(find.bySemanticsLabel('Ocean theme'));
    await tester.pumpAndSettle();
    final ocean = encoreThemes.firstWhere((t) => t.name == 'Ocean');
    expect(settings.theme.value, 'Ocean');
    expect(EncoreColors.accent, ocean.accent);
    expect(EncoreColors.background, isNot(emberBackground), reason: 'tinted');
    expect(
      Theme.of(tester.element(find.byType(PageTitle).first))
          .colorScheme
          .primary,
      ocean.accent,
    );
    // Still on Settings, with Ocean shown as chosen.
    expect(find.text('Appearance'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Ocean theme')),
      containsSemantics(
        label: 'Ocean theme',
        isButton: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
  });

  testWidgets('an unknown saved theme falls back to the default', (
    tester,
  ) async {
    settings.theme.value = 'Gone';
    await pumpApp(tester, const Size(400, 860));
    expect(EncoreColors.accent, encoreThemes.first.accent);
  });
}
