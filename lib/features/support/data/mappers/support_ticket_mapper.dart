import 'package:nyumba_property_management/core/offline/json_reader.dart';
import 'package:nyumba_property_management/core/offline/sync_metadata_mapper.dart';
import 'package:nyumba_property_management/features/support/domain/support_ticket.dart';

/// Translates between [SupportTicket] and the persisted/remote JSON shape.
///
/// The field names here are also the server's: `supportOpen` in
/// `functions/src/commands/support.ts` writes exactly these keys onto
/// `supportTickets/{id}`, and the landlord and admin pulls read that canonical
/// document directly rather than through a projection. That pairing is what
/// makes the pull work at all — every earlier client pull was written against a
/// mapper that already existed and did not fit, which surfaced as a
/// FormatException on a screen far from the mismatch.
///
/// Consequence: a rename on either side must land on both, in one change.
/// `support_ticket_mapper_test.dart` pins the field list from this side.
final class SupportTicketMapper {
  const SupportTicketMapper._();

  static Map<String, Object?> toJson(SupportTicket ticket) => <String, Object?>{
    'id': ticket.id,
    'version': ticket.version,
    'landlordId': ticket.landlordId,
    'subject': ticket.subject,
    'category': ticket.category.name,
    'status': ticket.status.wireName,
    // Derived from the status rather than carried independently, so a local
    // record can never disagree with itself about whether it is still running.
    'isTerminal': ticket.status.isTerminal,
    'priority': ticket.priority,
    'messages': <Object?>[
      for (final message in ticket.messages) _messageToJson(message),
    ],
    'lastMessageAt': ticket.lastMessageAt.toUtc().toIso8601String(),
    'lastMessageAuthorRole': ticket.lastMessageAuthorRole.name,
    'firstResponseAt': ticket.firstResponseAt?.toUtc().toIso8601String(),
    'resolvedAt': ticket.resolvedAt?.toUtc().toIso8601String(),
    'closedAt': ticket.closedAt?.toUtc().toIso8601String(),
    'statusNote': ticket.statusNote,
    'landlordName': ticket.landlordName,
    'landlordEmail': ticket.landlordEmail,
    'planTier': ticket.planTier,
    'subscriptionStatus': ticket.subscriptionStatus,
    'approvalStatus': ticket.approvalStatus,
    'appVersion': ticket.appVersion,
    'platform': ticket.platform,
    'createdAt': ticket.createdAt.toUtc().toIso8601String(),
    'updatedAt': ticket.updatedAt.toUtc().toIso8601String(),
    // Locally authored intent, never published by the server. It is what tells
    // the sync gateway which of the three support commands this record carries.
    'pendingAction': ticket.pendingAction?.name,
    'syncMetadata': SyncMetadataMapper.toJson(ticket.syncMetadata),
  };

  static SupportTicket fromJson(Map<String, Object?> json) {
    final reader = JsonReader(json);
    final messages = _messagesFrom(json['messages']);
    // A pulled ticket always carries both, but a record written by an older
    // client build might not; the last message is the same answer.
    final lastMessageAt =
        reader.optionalDate('lastMessageAt') ??
        messages.lastOrNull?.createdAt ??
        reader.requiredDate('createdAt');
    return SupportTicket(
      id: reader.requiredString('id'),
      version: reader.optionalInt('version') ?? 1,
      landlordId: reader.requiredString('landlordId'),
      subject: reader.requiredString('subject'),
      category: reader.enumValue('category', SupportCategory.values),
      status: SupportStatus.fromWire(reader.requiredString('status')),
      priority: reader.optionalString('priority') ?? 'normal',
      messages: messages,
      lastMessageAt: lastMessageAt,
      lastMessageAuthorRole: _role(json['lastMessageAuthorRole']),
      firstResponseAt: reader.optionalDate('firstResponseAt'),
      resolvedAt: reader.optionalDate('resolvedAt'),
      closedAt: reader.optionalDate('closedAt'),
      statusNote: reader.optionalString('statusNote'),
      landlordName: reader.optionalString('landlordName'),
      landlordEmail: reader.optionalString('landlordEmail'),
      planTier: reader.optionalString('planTier'),
      subscriptionStatus: reader.optionalString('subscriptionStatus'),
      approvalStatus: reader.optionalString('approvalStatus'),
      appVersion: reader.optionalString('appVersion'),
      platform: reader.optionalString('platform'),
      createdAt: reader.requiredDate('createdAt'),
      updatedAt: reader.requiredDate('updatedAt'),
      pendingAction: _action(json['pendingAction']),
      syncMetadata: SyncMetadataMapper.fromJson(json['syncMetadata']),
    );
  }

  static Map<String, Object?> _messageToJson(SupportMessage message) =>
      <String, Object?>{
        'id': message.id,
        'authorUid': message.authorUid,
        'authorRole': message.authorRole.name,
        'body': message.body,
        'attachmentPaths': message.attachmentPaths,
        'createdAt': message.createdAt.toUtc().toIso8601String(),
      };

  /// Messages arrive as a Firestore array of maps, already normalised to ISO
  /// strings by `FirestoreRemotePullGateway._normalize`. Anything that is not a
  /// well-formed entry is dropped rather than thrown on: one malformed message
  /// must not make the whole conversation unreadable, which is precisely the
  /// moment a landlord needs to see the rest of it.
  static List<SupportMessage> _messagesFrom(Object? raw) {
    if (raw is! List) return const <SupportMessage>[];
    final messages = <SupportMessage>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final map = Map<String, Object?>.from(entry);
      final id = map['id'];
      final body = map['body'];
      final createdAt = map['createdAt'];
      if (id is! String || body is! String || createdAt is! String) continue;
      final parsed = DateTime.tryParse(createdAt);
      if (parsed == null) continue;
      messages.add(
        SupportMessage(
          id: id,
          authorUid: map['authorUid'] is String
              ? map['authorUid']! as String
              : '',
          authorRole: _role(map['authorRole']),
          body: body,
          attachmentPaths: <String>[
            for (final path in (map['attachmentPaths'] as List<Object?>? ??
                const <Object?>[]))
              if (path is String) path,
          ],
          createdAt: parsed.toUtc(),
        ),
      );
    }
    messages.sort((left, right) => left.createdAt.compareTo(right.createdAt));
    return List<SupportMessage>.unmodifiable(messages);
  }

  /// Absence means the landlord: they are the only party who can start a
  /// thread, so an unlabelled message is theirs.
  static SupportAuthorRole _role(Object? raw) =>
      raw == 'support' ? SupportAuthorRole.support : SupportAuthorRole.landlord;

  static SupportAction? _action(Object? raw) {
    if (raw is! String) return null;
    for (final value in SupportAction.values) {
      if (value.name == raw) return value;
    }
    return null;
  }
}
