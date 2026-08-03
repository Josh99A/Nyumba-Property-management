import 'package:flutter/material.dart' hide Text;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nyumba_property_management/core/localization/localized_material.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../core/cloud/cloud_async.dart';
import '../../../core/localization/app_localizations_adapter.dart';
import '../../../core/localization/nyumba_localizations.dart';
import '../../../core/presentation/action_failure.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/authorization_policy.dart';
import '../../portfolio/application/rental_space_labels.dart';
import '../../portfolio/domain/unit.dart';
import '../../subscriptions/application/subscription_providers.dart';
import '../../subscriptions/domain/landlord_entitlement.dart';
import '../../subscriptions/presentation/upgrade_prompt.dart';
import '../application/marketplace_use_cases.dart';
import '../domain/listing.dart';

/// What the landlord chose when told a space has just become vacant.
enum _VacancyChoice { notNow, publish, openListings }

/// Publishes [listing], stopping at the plan's active-advert limit with an
/// upgrade prompt instead of letting the server refuse.
///
/// Shared by every surface that can put an advert live so the limit, the
/// wording of a refusal, and the confirmation cannot drift apart. Callers own
/// the photo requirement, because what to do about a photoless advert differs:
/// the listings screen opens its own editor, the vacancy prompt navigates.
///
/// Returns true only once the server has accepted the publication.
Future<bool> publishListingWithinPlan(
  BuildContext context,
  WidgetRef ref,
  Listing listing,
) async {
  // At the plan's active-listing limit, prompt for an upgrade instead of
  // sending a publication the server would reject. Only a confirmed
  // entitlement blocks locally; an unknown plan leaves the server to judge.
  if (ref.read(landlordEntitlementProvider).value case EntitlementKnown(
    entitlement: final plan,
  )) {
    final activeCount = ref
        .read(landlordListingsProvider)
        .supportingRecords
        .where((item) => item.status == ListingStatus.published)
        .length;
    if (activeCount >= plan.activeListingLimit) {
      final copy = appLocalizationsOf(context);
      await showUpgradePrompt(
        context,
        title: copy.listingLimitReachedTitle,
        message: copy.listingLimitReachedMessage(
          plan.displayName,
          plan.activeListingLimit,
        ),
      );
      return false;
    }
  }
  try {
    await ref.read(publishListingProvider)(listing.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text.localized(_publishConfirmation(context, ref, listing)),
        ),
      );
    }
    return true;
  } on Object catch (error) {
    if (context.mounted) {
      // Never the raw exception: `error.toString()` puts a class name, an
      // internal code, and sometimes a document path in front of the landlord.
      // `describeActionFailure` keeps all of that in `details`, which a
      // snackbar deliberately has no room for.
      final failure = describeActionFailure(
        error,
        action: context.tr('publish this listing'),
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text.localized(failure.message)));
    }
    return false;
  }
}

/// Answers the question the landlord actually asked — "is my advert up?" —
/// instead of describing the queue. Publishing pushes immediately, so with a
/// live link the only honest promise is "in a moment"; without one, the useful
/// thing to say is what has to happen first.
String _publishConfirmation(
  BuildContext context,
  WidgetRef ref,
  Listing listing,
) {
  final copy = appLocalizationsOf(context);
  return switch (ref.read(cloudStatusProvider).value) {
    CloudStatus.local => copy.publishSavedOnDevice,
    CloudStatus.failed ||
    CloudStatus.connecting ||
    null => copy.publishWhenBackOnline(listing.title),
    CloudStatus.live => copy.publishInProgress(listing.title),
  };
}

/// Offers publication at the moment a rental space becomes vacant.
///
/// Vacancy is the only state in which a space may be advertised, so it is also
/// the only moment the landlord can act on. Asking here saves the trip to the
/// listings screen that most landlords made anyway — and, for those who did
/// not, kept a rentable space invisible to tenants.
///
/// Does nothing when the space is already advertised, or when the account
/// cannot manage adverts at all. [listings] is the landlord's own advert list,
/// already loaded by the calling screen.
Future<void> promptToAdvertiseVacantSpace(
  BuildContext context,
  WidgetRef ref, {
  required Unit unit,
  required List<Listing> listings,
}) async {
  final session = ref.read(sessionControllerProvider);
  bool allows(CrudOperation operation) =>
      session != null &&
      AuthorizationPolicy.allowsSession(
        session,
        AppResource.privateListing,
        operation,
      );

  final unitListings = listings
      .where((listing) => listing.unitId == unit.id)
      .toList(growable: false);
  // Already on the public marketplace: there is nothing to ask.
  if (unitListings.any((listing) => listing.isPublic)) return;

  // A draft or a paused advert can go live again; a closed one cannot, and is
  // treated as though the space had no advert at all.
  Listing? advert;
  for (final listing in unitListings) {
    if (listing.status == ListingStatus.draft ||
        listing.status == ListingStatus.paused) {
      advert = listing;
      break;
    }
  }

  final canPublish = advert != null && allows(CrudOperation.update);
  final canCreate = advert == null && allows(CrudOperation.create);
  // Neither publishing nor creating is open to this account — say nothing
  // rather than offer an action that would be refused.
  if (!canPublish && !canCreate) return;

  // A photoless advert cannot be published, and the fix is in the editor, so
  // the offer becomes "add photos" rather than "publish".
  final needsPhotos = advert != null && !advert.hasPhotos;

  // Read through generated getters rather than composed literals: an
  // interpolated sentence can never match an ARB key, so the three bodies below
  // would have reached Luganda, Kiswahili, and Arabic readers in English.
  final copy = appLocalizationsOf(context);
  final choice = await showDialog<_VacancyChoice>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(copy.vacancyPromptTitle),
      content: SizedBox(
        width: 420,
        child: Text(
          advert == null
              ? copy.vacancyPromptCreateBody(unit.displayName)
              : needsPhotos
              ? copy.vacancyPromptPhotosBody(unit.displayName, advert.title)
              : copy.vacancyPromptPublishBody(unit.displayName, advert.title),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, _VacancyChoice.notNow),
          child: Text(copy.vacancyPromptNotNow),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            dialogContext,
            advert == null || needsPhotos
                ? _VacancyChoice.openListings
                : _VacancyChoice.publish,
          ),
          child: Text(
            advert == null
                ? copy.vacancyPromptCreateAction
                : needsPhotos
                ? copy.vacancyPromptPhotosAction
                : copy.vacancyPromptPublishAction,
          ),
        ),
      ],
    ),
  );

  if (!context.mounted) return;
  switch (choice) {
    case null:
    case _VacancyChoice.notNow:
      return;
    case _VacancyChoice.publish:
      await publishListingWithinPlan(context, ref, advert!);
    case _VacancyChoice.openListings:
      // With no advert yet the listings screen opens its create editor on this
      // space; with a photoless one it opens on the adverts themselves, where
      // Edit is the next tap.
      context.go(
        advert == null
            ? Uri(
                path: '/listings',
                queryParameters: <String, String>{'unitId': unit.id},
              ).toString()
            : '/listings',
      );
  }
}
