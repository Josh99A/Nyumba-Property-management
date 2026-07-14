/// Strict helpers for turning untrusted persisted/remote JSON into domain data.
/// In particular, [requiredInt] rejects floating-point rent values instead of
/// silently truncating them.
final class JsonReader {
  const JsonReader(this.json);

  final Map<String, Object?> json;

  String requiredString(String key) {
    final value = json[key];
    if (value is! String) throw FormatException('$key must be a string.');
    return value;
  }

  String? optionalString(String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is! String) throw FormatException('$key must be a string.');
    return value;
  }

  int requiredInt(String key) {
    final value = json[key];
    if (value is! int) {
      throw FormatException('$key must be an integer in minor units.');
    }
    return value;
  }

  int? optionalInt(String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is! int) throw FormatException('$key must be an integer.');
    return value;
  }

  double? optionalDouble(String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is! num) throw FormatException('$key must be a number.');
    return value.toDouble();
  }

  bool optionalBool(String key, {bool fallback = false}) {
    final value = json[key];
    if (value == null) return fallback;
    if (value is! bool) throw FormatException('$key must be a boolean.');
    return value;
  }

  DateTime requiredDate(String key) {
    final value = requiredString(key);
    try {
      return DateTime.parse(value).toUtc();
    } on FormatException {
      throw FormatException('$key must be an ISO-8601 date.');
    }
  }

  DateTime? optionalDate(String key) {
    final value = optionalString(key);
    if (value == null) return null;
    try {
      return DateTime.parse(value).toUtc();
    } on FormatException {
      throw FormatException('$key must be an ISO-8601 date.');
    }
  }

  List<String> stringList(String key) {
    final value = json[key];
    if (value == null) return const <String>[];
    if (value is! List || value.any((item) => item is! String)) {
      throw FormatException('$key must be a list of strings.');
    }
    return List<String>.from(value);
  }

  T enumValue<T extends Enum>(String key, List<T> values) {
    final name = requiredString(key);
    return values.firstWhere(
      (value) => value.name == name,
      orElse: () => throw FormatException('Unknown $key "$name".'),
    );
  }
}
