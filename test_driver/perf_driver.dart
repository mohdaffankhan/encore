import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

/// Prints the frame-time summaries that integration_test/perf_test.dart
/// collects with `watchPerformance`, and saves them to build/perf/.
Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    if (data == null) return;
    await Directory('build/perf').create(recursive: true);
    for (final MapEntry(:key, :value) in data.entries) {
      final s = value as Map<String, dynamic>;
      await File('build/perf/$key.json').writeAsString(jsonEncode(s));
      // ignore: avoid_print
      print(
        '[perf] $key: ${s['frame_count']} frames | '
        'build avg ${_ms(s['average_frame_build_time_millis'])}, '
        'p90 ${_ms(s['90th_percentile_frame_build_time_millis'])}, '
        'worst ${_ms(s['worst_frame_build_time_millis'])} | '
        'raster avg ${_ms(s['average_frame_rasterizer_time_millis'])}, '
        'p90 ${_ms(s['90th_percentile_frame_rasterizer_time_millis'])}, '
        'worst ${_ms(s['worst_frame_rasterizer_time_millis'])} | '
        'janky: ${s['missed_frame_build_budget_count']} build, '
        '${s['missed_frame_rasterizer_budget_count']} raster',
      );
    }
  },
);

String _ms(Object? v) => '${(v as num).toStringAsFixed(1)} ms';
