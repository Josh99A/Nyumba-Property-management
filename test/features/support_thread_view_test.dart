import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/app/bootstrap/app_dependencies.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/core/offline/outbox_entry.dart';
import 'package:nyumba_property_management/features/support/domain/support_ticket.dart';
import 'package:nyumba_property_management/features/support/presentation/support_thread_view.dart';

SupportTicket _ticket({
  SupportStatus status = SupportStatus.awaitingLandlord,
  int messages = 2,
}) {
  final start = DateTime.utc(2026, 8, 12, 9, 14);
  return SupportTicket(
    id: 'ticket-1',
    landlordId: 'landlord-1',
    subject: 'Payment not reconciling',
    category: SupportCategory.billing,
    status: status,
    priority: 'high',
    messages: <SupportMessage>[
      for (var index = 0; index < messages; index += 1)
        SupportMessage(
          id: 'm$index',
          authorUid: index.isEven ? 'landlord-1' : 'admin-1',
          authorRole: index.isEven
              ? SupportAuthorRole.landlord
              : SupportAuthorRole.support,
          body: 'Message $index',
          createdAt: start.add(Duration(hours: index)),
        ),
    ],
    lastMessageAt: start.add(Duration(hours: messages - 1)),
    lastMessageAuthorRole: messages.isEven
        ? SupportAuthorRole.support
        : SupportAuthorRole.landlord,
    createdAt: start,
    updatedAt: start,
    syncMetadata: const SyncMetadata.synced(),
  );
}

OutboxEntry _entry({required OutboxState state, String? errorReason}) =>
    OutboxEntry(
      id: 'mutation-1',
      entityType: OfflineEntityType.supportTicket,
      entityId: 'ticket-1',
      operation: OutboxOperation.update,
      payload: const <String, Object?>{},
      createdAt: DateTime.utc(2026, 8, 12, 11),
      state: state,
      errorReason: errorReason,
    );

Future<void> _pump(
  WidgetTester tester, {
  required SupportTicket ticket,
  required List<OutboxEntry> outbox,
  bool asSupportAgent = false,
  Size size = const Size(1280, 900),
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // The outbox is what the thread reads its delivery truth from, so it is
        // the only dependency this widget genuinely has.
        outboxEntriesProvider.overrideWith((ref) => Stream.value(outbox)),
      ],
      child: MaterialApp(
        // No NyumbaLocalizations delegate: registering it blanks the subtree in
        // widget tests, and English source copy is what these assertions read.
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: SupportThreadView(
                ticket: ticket,
                asSupportAgent: asSupportAgent,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a settled thread shows timestamps, never a sent tick', (
    tester,
  ) async {
    await _pump(tester, ticket: _ticket(), outbox: const <OutboxEntry>[]);

    expect(find.text('Message 0'), findsOneWidget);
    expect(find.text('Message 1'), findsOneWidget);
    expect(find.text('Sending…'), findsNothing);
    expect(find.textContaining('Not sent'), findsNothing);
  });

  testWidgets('an unsent message says so instead of looking delivered', (
    tester,
  ) async {
    // Three messages, so the trailing one is the landlord's own reply — the
    // only kind that can be sitting unsent in their outbox.
    await _pump(
      tester,
      ticket: _ticket(messages: 3),
      outbox: <OutboxEntry>[_entry(state: OutboxState.pending)],
    );

    // Only the trailing message is still in the outbox; the two the server has
    // already acknowledged keep their plain timestamp.
    expect(find.text('Sending…'), findsOneWidget);
  });

  testWidgets('a failed send reports the reason, not a silent success', (
    tester,
  ) async {
    await _pump(
      tester,
      ticket: _ticket(messages: 3),
      outbox: <OutboxEntry>[
        _entry(
          state: OutboxState.permanentlyFailed,
          errorReason: 'supportTicketClosed',
        ),
      ],
    );

    // The worst bug this feature can have is a message that never left while
    // the landlord believes they have asked for help.
    expect(find.textContaining('Not sent'), findsOneWidget);
    expect(find.textContaining('supportTicketClosed'), findsOneWidget);
  });

  testWidgets('a closed conversation replaces the composer with a way out', (
    tester,
  ) async {
    await _pump(
      tester,
      ticket: _ticket(status: SupportStatus.closed),
      outbox: const <OutboxEntry>[],
    );

    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('This conversation is closed'), findsOneWidget);
  });

  testWidgets('a resolved conversation still takes a reply', (tester) async {
    // Replying reopens it: the honest reading of someone answering a resolution
    // is that it was not resolved.
    await _pump(
      tester,
      ticket: _ticket(status: SupportStatus.resolved),
      outbox: const <OutboxEntry>[],
    );

    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('each side is offered only the status moves it may make', (
    tester,
  ) async {
    await _pump(
      tester,
      ticket: _ticket(status: SupportStatus.awaitingLandlord),
      outbox: const <OutboxEntry>[],
    );
    // A landlord may close their own request and nothing else.
    expect(find.text('This is sorted'), findsOneWidget);
    expect(find.text('Mark resolved'), findsNothing);
    expect(find.text('Mark in progress'), findsNothing);

    await _pump(
      tester,
      ticket: _ticket(status: SupportStatus.awaitingLandlord),
      outbox: const <OutboxEntry>[],
      asSupportAgent: true,
    );
    expect(find.text('Mark resolved'), findsOneWidget);
    expect(find.text('Mark in progress'), findsOneWidget);
    expect(find.text('This is sorted'), findsNothing);
  });

  // A `RenderFlex overflowed` error fails the surrounding test, so pumping is
  // the assertion — the same approach layout_overflow_test.dart takes. The
  // combination that actually produces the stripes is a narrow column plus long
  // wrapped labels, and the agent view has the wordiest row on either side.
  for (final size in const <String, Size>{
    'phone': Size(393, 852),
    'tablet': Size(768, 1024),
    'desktop': Size(1280, 900),
  }.entries) {
    for (final scale in const [1.0, 1.5, 2.0]) {
      testWidgets('thread fits @ ${size.key} x$scale', (tester) async {
        await _pump(
          tester,
          ticket: _ticket(messages: 3),
          outbox: <OutboxEntry>[
            _entry(
              state: OutboxState.permanentlyFailed,
              errorReason: 'supportTicketClosed',
            ),
          ],
          asSupportAgent: true,
          size: size.value,
          textScale: scale,
        );
      });
    }
  }

  testWidgets('account context is for the agent, not the landlord', (
    tester,
  ) async {
    final ticket = SupportTicket(
      id: 'ticket-1',
      landlordId: 'landlord-1',
      subject: 'Payment not reconciling',
      category: SupportCategory.billing,
      status: SupportStatus.open,
      priority: 'high',
      messages: _ticket(messages: 1).messages,
      lastMessageAt: DateTime.utc(2026, 8, 12, 9, 14),
      lastMessageAuthorRole: SupportAuthorRole.landlord,
      landlordName: 'Sarah Nakato',
      planTier: 'growth',
      subscriptionStatus: 'past_due',
      createdAt: DateTime.utc(2026, 8, 12, 9, 14),
      updatedAt: DateTime.utc(2026, 8, 12, 9, 14),
      syncMetadata: const SyncMetadata.synced(),
    );

    await _pump(tester, ticket: ticket, outbox: const <OutboxEntry>[]);
    // Our shorthand about their account is not something they came here for.
    expect(find.textContaining('past_due'), findsNothing);

    await _pump(
      tester,
      ticket: ticket,
      outbox: const <OutboxEntry>[],
      asSupportAgent: true,
    );
    expect(find.textContaining('past_due'), findsOneWidget);
    expect(find.textContaining('Sarah Nakato'), findsOneWidget);
  });
}
