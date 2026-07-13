import '../../../core/domain/domain_validation.dart';
import '../../../core/domain/sync_metadata.dart';

enum ApplicationStatus { submitted, underReview, approved, rejected, withdrawn }

final class RentalApplication {
  RentalApplication({
    required this.id,
    required this.listingId,
    required this.unitId,
    required this.propertyId,
    required this.applicantId,
    required this.applicantName,
    required this.applicantEmail,
    required this.applicantPhone,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.syncMetadata,
    this.message,
    this.desiredMoveIn,
  }) {
    validate();
  }

  final String id;
  final String listingId;
  final String unitId;
  final String propertyId;
  final String applicantId;
  final String applicantName;
  final String applicantEmail;
  final String applicantPhone;
  final String? message;
  final DateTime? desiredMoveIn;
  final ApplicationStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncMetadata syncMetadata;

  void validate() {
    DomainValidation.check(<String, String?>{
      'id': DomainValidation.requiredText(id, maxLength: 100),
      'listingId': DomainValidation.requiredText(listingId, maxLength: 100),
      'unitId': DomainValidation.requiredText(unitId, maxLength: 100),
      'propertyId': DomainValidation.requiredText(propertyId, maxLength: 100),
      'applicantId': DomainValidation.requiredText(applicantId, maxLength: 100),
      'applicantName': DomainValidation.requiredText(
        applicantName,
        maxLength: 120,
      ),
      'applicantEmail': DomainValidation.email(applicantEmail),
      'applicantPhone': DomainValidation.requiredText(
        applicantPhone,
        maxLength: 40,
      ),
      'message': DomainValidation.optionalText(message, maxLength: 2000),
      'updatedAt': updatedAt.isBefore(createdAt)
          ? 'must not be before createdAt'
          : null,
    });
  }

  RentalApplication copyWith({
    String? applicantName,
    String? applicantEmail,
    String? applicantPhone,
    String? message,
    bool clearMessage = false,
    DateTime? desiredMoveIn,
    bool clearDesiredMoveIn = false,
    ApplicationStatus? status,
    DateTime? updatedAt,
    SyncMetadata? syncMetadata,
  }) => RentalApplication(
    id: id,
    listingId: listingId,
    unitId: unitId,
    propertyId: propertyId,
    applicantId: applicantId,
    applicantName: applicantName ?? this.applicantName,
    applicantEmail: applicantEmail ?? this.applicantEmail,
    applicantPhone: applicantPhone ?? this.applicantPhone,
    message: clearMessage ? null : (message ?? this.message),
    desiredMoveIn: clearDesiredMoveIn
        ? null
        : (desiredMoveIn ?? this.desiredMoveIn),
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    syncMetadata: syncMetadata ?? this.syncMetadata,
  );
}

final class ApplyForUnitInput {
  const ApplyForUnitInput({
    required this.listingId,
    required this.applicantId,
    required this.applicantName,
    required this.applicantEmail,
    required this.applicantPhone,
    this.message,
    this.desiredMoveIn,
  });

  final String listingId;
  final String applicantId;
  final String applicantName;
  final String applicantEmail;
  final String applicantPhone;
  final String? message;
  final DateTime? desiredMoveIn;

  void validate() {
    DomainValidation.check(<String, String?>{
      'listingId': DomainValidation.requiredText(listingId, maxLength: 100),
      'applicantId': DomainValidation.requiredText(applicantId, maxLength: 100),
      'applicantName': DomainValidation.requiredText(
        applicantName,
        maxLength: 120,
      ),
      'applicantEmail': DomainValidation.email(applicantEmail),
      'applicantPhone': DomainValidation.requiredText(
        applicantPhone,
        maxLength: 40,
      ),
      'message': DomainValidation.optionalText(message, maxLength: 2000),
    });
  }
}
