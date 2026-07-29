// ignore_for_file: prefer_initializing_formals

import 'package:nyumba_property_management/core/domain/clock.dart';
import 'package:nyumba_property_management/core/domain/domain_exception.dart';
import 'package:nyumba_property_management/core/domain/id_generator.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/core/offline/outbox_entry.dart';
import 'package:nyumba_property_management/core/offline/uuid_id_generator.dart';
import 'package:nyumba_property_management/features/support/data/mappers/support_ticket_mapper.dart';
import 'package:nyumba_property_management/features/support/domain/support_repository.dart';
import 'package:nyumba_property_management/features/support/domain/support_ticket.dart';

final class SembastSupportRepository implements SupportRepository {
  SembastSupportRepository({
    required OfflineDatabase database,
    IdGenerator? idGenerator,
    Clock clock = const SystemClock(),
  }) : _database = database,
       _idGenerator = idGenerator ?? UuidIdGenerator(),
       _clock = clock;

  final OfflineDatabase _database;
  final IdGenerator _idGenerator;
  final Clock _clock;

  @override
  Future<SupportTicket> open({
    required String landlordId,
    required String subject,
    required SupportCategory category,
    required String body,
    required String appVersion,
    required String platform,
    String? landlordName,
    String? landlordEmail,
  }) async {
    final trimmedSubject = subject.trim();
    final trimmedBody = body.trim();
    if (trimmedSubject.isEmpty) {
      throw DomainValidationException(<String, String>{
        'subject': 'give this a short title',
      });
    }
    if (trimmedBody.isEmpty) {
      throw DomainValidationException(<String, String>{
        'body': 'tell us what is happening',
      });
    }
    final now = _clock.now().toUtc();
    final id = _idGenerator.generate();
    final ticket = SupportTicket(
      id: id,
      landlordId: landlordId,
      subject: trimmedSubject,
      category: category,
      status: SupportStatus.open,
      // Optimistic mirror of the server's derivation. Shown, never sent — the
      // command schema rejects a priority field outright.
      priority: category.isUrgent ? 'high' : 'normal',
      messages: <SupportMessage>[
        SupportMessage(
          id: '${id}_initial',
          authorUid: landlordId,
          authorRole: SupportAuthorRole.landlord,
          body: trimmedBody,
          createdAt: now,
        ),
      ],
      lastMessageAt: now,
      lastMessageAuthorRole: SupportAuthorRole.landlord,
      landlordName: landlordName,
      landlordEmail: landlordEmail,
      appVersion: appVersion,
      platform: platform,
      createdAt: now,
      updatedAt: now,
      pendingAction: SupportAction.open,
      syncMetadata: const SyncMetadata.pending(),
    );
    // Enqueued like any other write, so a message composed on a bad connection
    // survives — which is exactly the connection someone is complaining about.
    await _database.putEntityAndEnqueue(
      entityType: OfflineEntityType.supportTicket,
      entityId: ticket.id,
      entity: SupportTicketMapper.toJson(ticket),
      mutationId: _idGenerator.generate(),
      operation: OutboxOperation.create,
      createdAt: now,
      createOnly: true,
    );
    return ticket;
  }

  @override
  Future<SupportTicket> reply({
    required String ticketId,
    required String authorUid,
    required String body,
  }) async {
    final current = await _require(ticketId);
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      throw DomainValidationException(<String, String>{
        'body': 'a reply cannot be empty',
      });
    }
    if (!current.status.acceptsReplies) {
      throw DomainValidationException(<String, String>{
        'body': 'this conversation is closed',
      });
    }
    final now = _clock.now().toUtc();
    // The author is whoever owns the workspace this reply was written from. The
    // server re-derives it from the ticket and ignores anything sent, so this
    // value only ever affects how the message renders before it syncs.
    final authorRole = current.landlordId == authorUid
        ? SupportAuthorRole.landlord
        : SupportAuthorRole.support;
    return _enqueueUpdate(
      current.copyWith(
        messages: <SupportMessage>[
          ...current.messages,
          SupportMessage(
            // The mutation ID doubles as the message ID so a retried send
            // appends once, matching the server's `cmd.commandId` keying.
            id: _idGenerator.generate(),
            authorUid: authorUid,
            authorRole: authorRole,
            body: trimmed,
            createdAt: now,
          ),
        ],
        // Mirrors the server's own advance-on-reply rule, so the thread does not
        // sit visibly on the wrong status until the next pull lands.
        status: authorRole == SupportAuthorRole.landlord
            ? (current.status == SupportStatus.open
                  ? SupportStatus.open
                  : SupportStatus.inProgress)
            : SupportStatus.awaitingLandlord,
        lastMessageAt: now,
        lastMessageAuthorRole: authorRole,
        pendingAction: SupportAction.reply,
      ),
      now,
    );
  }

  @override
  Future<SupportTicket> updateStatus({
    required String ticketId,
    required SupportStatus status,
    String? note,
  }) async {
    final current = await _require(ticketId);
    if (current.status == status) {
      throw DomainValidationException(<String, String>{
        'status': 'this conversation is already there',
      });
    }
    final now = _clock.now().toUtc();
    return _enqueueUpdate(
      current.copyWith(
        status: status,
        statusNote: note?.trim().isEmpty ?? true ? null : note!.trim(),
        resolvedAt: status == SupportStatus.resolved ? now : null,
        closedAt: status == SupportStatus.closed ? now : null,
        pendingAction: SupportAction.updateStatus,
      ),
      now,
    );
  }

  Future<SupportTicket> _enqueueUpdate(SupportTicket next, DateTime now) async {
    final updated = next.copyWith(
      updatedAt: now,
      syncMetadata: next.syncMetadata.markPending(),
    );
    await _database.putEntityAndEnqueue(
      entityType: OfflineEntityType.supportTicket,
      entityId: updated.id,
      entity: SupportTicketMapper.toJson(updated),
      mutationId: _idGenerator.generate(),
      operation: OutboxOperation.update,
      createdAt: now,
    );
    return updated;
  }

  @override
  Future<SupportTicket?> getById(String id) async {
    final json = await _database.readEntity(
      OfflineEntityType.supportTicket,
      id,
    );
    return json == null ? null : SupportTicketMapper.fromJson(json);
  }

  @override
  Stream<List<SupportTicket>> watchAll({String? landlordId}) => _database
      .watchEntities(OfflineEntityType.supportTicket)
      .map(
        (items) => _sorted(items.map(SupportTicketMapper.fromJson), landlordId),
      );

  @override
  Stream<SupportTicket?> watchById(String id) => _database
      .watchEntity(OfflineEntityType.supportTicket, id)
      .map((json) => json == null ? null : SupportTicketMapper.fromJson(json));

  Future<SupportTicket> _require(String id) async {
    final ticket = await getById(id);
    if (ticket == null) throw EntityNotFoundException('supportTicket', id);
    return ticket;
  }

  /// Most recent activity first, which is the order both sides read in: a
  /// landlord looks for the thread they just wrote on, an agent for the one
  /// that just moved.
  static List<SupportTicket> _sorted(
    Iterable<SupportTicket> items,
    String? landlordId,
  ) {
    final result = items
        .where(
          (ticket) => landlordId == null || ticket.landlordId == landlordId,
        )
        .toList(growable: false);
    result.sort(
      (left, right) => right.lastMessageAt.compareTo(left.lastMessageAt),
    );
    return result;
  }
}
