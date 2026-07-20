import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../domain/platform_account.dart';

/// Streams the platform account directory straight from the admin-readable
/// server collections (`users`, `landlordAccounts`, `subscriptions`,
/// `auditLogs` — all client-read-only by rule for platform admins).
///
/// Deliberately not mirrored into the offline database: these aggregates are
/// server-owned, every admin mutation against them is an online audited
/// command, and a stale local copy of someone's suspension state is worse
/// than an honest "needs a connection".
final class FirestoreAdminDirectory implements AdminDirectoryRepository {
  FirestoreAdminDirectory({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Beyond this the directory needs server-side search/pagination; the rules
  /// cap nothing here, so the bound is the client's own honesty about scale.
  static const directoryLimit = 500;

  @override
  Stream<List<PlatformAccount>> watchAccounts() {
    final users = _firestore
        .collection('users')
        .limit(directoryLimit)
        .snapshots();
    final landlordAccounts = _firestore
        .collection('landlordAccounts')
        .limit(directoryLimit)
        .snapshots();
    final subscriptions = _firestore
        .collection('subscriptions')
        .limit(directoryLimit)
        .snapshots();
    return _combineLatest3(users, landlordAccounts, subscriptions).map(
      (snapshot) => combineAccounts(
        users: {for (final doc in snapshot.$1.docs) doc.id: doc.data()},
        landlordAccounts: {
          for (final doc in snapshot.$2.docs) doc.id: doc.data(),
        },
        subscriptions: {for (final doc in snapshot.$3.docs) doc.id: doc.data()},
      ),
    );
  }

  @override
  Stream<List<AdminAuditEvent>> watchRecentAuditEvents({int limit = 30}) =>
      _firestore
          .collection('auditLogs')
          .orderBy('at', descending: true)
          .limit(limit)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map((doc) => _auditEvent(doc.id, doc.data()))
                .whereType<AdminAuditEvent>()
                .toList(growable: false),
          );

  /// Pure join of the three server collections into presentation-ready
  /// accounts. Kept static and free of Firestore types in its logic so the
  /// mapping rules can be tested against plain maps.
  static List<PlatformAccount> combineAccounts({
    required Map<String, Map<String, Object?>> users,
    required Map<String, Map<String, Object?>> landlordAccounts,
    required Map<String, Map<String, Object?>> subscriptions,
  }) {
    // Firebase Auth enforces one live account per email, but deleting an
    // account leaves its profile document behind and a re-registration mints
    // a new UID — so a tester who recreated their account appears once per
    // life. Among documents sharing an email only the newest can still be
    // live; the older ones are orphans by construction and are dropped.
    final newestUidByEmail = <String, String>{};
    final createdAtByUid = <String, DateTime>{};
    for (final entry in users.entries) {
      if (entry.value['isDeleted'] == true) continue;
      final email = _text(entry.value['email'])?.toLowerCase();
      if (email == null) continue;
      final createdAt =
          _date(entry.value['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      createdAtByUid[entry.key] = createdAt;
      final current = newestUidByEmail[email];
      if (current == null || createdAt.isAfter(createdAtByUid[current]!)) {
        newestUidByEmail[email] = entry.key;
      }
    }

    final result = <PlatformAccount>[];
    for (final entry in users.entries) {
      final uid = entry.key;
      final data = entry.value;
      if (data['isDeleted'] == true) continue;
      final normalizedEmail = _text(data['email'])?.toLowerCase();
      if (normalizedEmail != null && newestUidByEmail[normalizedEmail] != uid) {
        continue;
      }

      final email = _text(data['email']) ?? '';
      final displayName =
          _text(data['displayName']) ??
          (email.isNotEmpty ? email : 'Unnamed account');
      final role = _text(data['role'])?.toLowerCase();
      final landlordAccount = landlordAccounts[uid];
      final subscription = subscriptions[uid];

      // A super-admin archive lives on the users document and outranks
      // everything else; otherwise landlord standing lives on the
      // landlordAccounts aggregate, and the users document only distinguishes
      // active from suspended for everyone else.
      final status = _text(data['status']) == 'archived'
          ? PlatformAccountStatus.archived
          : landlordAccount != null
          ? switch (_text(landlordAccount['approvalStatus'])) {
              'pending' => PlatformAccountStatus.pendingApproval,
              'suspended' => PlatformAccountStatus.suspended,
              _ => PlatformAccountStatus.active,
            }
          : (_text(data['status']) == 'suspended'
                ? PlatformAccountStatus.suspended
                : PlatformAccountStatus.active);

      result.add(
        PlatformAccount(
          uid: uid,
          displayName: displayName,
          email: email,
          roleLabel: switch (role) {
            'landlord' => 'Landlord',
            'tenant' => 'Tenant',
            _ => 'Client',
          },
          status: status,
          joinedLabel: _dateLabel(data['createdAt']) ?? 'Unknown',
          userVersion: _version(data['version']),
          landlordAccountVersion: _version(landlordAccount?['version']),
          businessName: landlordAccount == null
              ? null
              : _text(landlordAccount['businessName']),
          subscriptionTier: subscription == null
              ? null
              : _text(subscription['tier']),
          subscriptionRequestedTier: subscription == null
              ? null
              : _text(subscription['requestedTier']),
          subscriptionStatus: subscription == null
              ? PlatformSubscriptionStatus.none
              : PlatformSubscriptionStatus.fromServer(
                  _text(subscription['status']),
                ),
          subscriptionVersion: _version(subscription?['version']),
        ),
      );
    }
    result.sort(
      (left, right) => left.displayName.toLowerCase().compareTo(
        right.displayName.toLowerCase(),
      ),
    );
    return result;
  }

  static AdminAuditEvent? _auditEvent(String id, Map<String, Object?> data) {
    final action = _text(data['action']);
    final actorUid = _text(data['actorUid']);
    final outcome = _text(data['outcome']);
    final at = _date(data['at']);
    if (action == null || actorUid == null || outcome == null || at == null) {
      return null;
    }
    return AdminAuditEvent(
      id: id,
      action: action,
      actorUid: actorUid,
      actorIsAdmin: data['actorIsAdmin'] == true,
      outcome: outcome,
      at: at,
      aggregateId: _text(data['aggregateId']),
      reasonCode: _text(data['reasonCode']),
    );
  }

  static String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static int? _version(Object? value) => switch (value) {
    int() => value,
    num() => value.toInt(),
    _ => int.tryParse(value?.toString() ?? ''),
  };

  static DateTime? _date(Object? value) => switch (value) {
    Timestamp() => value.toDate(),
    DateTime() => value,
    String() => DateTime.tryParse(value),
    _ => null,
  };

  static String? _dateLabel(Object? value) {
    final date = _date(value);
    return date == null
        ? null
        : DateFormat('d MMM yyyy').format(date.toLocal());
  }

  /// Emits whenever any source emits, once every source has produced its
  /// first snapshot. A directory that rendered users before landlord standing
  /// arrived would briefly show a suspended landlord as active.
  static Stream<(A, B, C)> _combineLatest3<A, B, C>(
    Stream<A> a,
    Stream<B> b,
    Stream<C> c,
  ) {
    late StreamController<(A, B, C)> controller;
    StreamSubscription<A>? subscriptionA;
    StreamSubscription<B>? subscriptionB;
    StreamSubscription<C>? subscriptionC;
    A? latestA;
    B? latestB;
    C? latestC;
    var hasA = false, hasB = false, hasC = false;

    void emit() {
      if (hasA && hasB && hasC) {
        controller.add((latestA as A, latestB as B, latestC as C));
      }
    }

    controller = StreamController<(A, B, C)>(
      onListen: () {
        subscriptionA = a.listen((value) {
          latestA = value;
          hasA = true;
          emit();
        }, onError: controller.addError);
        subscriptionB = b.listen((value) {
          latestB = value;
          hasB = true;
          emit();
        }, onError: controller.addError);
        subscriptionC = c.listen((value) {
          latestC = value;
          hasC = true;
          emit();
        }, onError: controller.addError);
      },
      onCancel: () async {
        await subscriptionA?.cancel();
        await subscriptionB?.cancel();
        await subscriptionC?.cancel();
      },
    );
    return controller.stream;
  }
}
