import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cloud_data.dart';

extension CloudDataAsyncValue<T> on AsyncValue<CloudData<List<T>>> {
  /// The records to render, or an empty list when none have arrived yet.
  ///
  /// **Only for collections that are supporting context on a screen** — the
  /// unit list behind a tenant picker, the property names a maintenance row
  /// needs to label itself. On those, the screen's own primary read is what
  /// carries the freshness and the failure states, and duplicating them per
  /// lookup list would bury the real one.
  ///
  /// Never use this for the collection a screen is *about*: flattening away
  /// [CloudData] there is exactly how a denied read or a dropped connection
  /// comes to render as "you have no properties". Those screens take the
  /// [CloudData] itself and hand it to `CloudDataView`.
  List<T> get supportingRecords => value?.value ?? <T>[];

  /// The freshness of the underlying read, for a screen that wants to combine
  /// several into one honest summary.
  CloudData<List<T>>? get cloudData => value;
}
