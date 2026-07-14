import '../../../core/domain/domain_validation.dart';
import '../../../core/domain/sync_metadata.dart';

enum MaintenancePriority { normal, high, urgent }

enum MaintenanceStatus { submitted, scheduled, inProgress, resolved, cancelled }

extension MaintenanceStatusX on MaintenanceStatus {
  bool get isOpen =>
      this == MaintenanceStatus.submitted ||
      this == MaintenanceStatus.scheduled;

  bool get isTerminal =>
      this == MaintenanceStatus.resolved || this == MaintenanceStatus.cancelled;
}

/// One maintenance request aggregate shared by the tenant reporting flow and
/// the landlord work-order flow. Location and reporter labels are denormalized
/// projections so lists render without cross-aggregate lookups.
final class MaintenanceRequest {
  MaintenanceRequest({
    required this.id,
    required this.reference,
    required this.landlordId,
    required this.title,
    required this.description,
    required this.location,
    required this.category,
    required this.priority,
    required this.status,
    required this.reporterName,
    required this.reportedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.syncMetadata,
    this.tenantId,
    this.propertyId,
    this.unitId,
    this.assignee,
    this.appointment,
    this.allowAccess = false,
    this.photoCount = 0,
    this.resolvedAt,
  }) {
    validate();
  }

  final String id;

  /// Human-readable work-order reference such as `MNT-2048`.
  final String reference;
  final String landlordId;
  final String? tenantId;
  final String? propertyId;
  final String? unitId;
  final String title;
  final String description;

  /// Display location such as `Unit A2 · Greenview Court`.
  final String location;
  final String category;
  final MaintenancePriority priority;
  final MaintenanceStatus status;
  final String reporterName;
  final String? assignee;

  /// Free-form appointment window agreed with the tenant.
  final String? appointment;
  final bool allowAccess;
  final int photoCount;
  final DateTime reportedAt;
  final DateTime? resolvedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncMetadata syncMetadata;

  void validate() {
    DomainValidation.check(<String, String?>{
      'reference': DomainValidation.requiredText(reference, maxLength: 40),
      'landlordId': DomainValidation.requiredText(landlordId, maxLength: 100),
      'title': DomainValidation.requiredText(title, maxLength: 120),
      'description': DomainValidation.requiredText(
        description,
        maxLength: 2000,
      ),
      'location': DomainValidation.requiredText(location, maxLength: 160),
      'category': DomainValidation.requiredText(category, maxLength: 60),
      'reporterName': DomainValidation.requiredText(
        reporterName,
        maxLength: 120,
      ),
      'photoCount': DomainValidation.nonNegativeInt(photoCount),
      'resolvedAt': status == MaintenanceStatus.resolved && resolvedAt == null
          ? 'is required once a request is resolved'
          : null,
    });
  }

  MaintenanceRequest copyWith({
    MaintenanceStatus? status,
    MaintenancePriority? priority,
    String? assignee,
    bool clearAssignee = false,
    String? appointment,
    bool clearAppointment = false,
    DateTime? resolvedAt,
    DateTime? updatedAt,
    SyncMetadata? syncMetadata,
  }) => MaintenanceRequest(
    id: id,
    reference: reference,
    landlordId: landlordId,
    tenantId: tenantId,
    propertyId: propertyId,
    unitId: unitId,
    title: title,
    description: description,
    location: location,
    category: category,
    priority: priority ?? this.priority,
    status: status ?? this.status,
    reporterName: reporterName,
    assignee: clearAssignee ? null : (assignee ?? this.assignee),
    appointment: clearAppointment ? null : (appointment ?? this.appointment),
    allowAccess: allowAccess,
    photoCount: photoCount,
    reportedAt: reportedAt,
    resolvedAt: resolvedAt ?? this.resolvedAt,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    syncMetadata: syncMetadata ?? this.syncMetadata,
  );
}

final class CreateMaintenanceRequestInput {
  const CreateMaintenanceRequestInput({
    required this.landlordId,
    required this.title,
    required this.description,
    required this.location,
    required this.reporterName,
    this.category = 'General',
    this.priority = MaintenancePriority.normal,
    this.tenantId,
    this.propertyId,
    this.unitId,
    this.allowAccess = false,
    this.photoCount = 0,
  });

  final String landlordId;
  final String title;
  final String description;
  final String location;
  final String reporterName;
  final String category;
  final MaintenancePriority priority;
  final String? tenantId;
  final String? propertyId;
  final String? unitId;
  final bool allowAccess;
  final int photoCount;
}

final class TransitionMaintenanceInput {
  const TransitionMaintenanceInput({
    required this.requestId,
    required this.status,
    this.assignee,
    this.appointment,
  });

  final String requestId;
  final MaintenanceStatus status;
  final String? assignee;
  final String? appointment;
}
