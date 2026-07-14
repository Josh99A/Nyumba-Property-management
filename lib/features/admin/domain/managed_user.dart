import '../../../core/domain/domain_validation.dart';
import '../../../core/domain/sync_metadata.dart';

enum ManagedUserStatus {
  active('Active'),
  invited('Invited'),
  suspended('Suspended');

  const ManagedUserStatus(this.label);

  final String label;
}

/// Admin-facing projection of one platform account. The server owns the
/// canonical account; local admin mutations are queued intents.
final class ManagedUser {
  ManagedUser({
    required this.id,
    required this.reference,
    required this.name,
    required this.email,
    required this.role,
    required this.location,
    required this.status,
    required this.lastActiveLabel,
    required this.joinedLabel,
    required this.createdAt,
    required this.updatedAt,
    required this.syncMetadata,
  }) {
    validate();
  }

  final String id;

  /// Human-readable account reference such as `USR-4082`.
  final String reference;
  final String name;
  final String email;
  final String role;
  final String location;
  final ManagedUserStatus status;
  final String lastActiveLabel;
  final String joinedLabel;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncMetadata syncMetadata;

  void validate() {
    DomainValidation.check(<String, String?>{
      'reference': DomainValidation.requiredText(reference, maxLength: 40),
      'name': DomainValidation.requiredText(name, maxLength: 120),
      'email': DomainValidation.email(email),
      'role': DomainValidation.requiredText(role, maxLength: 40),
      'location': DomainValidation.requiredText(location, maxLength: 80),
      'lastActiveLabel': DomainValidation.requiredText(
        lastActiveLabel,
        maxLength: 60,
      ),
      'joinedLabel': DomainValidation.requiredText(joinedLabel, maxLength: 40),
    });
  }

  ManagedUser copyWith({
    ManagedUserStatus? status,
    String? lastActiveLabel,
    DateTime? updatedAt,
    SyncMetadata? syncMetadata,
  }) => ManagedUser(
    id: id,
    reference: reference,
    name: name,
    email: email,
    role: role,
    location: location,
    status: status ?? this.status,
    lastActiveLabel: lastActiveLabel ?? this.lastActiveLabel,
    joinedLabel: joinedLabel,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    syncMetadata: syncMetadata ?? this.syncMetadata,
  );
}

final class InviteManagedUserInput {
  const InviteManagedUserInput({
    required this.name,
    required this.email,
    required this.role,
    this.location = 'Kampala',
  });

  final String name;
  final String email;
  final String role;
  final String location;
}
