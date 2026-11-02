import 'dart:io';

import 'package:encore/services/equalizer.dart';
import 'package:encore/services/settings.dart';
import 'package:encore/services/storage.dart';
import 'package:encore/ui/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shell_test.dart' show pumpApp;

// There was no equalizer. Desktop: FFmpeg's equalizer filter in mpv;
// Android: the system equalizer (checked on the phone by the e2e).

void main() {
  tearDown(() {
    settings.equalizerOn.value = false;
    settings.equalizerGains.value = const [0, 0, 0, 0, 0];
  });

  test("desktop: mpv's filter, one equalizer per band that changes", () {
    expect(Equalizer.mpvFilter(const [0, 0, 0, 0, 0]), '');
    expect(
      Equalizer.mpvFilter(const [6, 4, 0, 0, -2.5]),
      'lavfi=[equalizer=f=60:t=o:w=2:g=6,equalizer=f=230:t=o:w=2:g=4,'
      'equalizer=f=14000:t=o:w=2:g=-2.5]',
    );
  });

  test('presets are told apart; anything else is custom', () {
    expect(Equalizer.presetFor(Equalizer.presets['Rock']!), 'Rock');
    expect(Equalizer.presetFor(const [1, 0, 0, 0, 0]), isNull);
    expect(
      Equalizer.presets.values.map((g) => g.join()).toSet(),
      hasLength(Equalizer.presets.length),
      reason: 'no two presets alike',
    );
  });

  test('applies the settings, and nothing while it is off', () async {
    final sent = <String>[];
    final eq = Equalizer()..setMpvFilter = (f) async => sent.add(f);
    eq.start();
    expect(sent.last, '');
    settings.equalizerGains.value = Equalizer.presets['Bass boost']!;
    expect(sent.last, '', reason: 'off');
    settings.equalizerOn.value = true;
    expect(sent.last, Equalizer.mpvFilter(Equalizer.presets['Bass boost']!));
    settings.equalizerOn.value = false;
    expect(sent.last, '');
  });

  test('the equalizer is there the next time', () async {
    final dir = await Directory.systemTemp.createTemp('encore_eq');
    addTearDown(() => dir.delete(recursive: true));
    useDataDir(dir);
    final before = Settings();
    await before.load();
    before.equalizerOn.value = true;
    before.equalizerGains.value = const [3, 0, -2, 0, 5];
    await before.saved;
    final after = Settings();
    await after.load();
    expect(after.equalizerOn.value, isTrue);
    expect(after.equalizerGains.value, [3, 0, -2, 0, 5]);
  });

  testWidgets('Settings: a preset turns it on, a band makes it custom', (
    tester,
  ) async {
    await pumpApp(tester, const Size(400, 860));
    openSettings();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Equalizer'), 200);
    expect(find.text('Off'), findsOneWidget);
    await tester.tap(find.text('Equalizer'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bass boost'));
    await tester.pumpAndSettle();
    expect(settings.equalizerOn.value, isTrue);
    expect(settings.equalizerGains.value, Equalizer.presets['Bass boost']);
    expect(find.text('+6 dB'), findsOneWidget, reason: '60 Hz');

    // Dragging the 14 kHz band up.
    final treble = find.byType(Slider).last;
    await tester.drag(treble, const Offset(0, -60));
    await tester.pumpAndSettle();
    expect(settings.equalizerGains.value.last, greaterThan(0));
    await tester.tapAt(const Offset(200, 40)); // close the sheet
    await tester.pumpAndSettle();
    expect(find.text('Custom'), findsOneWidget, reason: 'the settings row');
  });
}
