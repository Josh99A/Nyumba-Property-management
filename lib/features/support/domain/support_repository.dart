import 'package:nyumba_property_management/features/support/domain/support_ticket.dart';

/// Everything the support screens do, as three writes and two reads.
///
/// Deliberately narrow: replying and moving a ticket are the same two calls for
/// a landlord and an administrator, because the server resolves the author from
/// the ticket rather than from a flag the client sets. A repository that took a
/// role would be a repository that could lie about one.
abstract interface class SupportRepository {
  Future<SupportTicket> open({
    required String landlordId,
    required String subject,
    required SupportCategory category,
    required String body,
    required String appVersion,
    required String platform,
    String? landlordName,
    String? landlordEmail,
  });

  Future<SupportTicket> reply({
    required String ticketId,
    required String authorUid,
    required String body,
  });

  /// Moves a ticket. Which transitions are legal is the server's call; this
  /// records the intent optimistically so the thread reflects it immediately.
  Future<SupportTicket> updateStatus({
    required String ticketId,
    required SupportStatus status,
    String? note,
  });

  Future<SupportTicket?> getById(String id);

  /// Newest activity first. [landlordId] filters to one workspace; the admin
  /// queue passes null and gets every ticket the administrative pull mirrored.
  Stream<List<SupportTicket>> watchAll({String? landlordId});

  Stream<SupportTicket?> watchById(String id);
}
