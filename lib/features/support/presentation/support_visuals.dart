import 'package:flutter/material.dart' hide Text, Tooltip;

import '../../../core/presentation/status_badge.dart';
import '../domain/support_ticket.dart';

/// Shared vocabulary for both support surfaces.
///
/// The landlord and the administrator read the *same* status through different
/// words on purpose. `awaiting_landlord` is our workflow term; a landlord needs
/// to be told "Needs you". Keeping both labels beside each other here is what
/// stops the internal phrase leaking into their screen the next time someone
/// adds a status.
String landlordStatusLabel(SupportStatus status) => switch (status) {
  SupportStatus.open => 'Sent',
  SupportStatus.inProgress => 'Nyumba is looking into this',
  SupportStatus.awaitingLandlord => 'Needs you',
  SupportStatus.resolved => 'Resolved',
  SupportStatus.closed => 'Closed',
};

String adminStatusLabel(SupportStatus status) => switch (status) {
  SupportStatus.open => 'New',
  SupportStatus.inProgress => 'In progress',
  SupportStatus.awaitingLandlord => 'Awaiting landlord',
  SupportStatus.resolved => 'Resolved',
  SupportStatus.closed => 'Closed',
};

BadgeTone supportStatusTone(SupportStatus status) => switch (status) {
  SupportStatus.open => BadgeTone.neutral,
  SupportStatus.inProgress ||
  SupportStatus.awaitingLandlord => BadgeTone.warning,
  SupportStatus.resolved => BadgeTone.success,
  SupportStatus.closed => BadgeTone.neutral,
};

String supportCategoryLabel(SupportCategory category) => switch (category) {
  SupportCategory.billing => 'Billing & subscription',
  SupportCategory.payments => 'Payments & receipts',
  SupportCategory.tenants => 'Tenants & leases',
  SupportCategory.listings => 'Listings & adverts',
  SupportCategory.account => 'Account & access',
  SupportCategory.other => 'Something else',
};

/// Short enough for a queue row, where the full label would crowd out the name.
String supportCategoryShortLabel(SupportCategory category) =>
    switch (category) {
      SupportCategory.billing => 'Billing',
      SupportCategory.payments => 'Payments',
      SupportCategory.tenants => 'Tenants',
      SupportCategory.listings => 'Listings',
      SupportCategory.account => 'Account',
      SupportCategory.other => 'Other',
    };

IconData supportCategoryIcon(SupportCategory category) => switch (category) {
  SupportCategory.billing => Icons.workspace_premium_outlined,
  SupportCategory.payments => Icons.payments_outlined,
  SupportCategory.tenants => Icons.people_outline_rounded,
  SupportCategory.listings => Icons.sell_outlined,
  SupportCategory.account => Icons.lock_outline_rounded,
  SupportCategory.other => Icons.help_outline_rounded,
};

/// Relative time, in the coarsest unit that is still true.
///
/// "3 hours ago" is what someone reads a conversation list for; a timestamp
/// makes them do the subtraction. The exact time stays on the message itself.
String supportRelativeTime(DateTime moment, DateTime now) {
  final elapsed = now.difference(moment);
  if (elapsed.inMinutes < 1) return 'Just now';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} min ago';
  if (elapsed.inHours < 24) {
    return '${elapsed.inHours} hour${elapsed.inHours == 1 ? '' : 's'} ago';
  }
  if (elapsed.inDays < 30) {
    return '${elapsed.inDays} day${elapsed.inDays == 1 ? '' : 's'} ago';
  }
  final months = elapsed.inDays ~/ 30;
  return '$months month${months == 1 ? '' : 's'} ago';
}
