import 'domain_exception.dart';

/// Collects validation failures so callers receive all actionable errors at
/// once rather than fixing one field at a time.
final class DomainValidation {
  DomainValidation._();

  static void check(Map<String, String?> checks) {
    final errors = <String, String>{
      for (final entry in checks.entries)
        if (entry.value != null) entry.key: entry.value!,
    };
    if (errors.isNotEmpty) {
      throw DomainValidationException(errors);
    }
  }

  static String? requiredText(String value, {int maxLength = 200}) {
    final normalized = value.trim();
    if (normalized.isEmpty) return 'is required';
    if (normalized.length > maxLength) {
      return 'must be at most $maxLength characters';
    }
    return null;
  }

  static String? optionalText(String? value, {int maxLength = 2000}) {
    if (value == null || value.trim().isEmpty) return null;
    if (value.trim().length > maxLength) {
      return 'must be at most $maxLength characters';
    }
    return null;
  }

  static String? positiveMinorUnits(int value, {bool allowZero = false}) {
    if (allowZero ? value < 0 : value <= 0) {
      return allowZero ? 'must not be negative' : 'must be greater than zero';
    }
    return null;
  }

  static String? currencyCode(String value) {
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(value)) {
      return 'must be a three-letter uppercase ISO currency code';
    }
    return null;
  }

  static String? email(String value, {bool required = true}) {
    final normalized = value.trim();
    if (normalized.isEmpty) return required ? 'is required' : null;
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalized)) {
      return 'must be a valid email address';
    }
    return null;
  }

  static String? nonNegativeInt(int value) =>
      value < 0 ? 'must not be negative' : null;
}
