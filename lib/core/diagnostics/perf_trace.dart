import 'dart:developer' as developer;

/// Whether performance instrumentation runs at all.
///
/// Traces and counters are development instruments: they exist to prove that an
/// optimisation actually moved the number it claimed to move. A product build
/// compiles them out so the hot paths they wrap — the remote merge loop and
/// every image load — carry no measurement cost in a user's hands.
const bool performanceTracingEnabled = !bool.fromEnvironment('dart.vm.product');

/// Named aggregate measurements collected since the last [PerfCounters.reset].
///
/// The timeline gives the shape of a single frame; this gives the totals across
/// a whole session — how many merge transactions ran, how many image bytes were
/// fetched — which is what distinguishes "one batched write" from "fifty" when
/// reading a test or a debug console rather than a DevTools trace.
final class PerfCounters {
  PerfCounters._();

  static final Map<String, int> _counts = <String, int>{};
  static final Map<String, int> _microseconds = <String, int>{};

  /// Every recorded counter name mapped to its running total.
  static Map<String, int> get counts => Map.unmodifiable(_counts);

  /// Every recorded duration name mapped to its accumulated microseconds.
  static Map<String, int> get microseconds => Map.unmodifiable(_microseconds);

  static void increment(String name, [int by = 1]) {
    if (!performanceTracingEnabled) return;
    _counts[name] = (_counts[name] ?? 0) + by;
  }

  static void addDuration(String name, Duration value) {
    if (!performanceTracingEnabled) return;
    _microseconds[name] = (_microseconds[name] ?? 0) + value.inMicroseconds;
  }

  static int countOf(String name) => _counts[name] ?? 0;

  static Duration durationOf(String name) =>
      Duration(microseconds: _microseconds[name] ?? 0);

  static void reset() {
    _counts.clear();
    _microseconds.clear();
  }

  /// A stable, sorted readout for logging or test failure messages.
  static String report() {
    final lines = <String>[];
    for (final name in (_counts.keys.toList()..sort())) {
      lines.add('$name: ${_counts[name]}');
    }
    for (final name in (_microseconds.keys.toList()..sort())) {
      final millis = (_microseconds[name]! / 1000).toStringAsFixed(1);
      lines.add('$name: ${millis}ms');
    }
    return lines.join('\n');
  }
}

/// Times [action] as an asynchronous timeline slice and a named counter.
///
/// [developer.TimelineTask] rather than the synchronous begin/end pair because
/// the work being measured suspends: strictly nested slices cannot describe an
/// awaited transaction, and mismatched nesting corrupts the whole trace.
Future<T> traceAsync<T>(
  String name,
  Future<T> Function() action, {
  Map<String, Object?> Function()? arguments,
}) async {
  if (!performanceTracingEnabled) return action();
  final task = developer.TimelineTask()
    ..start(name, arguments: arguments?.call());
  final stopwatch = Stopwatch()..start();
  try {
    return await action();
  } finally {
    stopwatch.stop();
    task.finish();
    PerfCounters.increment(name);
    PerfCounters.addDuration(name, stopwatch.elapsed);
  }
}

/// Times [action] as a synchronous timeline slice and a named counter.
T traceSync<T>(
  String name,
  T Function() action, {
  Map<String, Object?> Function()? arguments,
}) {
  if (!performanceTracingEnabled) return action();
  final stopwatch = Stopwatch()..start();
  try {
    return developer.Timeline.timeSync(
      name,
      action,
      arguments: arguments?.call(),
    );
  } finally {
    stopwatch.stop();
    PerfCounters.increment(name);
    PerfCounters.addDuration(name, stopwatch.elapsed);
  }
}

/// Counter and trace names, kept in one place so a rename cannot silently
/// orphan the assertion in a test that reads them.
abstract final class PerfNames {
  /// One entry per database transaction opened to merge server records.
  static const String remoteMergeTransaction = 'remote-merge-transaction';

  /// One entry per server record considered by a merge.
  static const String remoteMergeRecord = 'remote-merge-record';

  /// One entry per server record a merge could not apply.
  ///
  /// [remoteMergeRecord] alone cannot distinguish "every record merged" from
  /// "half of them silently failed"; this is what a test or a debug session
  /// checks to tell the two apart.
  static const String remoteMergeFailure = 'remote-merge-failure';

  /// One entry per storage object whose bytes were downloaded.
  static const String mediaByteFetch = 'media-byte-fetch';

  /// One entry per storage object whose download URL was resolved.
  static const String mediaUrlResolve = 'media-url-resolve';
}
