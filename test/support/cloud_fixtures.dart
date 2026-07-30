import 'package:nyumba_property_management/core/cloud/cloud_data.dart';

/// Wraps a fixture list as a validated server read.
///
/// Picks [CloudData.empty] for an empty list rather than [CloudData.live],
/// because that is the distinction the production code turns on: an empty
/// *confirmed* result renders as "nothing here", while a live result with no
/// rows would be a contradiction. Tests that want a failure, a cached copy, or
/// a stale one construct those states explicitly — the point of this helper is
/// only to remove noise from the common "the server answered" case.
CloudData<List<T>> cloudOf<T>(List<T> records, {DateTime? retrievedAt}) {
  final at = retrievedAt ?? DateTime.utc(2026, 7, 29, 9);
  return records.isEmpty
      ? CloudData<List<T>>.empty(records, retrievedAt: at)
      : CloudData<List<T>>.live(records, retrievedAt: at);
}
