import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

class UiJankMonitor {
  UiJankMonitor({this.warningThreshold = const Duration(milliseconds: 32)});

  final Duration warningThreshold;
  bool _started = false;

  void start() {
    if (_started || kReleaseMode) return;
    _started = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void stop() {
    if (!_started || kReleaseMode) return;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _started = false;
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      final total = timing.totalSpan;
      if (total > warningThreshold) {
        debugPrint(
            '[ui-jank] frame=${total.inMilliseconds}ms build=${timing.buildDuration.inMilliseconds}ms raster=${timing.rasterDuration.inMilliseconds}ms');
      }
    }
  }
}
