import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/localized_material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/presentation/surface.dart';
import '../application/notification_providers.dart';
import '../application/push_interactions.dart';
import '../domain/app_notification.dart';

class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationCountProvider);
    final copy = AppLocalizations.of(context)!;
    return Badge(
      isLabelVisible: unread > 0,
      label: Text(unread > 99 ? '99+' : '$unread'),
      child: IconButton(
        tooltip: unread == 0
            ? copy.notifications
            : copy.unreadNotifications(unread),
        onPressed: () => showNotificationCenter(context),
        icon: Icon(
          unread == 0
              ? Icons.notifications_none_rounded
              : Icons.notifications_rounded,
        ),
      ),
    );
  }
}

Future<void> showNotificationCenter(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _NotificationCenterSheet(),
  );
}

class _NotificationCenterSheet extends ConsumerWidget {
  const _NotificationCenterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(appNotificationsProvider);
    final copy = AppLocalizations.of(context)!;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      copy.notifications,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: copy.closeNotifications,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Text(
                copy.notificationSyncDescription,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              Expanded(
                child: notifications.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator.adaptive()),
                  error: (_, _) => _NotificationState(
                    icon: Icons.cloud_off_rounded,
                    title: copy.notificationLoadFailed,
                    message: copy.notificationLocalDataAvailable,
                  ),
                  data: (items) => items.isEmpty
                      ? _NotificationState(
                          icon: Icons.notifications_none_rounded,
                          title: copy.noNotificationsYet,
                          message: copy.newNotificationsWillAppear,
                        )
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) =>
                              _NotificationTile(notification: items[index]),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = AppLocalizations.of(context)!;
    final icon = switch (notification.kind) {
      AppNotificationKind.application => Icons.assignment_outlined,
      AppNotificationKind.enquiry => Icons.forum_outlined,
      AppNotificationKind.tenantNotice => Icons.campaign_outlined,
      AppNotificationKind.system => Icons.info_outline_rounded,
    };
    return Semantics(
      button: true,
      label: notification.isRead
          ? notification.title
          : copy.unreadTitle(notification.title),
      child: NyumbaSurface(
        padding: const EdgeInsets.all(14),
        onTap: () => _open(context, ref),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(child: Icon(icon, size: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                fontWeight: notification.isRead
                                    ? FontWeight.w500
                                    : FontWeight.w700,
                              ),
                        ),
                      ),
                      if (!notification.isRead)
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: context.nyumba.terracottaGold,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(notification.body),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        DateFormat(
                          'd MMM, HH:mm',
                          Localizations.localeOf(context).toLanguageTag(),
                        ).format(notification.createdAt.toLocal()),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (notification.syncMetadata.needsSync) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.sync_rounded, size: 14),
                        const SizedBox(width: 3),
                        Text(
                          copy.pending,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final router = GoRouter.of(context);
    try {
      if (!notification.isRead) {
        await ref.read(markNotificationReadProvider)(notification.id);
      }
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.notificationMarkReadFailed,
          ),
        ),
      );
    }
    if (!context.mounted) return;
    Navigator.pop(context);
    final route = safeNotificationRoute(notification.route);
    if (route != null) router.go(route);
  }
}

class _NotificationState extends StatelessWidget {
  const _NotificationState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 38),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
