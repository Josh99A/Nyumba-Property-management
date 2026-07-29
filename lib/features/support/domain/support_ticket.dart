import 'package:nyumba_property_management/core/domain/sync_metadata.dart';

/// What a support conversation is about.
///
/// Six buckets, chosen so a landlord can pick one without reading all of them.
/// The category is what routes the ticket and what derives its priority on the
/// server, so it is asked before the message rather than after.
enum SupportCategory {
  billing,
  payments,
  tenants,
  listings,
  account,
  other;

  /// Whether Nyumba treats this as time-critical regardless of what was typed.
  /// Mirrors the server's derivation in `commands/support.ts` — shown to set
  /// expectations, never sent, because a client-chosen priority is a field
  /// where everyone picks urgent.
  bool get isUrgent =>
      this == SupportCategory.billing || this == SupportCategory.account;
}

/// Where a ticket sits in its lifecycle.
///
/// The wire names are snake_case because that is what the command schema and
/// the canonical document use; carrying them on the enum keeps the translation
/// in one place instead of spreading `_snakeCase` calls through the mapper and
/// the sync gateway.
enum SupportStatus {
  open('open'),
  inProgress('in_progress'),
  awaitingLandlord('awaiting_landlord'),
  resolved('resolved'),
  closed('closed');

  const SupportStatus(this.wireName);

  final String wireName;

  static SupportStatus fromWire(String raw) => values.firstWhere(
    (value) => value.wireName == raw,
    orElse: () => throw FormatException('Unknown support status "$raw".'),
  );

  /// Nothing further is expected from either side.
  bool get isTerminal =>
      this == SupportStatus.resolved || this == SupportStatus.closed;

  /// Whether the landlord can still write on this thread. A `resolved` ticket
  /// stays open to replies on purpose: the honest reading of someone answering
  /// a resolution is that it was not resolved.
  bool get acceptsReplies => this != SupportStatus.closed;
}

enum SupportAuthorRole { landlord, support }

/// The edit a pending ticket record is carrying to the server.
///
/// Three commands share the five generic [OutboxOperation] values, so the
/// operation alone cannot name the intent. The repository stamps this and
/// `firebase_remote_sync_gateway` reads it back — the same shape as
/// `ReviewAction`.
enum SupportAction { open, reply, updateStatus }

final class SupportMessage {
  const SupportMessage({
    required this.id,
    required this.authorUid,
    required this.authorRole,
    required this.body,
    required this.createdAt,
    this.attachmentPaths = const <String>[],
  });

  final String id;
  final String authorUid;
  final SupportAuthorRole authorRole;
  final String body;
  final List<String> attachmentPaths;
  final DateTime createdAt;

  bool get isFromSupport => authorRole == SupportAuthorRole.support;
}

final class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.landlordId,
    required this.subject,
    required this.category,
    required this.status,
    required this.priority,
    required this.messages,
    required this.lastMessageAt,
    required this.lastMessageAuthorRole,
    required this.createdAt,
    required this.updatedAt,
    required this.syncMetadata,
    this.version = 1,
    this.firstResponseAt,
    this.resolvedAt,
    this.closedAt,
    this.statusNote,
    this.landlordName,
    this.landlordEmail,
    this.planTier,
    this.subscriptionStatus,
    this.approvalStatus,
    this.appVersion,
    this.platform,
    this.pendingAction,
  });

  final String id;
  final String landlordId;
  final String subject;
  final SupportCategory category;
  final SupportStatus status;

  /// Server-derived. Rendered in the admin queue, never offered as a control.
  final String priority;

  final List<SupportMessage> messages;
  final DateTime lastMessageAt;
  final SupportAuthorRole lastMessageAuthorRole;

  /// When Nyumba first answered. The one number worth measuring this desk by.
  final DateTime? firstResponseAt;
  final DateTime? resolvedAt;
  final DateTime? closedAt;
  final String? statusNote;

  /// Account context captured when the ticket was opened, so whoever answers is
  /// not reading a tier the landlord has since moved off.
  final String? landlordName;
  final String? landlordEmail;
  final String? planTier;
  final String? subscriptionStatus;
  final String? approvalStatus;
  final String? appVersion;
  final String? platform;

  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;
  final SyncMetadata syncMetadata;
  final SupportAction? pendingAction;

  /// Whether the ball is with the landlord — drives "Needs you" on their list
  /// and keeps the admin queue's "needs reply" filter off the message array.
  bool get awaitsLandlord =>
      lastMessageAuthorRole == SupportAuthorRole.support && !status.isTerminal;

  bool get awaitsSupport =>
      lastMessageAuthorRole == SupportAuthorRole.landlord && !status.isTerminal;

  SupportMessage? get latestMessage => messages.isEmpty ? null : messages.last;

  /// Mirrors `SUPPORT_REOPEN_WINDOW_DAYS`. Past it, a landlord starts a new
  /// conversation rather than reviving one nobody has looked at in a fortnight.
  static const Duration reopenWindow = Duration(days: 14);

  bool reopenableAt(DateTime now) =>
      status == SupportStatus.resolved &&
      resolvedAt != null &&
      now.difference(resolvedAt!) <= reopenWindow;

  SupportTicket copyWith({
    SupportStatus? status,
    List<SupportMessage>? messages,
    DateTime? lastMessageAt,
    SupportAuthorRole? lastMessageAuthorRole,
    DateTime? resolvedAt,
    DateTime? closedAt,
    String? statusNote,
    DateTime? updatedAt,
    int? version,
    SyncMetadata? syncMetadata,
    SupportAction? pendingAction,
  }) => SupportTicket(
    id: id,
    landlordId: landlordId,
    subject: subject,
    category: category,
    status: status ?? this.status,
    priority: priority,
    messages: messages ?? this.messages,
    lastMessageAt: lastMessageAt ?? this.lastMessageAt,
    lastMessageAuthorRole: lastMessageAuthorRole ?? this.lastMessageAuthorRole,
    firstResponseAt: firstResponseAt,
    resolvedAt: resolvedAt ?? this.resolvedAt,
    closedAt: closedAt ?? this.closedAt,
    statusNote: statusNote ?? this.statusNote,
    landlordName: landlordName,
    landlordEmail: landlordEmail,
    planTier: planTier,
    subscriptionStatus: subscriptionStatus,
    approvalStatus: approvalStatus,
    appVersion: appVersion,
    platform: platform,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    version: version ?? this.version,
    syncMetadata: syncMetadata ?? this.syncMetadata,
    pendingAction: pendingAction ?? this.pendingAction,
  );
}
