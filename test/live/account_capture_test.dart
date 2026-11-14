// Run by hand only (never in CI): reads the signed-in test account's
// library pages and saves YouTube's replies, to write tests from.
//   flutter test test/live/account_capture_test.dart \
//     --dart-define=ENCORE_DUMP=<folder> --dart-define=ENCORE_ACCOUNT_DIR=<test_data folder>
// Read-only: nothing on the account is changed.
import 'dart:io';

import 'package:encore/api/innertube.dart' as yt;
import 'package:encore/services/account.dart';
import 'package:flutter_test/flutter_test.dart';

const _dir = String.fromEnvironment('ENCORE_ACCOUNT_DIR');

void main() {
  test(
    'capture the signed-in library',
    () async {
      final acc = Account(store: DeviceSecretStore(Directory(_dir)));
      await acc.load();
      expect(acc.status.value, AccountStatus.signedIn);
      yt.signIn = acc;
      for (final id in ['MPREb_2IPsncXPdzh', 'UC-kVv2dTX6UD68r3wUmExKw']) {
        try {
          await yt.browse(id);
        } catch (e) {
          fail('$id: $e');
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      await acc.saved;
    },
    skip: _dir.isEmpty,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
