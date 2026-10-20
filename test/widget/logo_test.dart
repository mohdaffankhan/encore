import 'package:encore/ui/theme.dart';
import 'package:encore/ui/widgets/logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Guards the in-app mark against accidental changes; it should match the
// app icon drawn by tool/icons.py. Regenerate with --update-goldens.
void main() {
  testWidgets('Encore mark', (tester) async {
    await tester.pumpWidget(
      const Center(
        child: RepaintBoundary(
          child: ColoredBox(
            color: EncoreColors.background,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: EncoreMark(size: 128),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(RepaintBoundary).first,
      matchesGoldenFile('goldens/encore_mark.png'),
    );
  });
}
