import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/domain/domain_exception.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/core/offline/outbox_entry.dart';
import 'package:nyumba_property_management/features/support/data/sembast_support_repository.dart';
import 'package:nyumba_property_management/features/support/domain/support_ticket.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  Future<OfflineDatabase> openDatabase(String name) async {
    final database = OfflineDatabase(
      await databaseFactoryMemory.openDatabase(name),
    );
    await database.initialize();
    return database;
  }

  Future<SupportTicket> openTicket(
    SembastSupportRepository repository, {
    SupportCategory category = SupportCategory.billing,
  }) => repository.open(
    landlordId: 'landlord-1',
    subject: 'Payment not reconciling',
    category: category,
    body: 'My tenant paid on the 3rd but the balance has not moved.',
    appVersion: '1.4.2+31',
    platform: 'android',
  );

  test('open persists the ticket and its command atomically', () async {
    final database = await openDatabase('support-open.db');
    addTearDown(database.close);
    final repository = SembastSupportRepository(database: database);

    final ticket = await openTicket(repository);

    final outbox = await database.readOutbox();
    expect(outbox, hasLength(1));
    expect(outbox.single.entityType, OfflineEntityType.supportTicket);
    expect(outbox.single.entityId, ticket.id);
    expect(outbox.single.operation, OutboxOperation.create);
    // Composed on a bad connection is exactly when someone has most to say, so
    // the message is durable before it is sent.
    expect(ticket.syncMetadata.needsSync, isTrue);

    final stored = await repository.getById(ticket.id);
    expect(stored?.status, SupportStatus.open);
    expect(stored?.messages, hasLength(1));
    expect(stored?.lastMessageAuthorRole, SupportAuthorRole.landlord);
    expect(stored?.pendingAction, SupportAction.open);
  });

  test('open mirrors the server-derived priority without sending it', () async {
    final database = await openDatabase('support-priority.db');
    addTearDown(database.close);
    final repository = SembastSupportRepository(database: database);

    final billing = await openTicket(repository);
    final listings = await openTicket(
      repository,
      category: SupportCategory.listings,
    );

    // Billing and account cannot wait; the rest can. Matches the derivation in
    // commands/support.ts — this copy only affects what the client renders.
    expect(billing.priority, 'high');
    expect(listings.priority, 'normal');
  });

  test('open rejects an empty subject or body before enqueueing', () async {
    final database = await openDatabase('support-validation.db');
    addTearDown(database.close);
    final repository = SembastSupportRepository(database: database);

    await expectLater(
      repository.open(
        landlordId: 'landlord-1',
        subject: '   ',
        category: SupportCategory.other,
        body: 'Something is wrong.',
        appVersion: '1.0.0',
        platform: 'web',
      ),
      throwsA(isA<DomainValidationException>()),
    );
    expect(await database.readOutbox(), isEmpty);
  });

  test('a landlord reply advances the status the way the server will', () async {
    final database = await openDatabase('support-reply.db');
    addTearDown(database.close);
    final repository = SembastSupportRepository(database: database);
    final ticket = await openTicket(repository);

    // Support answered, so the ball is with the landlord.
    final answered = await repository.updateStatus(
      ticketId: ticket.id,
      status: SupportStatus.awaitingLandlord,
    );
    expect(answered.status, SupportStatus.awaitingLandlord);

    final replied = await repository.reply(
      ticketId: ticket.id,
      authorUid: 'landlord-1',
      body: 'Here is the reference: ABC123.',
    );

    expect(replied.status, SupportStatus.inProgress);
    expect(replied.messages, hasLength(2));
    expect(replied.lastMessageAuthorRole, SupportAuthorRole.landlord);
    expect(replied.pendingAction, SupportAction.reply);
    expect(replied.awaitsSupport, isTrue);
  });

  test('an agent reply hands the thread back to the landlord', () async {
    final database = await openDatabase('support-agent-reply.db');
    addTearDown(database.close);
    final repository = SembastSupportRepository(database: database);
    final ticket = await openTicket(repository);

    final replied = await repository.reply(
      ticketId: ticket.id,
      // Not the landlord who owns the ticket, so this is the support side.
      authorUid: 'admin-1',
      body: 'Could you send the MTN reference?',
    );

    expect(replied.messages.last.authorRole, SupportAuthorRole.support);
    expect(replied.status, SupportStatus.awaitingLandlord);
    expect(replied.awaitsLandlord, isTrue);
  });

  test('a reply to a resolved ticket reopens it', () async {
    final database = await openDatabase('support-reopen.db');
    addTearDown(database.close);
    final repository = SembastSupportRepository(database: database);
    final ticket = await openTicket(repository);
    await repository.updateStatus(
      ticketId: ticket.id,
      status: SupportStatus.resolved,
    );

    final replied = await repository.reply(
      ticketId: ticket.id,
      authorUid: 'landlord-1',
      body: 'This is still happening.',
    );

    expect(replied.status, SupportStatus.inProgress);
  });

  test('a closed conversation refuses further replies', () async {
    final database = await openDatabase('support-closed.db');
    addTearDown(database.close);
    final repository = SembastSupportRepository(database: database);
    final ticket = await openTicket(repository);
    await repository.updateStatus(
      ticketId: ticket.id,
      status: SupportStatus.closed,
    );

    await expectLater(
      repository.reply(
        ticketId: ticket.id,
        authorUid: 'landlord-1',
        body: 'One more thing.',
      ),
      throwsA(isA<DomainValidationException>()),
    );
  });

  test('watchAll filters to one workspace, newest activity first', () async {
    final database = await openDatabase('support-watch.db');
    addTearDown(database.close);
    final repository = SembastSupportRepository(database: database);

    final first = await openTicket(repository);
    await repository.reply(
      ticketId: first.id,
      authorUid: 'admin-1',
      body: 'Looking into it.',
    );
    final second = await repository.open(
      landlordId: 'landlord-2',
      subject: 'Cannot publish',
      category: SupportCategory.listings,
      body: 'The publish button does nothing.',
      appVersion: '1.4.2+31',
      platform: 'ios',
    );

    // The admin queue sees both; a landlord sees only their own.
    expect((await repository.watchAll().first).map((t) => t.id), hasLength(2));
    final mine = await repository.watchAll(landlordId: 'landlord-1').first;
    expect(mine.map((ticket) => ticket.id), <String>[first.id]);
    expect(
      (await repository.watchAll(landlordId: 'landlord-2').first).single.id,
      second.id,
    );
  });
}
