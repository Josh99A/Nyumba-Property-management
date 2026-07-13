/// Base class for failures caused by invalid domain operations.
sealed class DomainException implements Exception {
  const DomainException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when one or more fields do not satisfy a domain invariant.
final class DomainValidationException extends DomainException {
  DomainValidationException(Map<String, String> errors)
    : errors = Map.unmodifiable(errors),
      super(_format(errors));

  final Map<String, String> errors;

  static String _format(Map<String, String> errors) =>
      errors.entries.map((entry) => '${entry.key}: ${entry.value}').join(', ');
}

/// Thrown when an aggregate cannot be found in the local source of truth.
final class EntityNotFoundException extends DomainException {
  const EntityNotFoundException(this.entityType, this.entityId)
    : super('$entityType "$entityId" was not found.');

  final String entityType;
  final String entityId;
}

/// Thrown when a create operation would overwrite an existing aggregate.
final class EntityAlreadyExistsException extends DomainException {
  const EntityAlreadyExistsException(this.entityType, this.entityId)
    : super('$entityType "$entityId" already exists.');

  final String entityType;
  final String entityId;
}
