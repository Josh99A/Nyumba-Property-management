/// Pins the Dart half of the support-ticket read contract.
///
/// Unlike every other pulled aggregate there is no projection here: the landlord
/// and admin pulls read the canonical `supportTickets/{id}` document directly,
/// because its Firestore shape and this mapper were written together in one
/// change. That is exactly what makes them able to drift silently later — a
/// rename on the server would surface as a FormatException on a screen far from
/// the cause, which is the failure mode that disabled the tenant pull entirely.
///
/// Keep this in step with `supportOpen` and `supportReply` in
/// `firebase/functions/src/commands/support.ts`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/features/support/data/mappers/support_ticket_mapper.dart';
import 'package:nyumba_property_management/features/support/domain/support_ticket.dart';

/// Byte-for-byte what the command writes, after `_normalize` has turned every
/// Timestamp into an ISO-8601 string and `mergeRemoteEntity` has stamped
/// `syncMetadata` on the merged record.
Map<String, Object?> serverTicket() => <String, Object?>{
  'id': 'ticket-1',
  'version': 3,
  'createdAt': '2026-08-12T09:14:00.000Z',
  'updatedAt': '2026-08-12T11:02:00.000Z',
  'isDeleted': false,
  'landlordId': 'landlord-1',
  'openedByUid': 'landlord-1',
  'subject': 'Payment not reconciling',
  'category': 'billing',
  'status': 'awaiting_landlord',
  'isTerminal': false,
  'priority': 'high',
  'messages': <Object?>[
    <String, Object?>{
      'id': 'cmd-1_initial',
      'authorUid': 'landlord-1',
      'authorRole': 'landlord',
      'body': 'My tenant paid on the 3rd but the balance has not moved.',
      'attachmentPaths': <Object?>[],
      'createdAt': '2026-08-12T09:14:00.000Z',
    },
    <String, Object?>{
      'id': 'cmd-2',
      'authorUid': 'admin-1',
      'authorRole': 'support',
      'body': 'Thanks — could you send the MTN reference?',
      'attachmentPaths': <Object?>[],
      'createdAt': '2026-08-12T11:02:00.000Z',
    },
  ],
  'lastMessageAt': '2026-08-12T11:02:00.000Z',
  'lastMessageAuthorRole': 'support',
  'firstResponseAt': '2026-08-12T11:02:00.000Z',
  'resolvedAt': null,
  'closedAt': null,
  'landlordName': 'Sarah Nakato',
  'landlordEmail': 'sarah@example.ug',
  'planTier': 'growth',
  'subscriptionStatus': 'active',
  'approvalStatus': 'approved',
  'appVersion': '1.4.2+31',
  'platform': 'android',
  'locale': 'en',
  'syncMetadata': <String, Object?>{
    'state': 'synced',
    'serverRevision': '3',
    'lastSyncedAt': '2026-08-12T11:02:00.000Z',
    'lastError': null,
  },
};

void main() {
  group('SupportTicketMapper.fromJson', () {
    test('reads a pulled ticket without losing a field the UI renders', () {
      final ticket = SupportTicketMapper.fromJson(serverTicket());

      expect(ticket.id, 'ticket-1');
      expect(ticket.version, 3);
      expect(ticket.landlordId, 'landlord-1');
      expect(ticket.subject, 'Payment not reconciling');
      expect(ticket.category, SupportCategory.billing);
      expect(ticket.status, SupportStatus.awaitingLandlord);
      expect(ticket.priority, 'high');
      expect(ticket.messages, hasLength(2));
      expect(ticket.messages.first.authorRole, SupportAuthorRole.landlord);
      expect(ticket.messages.last.authorRole, SupportAuthorRole.support);
      expect(ticket.firstResponseAt, isNotNull);
      // The denormalized context the admin queue renders instead of joining.
      expect(ticket.landlordName, 'Sarah Nakato');
      expect(ticket.planTier, 'growth');
      expect(ticket.subscriptionStatus, 'active');
      expect(ticket.appVersion, '1.4.2+31');
      expect(ticket.syncMetadata.state, EntitySyncState.synced);
    });

    test('translates the snake_case statuses the command writes', () {
      // The one place the two languages genuinely differ. A mapper that read
      // these as unknown would throw on every in-flight ticket.
      for (final (wire, expected) in const <(String, SupportStatus)>[
        ('open', SupportStatus.open),
        ('in_progress', SupportStatus.inProgress),
        ('awaiting_landlord', SupportStatus.awaitingLandlord),
        ('resolved', SupportStatus.resolved),
        ('closed', SupportStatus.closed),
      ]) {
        final ticket = SupportTicketMapper.fromJson(<String, Object?>{
          ...serverTicket(),
          'status': wire,
        });
        expect(ticket.status, expected, reason: wire);
      }
    });

    test('drops a malformed message rather than the conversation', () {
      // One bad entry must not make the whole thread unreadable — that is
      // precisely the moment someone needs to see the rest of it.
      final ticket = SupportTicketMapper.fromJson(<String, Object?>{
        ...serverTicket(),
        'messages': <Object?>[
          <String, Object?>{
            'id': 'good',
            'authorUid': 'landlord-1',
            'authorRole': 'landlord',
            'body': 'Still nothing.',
            'createdAt': '2026-08-13T08:00:00.000Z',
          },
          <String, Object?>{'id': 'no-body', 'createdAt': 'not-a-date'},
          'not even a map',
        ],
      });
      expect(ticket.messages, hasLength(1));
      expect(ticket.messages.single.body, 'Still nothing.');
    });

    test('orders messages by time, whatever order they arrived in', () {
      final ticket = SupportTicketMapper.fromJson(<String, Object?>{
        ...serverTicket(),
        'messages': <Object?>[
          <String, Object?>{
            'id': 'later',
            'authorRole': 'support',
            'body': 'Second.',
            'createdAt': '2026-08-12T11:02:00.000Z',
          },
          <String, Object?>{
            'id': 'earlier',
            'authorRole': 'landlord',
            'body': 'First.',
            'createdAt': '2026-08-12T09:14:00.000Z',
          },
        ],
      });
      expect(
        ticket.messages.map((message) => message.body),
        <String>['First.', 'Second.'],
      );
    });
  });

  group('SupportTicketMapper.toJson', () {
    test('round-trips a ticket through the persisted shape', () {
      final original = SupportTicketMapper.fromJson(serverTicket());
      final restored = SupportTicketMapper.fromJson(
        SupportTicketMapper.toJson(original),
      );

      expect(restored.status, original.status);
      expect(restored.category, original.category);
      expect(restored.subject, original.subject);
      expect(restored.messages.length, original.messages.length);
      expect(restored.lastMessageAuthorRole, original.lastMessageAuthorRole);
      expect(restored.planTier, original.planTier);
    });

    test('derives isTerminal from the status it is writing', () {
      final ticket = SupportTicketMapper.fromJson(<String, Object?>{
        ...serverTicket(),
        'status': 'resolved',
        // Deliberately stale: a local record must never be able to disagree
        // with itself about whether the conversation is still running.
        'isTerminal': false,
      });
      expect(SupportTicketMapper.toJson(ticket)['isTerminal'], isTrue);
    });
  });

  group('SupportTicket', () {
    test('says who the ball is with', () {
      final ticket = SupportTicketMapper.fromJson(serverTicket());
      expect(ticket.awaitsLandlord, isTrue);
      expect(ticket.awaitsSupport, isFalse);

      final resolved = ticket.copyWith(status: SupportStatus.resolved);
      // A resolved ticket is waiting on nobody, whoever spoke last.
      expect(resolved.awaitsLandlord, isFalse);
      expect(resolved.awaitsSupport, isFalse);
    });

    test('accepts replies until it is closed, including once resolved', () {
      // Replying to a resolution reopens it, because the honest reading of
      // someone answering a resolution is that it was not resolved.
      expect(SupportStatus.resolved.acceptsReplies, isTrue);
      expect(SupportStatus.closed.acceptsReplies, isFalse);
    });

    test('allows a reopen only inside the window, from a real resolution', () {
      final base = SupportTicketMapper.fromJson(serverTicket());
      final now = DateTime.utc(2026, 8, 20);

      final fresh = base.copyWith(
        status: SupportStatus.resolved,
        resolvedAt: now.subtract(const Duration(days: 3)),
      );
      final stale = base.copyWith(
        status: SupportStatus.resolved,
        resolvedAt: now.subtract(const Duration(days: 30)),
      );

      expect(fresh.reopenableAt(now), isTrue);
      expect(stale.reopenableAt(now), isFalse);
      // Never resolved, so there is nothing to reopen.
      expect(base.reopenableAt(now), isFalse);
    });
  });
}
