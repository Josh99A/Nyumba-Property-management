import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/localized_material.dart';
import 'package:nyumba_property_management/core/localization/nyumba_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_localizations_adapter.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../app/theme/nyumba_colors.dart';
import '../../../core/config/market_config.dart';
import '../../../core/presentation/async_action_button.dart';
import '../../../core/presentation/nyumba_logo.dart';
import '../../../core/presentation/responsive.dart';
import '../../../core/presentation/status_message.dart';
import '../../../core/presentation/surface.dart';
import '../../auth/application/session_controller.dart';
import '../domain/application.dart';
import '../application/marketplace_use_cases.dart';
import '../domain/listing.dart';
import '../../reviews/presentation/public_reviews_section.dart';
import 'listing_location_section.dart';
import 'listing_visuals.dart';
import 'marketplace_navigation.dart';

class ListingDetailScreen extends ConsumerWidget {
  const ListingDetailScreen({required this.listingId, super.key});

  final String listingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listings = ref.watch(publicListingsProvider);
    final session = ref.watch(sessionControllerProvider);
    final navigationAction = marketplaceNavigationAction(session);
    // An advert that has not been acknowledged yet is absent from the public
    // catalogue by design, which used to make its own landlord's "view" action
    // land on "listing not found". Their own copy is in this workspace, so the
    // page can show them exactly what tenants will get, clearly marked as not
    // live yet. Nothing leaks: this store holds only records this workspace
    // authored or was served privately, so it is empty for a visitor.
    final ownListings = ref.watch(landlordListingsProvider);
    final listing =
        _listingIn(listings.value ?? const <Listing>[]) ??
        _listingIn(ownListings.value ?? const <Listing>[]);
    return Scaffold(
      backgroundColor: context.nyumba.softIvory,
      // On a phone the enquiry card sits below a long description, so the
      // action that brought the visitor here would otherwise be several
      // screens away from the photos.
      bottomNavigationBar: context.isCompact && listing != null
          ? _MobileEnquiryBar(listing: listing)
          : null,
      appBar: AppBar(
        toolbarHeight: 70,
        backgroundColor: context.nyumba.surface,
        leading: IconButton(
          tooltip: context.tr('Back to available homes'),
          onPressed: () => context.go('/explore'),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const NyumbaLogo(height: 39),
        actions: [
          TextButton(
            onPressed: () => context.go(navigationAction.path),
            child: Text.localized(navigationAction.label),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: listings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: NyumbaStatusMessage.fromError(
                error,
                localizations: appLocalizationsOf(context),
                subject: appLocalizationsOf(context).statusSubjectThisHome,
                onRetry: () => ref.invalidate(publicListingsProvider),
              ),
            ),
          ),
        ),
        data: (items) {
          final published = _listingIn(items);
          final listing =
              published ?? _listingIn(ownListings.value ?? const <Listing>[]);
          if (listing == null) {
            return _ListingNotFound(onBack: () => context.go('/explore'));
          }
          return _ListingDetails(listing: listing, preview: published == null);
        },
      ),
    );
  }

  Listing? _listingIn(List<Listing> items) {
    for (final item in items) {
      if (item.id == listingId) return item;
    }
    return null;
  }
}

/// Rent and the primary action, pinned to the bottom of the phone layout.
class _MobileEnquiryBar extends StatelessWidget {
  const _MobileEnquiryBar({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final copy = appLocalizationsOf(context);
    final rent = NumberFormat.currency(
      locale: copy.numberLocale,
      name: NyumbaMarket.currencyCode,
      symbol: NyumbaMarket.currencySymbol,
      decimalDigits: 0,
    ).format(listing.monthlyRentMinor ~/ 100);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.nyumba.surface,
        border: BorderDirectional(
          top: BorderSide(color: context.nyumba.outline),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      copy.monthlyRentDisplay(rent),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: context.nyumba.terracottaDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      listingLocationFor(listing),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AsyncActionButton.filled(
                onPressed: () => _showApplication(context, listing),
                showBusyIndicator: false,
                child: const Text.localized('Apply'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListingDetails extends StatelessWidget {
  const _ListingDetails({required this.listing, this.preview = false});

  final Listing listing;

  /// True when the public catalogue does not hold this advert yet, so what is
  /// on screen is the landlord's own copy rather than what tenants can see.
  final bool preview;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(
      locale: 'en_UG',
      symbol: 'UGX ',
      decimalDigits: 0,
    );
    return SingleChildScrollView(
      padding: EdgeInsetsDirectional.fromSTEB(
        context.pageGutter,
        24,
        context.pageGutter,
        60,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextButton.icon(
                onPressed: () => context.go('/explore'),
                style: TextButton.styleFrom(
                  alignment: AlignmentDirectional.centerStart,
                ),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text.localized('Available homes'),
              ),
              const SizedBox(height: 10),
              if (preview) ...[
                NyumbaSurface(
                  backgroundColor: context.nyumba.navyTint,
                  borderColor: context.nyumba.navyBorder,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.visibility_outlined,
                        color: context.nyumba.midnightNavy,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text.localized(
                          'Preview — not live yet. This is how the advert will '
                          'look to tenants once the server has it.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Hero(
                tag: 'listing-image-${listing.id}',
                child: ListingPhotoCarousel(
                  listing: listing,
                  aspectRatio: context.isCompact ? 4 / 3 : 2.45,
                ),
              ),
              const SizedBox(height: 26),
              LayoutBuilder(
                builder: (context, constraints) {
                  final content = _ListingDescription(
                    listing: listing,
                    formattedRent: currency.format(
                      listing.monthlyRentMinor / 100,
                    ),
                  );
                  final actions = _ListingActions(listing: listing);
                  if (constraints.maxWidth < 860) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [content, const SizedBox(height: 22), actions],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 7, child: content),
                      const SizedBox(width: 30),
                      SizedBox(width: 350, child: actions),
                    ],
                  );
                },
              ),
              const SizedBox(height: 26),
              // Reputation sits below the listing, not beside it: it describes
              // the landlord across every property they own, while everything
              // above describes this one home.
              PublicReviewsSection(
                landlordToken: listing.publicContactToken ?? '',
                ratingAverage: listing.ratingAverage,
                ratingCount: listing.ratingCount,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListingDescription extends StatelessWidget {
  const _ListingDescription({
    required this.listing,
    required this.formattedRent,
  });

  final Listing listing;
  final String formattedRent;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(
      locale: 'en_UG',
      symbol: '${listing.currency} ',
      decimalDigits: 0,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.localized(
          listing.title,
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              Icons.location_on_outlined,
              size: 20,
              color: context.nyumba.mutedInk,
            ),
            const SizedBox(width: 5),
            Text.localized(
              listingLocationFor(listing),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text.localized(
          '$formattedRent / month',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: context.nyumba.midnightNavy,
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (listing.bedrooms != null)
              _Fact(
                icon: Icons.bed_outlined,
                value:
                    '${listing.bedrooms} bedroom${listing.bedrooms == 1 ? '' : 's'}',
              ),
            if (listing.bathrooms != null)
              _Fact(
                icon: Icons.bathtub_outlined,
                value:
                    '${listing.bathrooms} bathroom${listing.bathrooms == 1 ? '' : 's'}',
              ),
            if (listing.unitType != null)
              _Fact(
                icon: Icons.apartment_outlined,
                value: listingUnitTypeLabel(listing.unitType!),
              ),
            if (listing.floorAreaSquareMetres != null)
              _Fact(
                icon: Icons.square_foot_outlined,
                value: '${listing.floorAreaSquareMetres} m²',
              ),
            _Fact(
              icon: Icons.chair_outlined,
              value: listing.furnished ? 'Furnished' : 'Unfurnished',
            ),
            if (listing.parkingSpaces != null)
              _Fact(
                icon: Icons.local_parking_outlined,
                value:
                    '${listing.parkingSpaces} parking space${listing.parkingSpaces == 1 ? '' : 's'}',
              ),
            if (listing.availableFrom != null)
              _Fact(
                icon: Icons.event_available_outlined,
                value:
                    'Available ${DateFormat('d MMM y').format(listing.availableFrom!)}',
              ),
          ],
        ),
        const SizedBox(height: 30),
        Text.localized(
          'About this home',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        Text.localized(
          listing.description,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 28),
        if (listing.amenities.isNotEmpty) ...[
          Text.localized(
            'Amenities',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 14,
            children: [
              for (final amenity in listing.amenities)
                _Included(label: amenity),
            ],
          ),
          const SizedBox(height: 28),
        ],
        if (listing.utilitiesIncluded.isNotEmpty) ...[
          Text.localized(
            'Utilities included',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 14,
            children: [
              for (final utility in listing.utilitiesIncluded)
                _Included(label: utility),
            ],
          ),
          const SizedBox(height: 28),
        ],
        if (listing.accessibilityFeatures.isNotEmpty) ...[
          Text.localized(
            'Accessibility',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 14,
            children: [
              for (final feature in listing.accessibilityFeatures)
                _Included(label: feature),
            ],
          ),
          const SizedBox(height: 28),
        ],
        // Placed after the photos, price, and amenities have done their job,
        // and before the money table where readers stall. It renders nothing
        // when the advert has no pin.
        if (listing.approximateLatitude != null &&
            listing.approximateLongitude != null) ...[
          ListingLocationSection(listing: listing),
          const SizedBox(height: 28),
        ],
        Text.localized(
          'Costs and terms',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        _DetailRow(label: 'Monthly rent', value: formattedRent),
        if (listing.securityDepositMinor != null)
          _DetailRow(
            label: 'Security deposit',
            value: money.format(listing.securityDepositMinor! / 100),
          ),
        if (listing.serviceChargeMinor != null)
          _DetailRow(
            label: 'Monthly service charge',
            value: money.format(listing.serviceChargeMinor! / 100),
          ),
        if (listing.minimumLeaseMonths != null)
          _DetailRow(
            label: 'Minimum lease',
            value: '${listing.minimumLeaseMonths} months',
          ),
        if (listing.petsPolicy?.trim().isNotEmpty ?? false)
          _DetailRow(label: 'Pets', value: listing.petsPolicy!),
        if (listing.smokingPolicy?.trim().isNotEmpty ?? false)
          _DetailRow(label: 'Smoking', value: listing.smokingPolicy!),
        if (listing.viewingInstructions?.trim().isNotEmpty ?? false) ...[
          const SizedBox(height: 22),
          Text.localized(
            'Viewing',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text.localized(listing.viewingInstructions!),
        ],
        if (listing.expiresAt != null) ...[
          const SizedBox(height: 22),
          Text.localized(
            'Listing active until ${DateFormat('d MMM y').format(listing.expiresAt!)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _ListingActions extends StatelessWidget {
  const _ListingActions({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    return NyumbaSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.localized(
            'Interested in this home?',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text.localized(
            'Contact the landlord or submit an application.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          AsyncActionButton.filled(
            onPressed: () => _showApplication(context, listing),
            showBusyIndicator: false,
            icon: const Icon(Icons.description_outlined),
            child: Text.localized(
              'Apply for this ${listing.unitType == null ? 'rental space' : listingUnitTypeLabel(listing.unitType!).toLowerCase()}',
            ),
          ),
          const SizedBox(height: 10),
          AsyncActionButton.outlined(
            onPressed: () => _showContact(context, listing),
            showBusyIndicator: false,
            icon: const Icon(Icons.phone_outlined),
            child: const Text.localized('Contact landlord'),
          ),
          const SizedBox(height: 18),
          const Divider(),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(
                Icons.verified_user_outlined,
                color: context.nyumba.sageDark,
                size: 20,
              ),
              SizedBox(width: 9),
              Expanded(child: Text.localized('Verified subscribed landlord')),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.offline_pin_outlined,
                color: context.nyumba.sageDark,
                size: 20,
              ),
              SizedBox(width: 9),
              Expanded(child: Text.localized('Details available offline')),
            ],
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: context.nyumba.surface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: context.nyumba.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 19, color: context.nyumba.midnightNavy),
          const SizedBox(width: 7),
          Text.localized(value),
        ],
      ),
    );
  }
}

class _Included extends StatelessWidget {
  const _Included({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Row(
        children: [
          Icon(
            Icons.check_circle_rounded,
            color: context.nyumba.sageDark,
            size: 19,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text.localized(label)),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text.localized(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: context.nyumba.mutedInk),
            ),
          ),
          Expanded(child: Text.localized(value)),
        ],
      ),
    );
  }
}

class _ListingNotFound extends StatelessWidget {
  const _ListingNotFound({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.home_work_outlined,
              size: 54,
              color: context.nyumba.mutedInk,
            ),
            const SizedBox(height: 16),
            Text.localized(
              'This home is no longer available',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            const Text.localized(
              'Browse the latest verified listings instead.',
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onBack,
              child: const Text.localized('Browse available homes'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showContact(BuildContext context, Listing listing) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text.localized(
              'Contact landlord',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text.localized(
              'Ask about ${listing.title}. Nyumba routes enquiries without exposing private landlord contact details.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Icon(Icons.shield_outlined)),
              title: Text.localized('Private, routed contact'),
              subtitle: Text.localized(
                'Use the application form to send your details securely. Direct contact is not part of the public listing.',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _showApplication(BuildContext context, Listing listing) async {
  await showDialog<void>(
    context: context,
    builder: (context) => _ApplicationDialog(listing: listing),
  );
}

class _ApplicationDialog extends ConsumerStatefulWidget {
  const _ApplicationDialog({required this.listing});

  final Listing listing;

  @override
  ConsumerState<_ApplicationDialog> createState() => _ApplicationDialogState();
}

class _ApplicationDialogState extends ConsumerState<_ApplicationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _message = TextEditingController();
  DateTime? _moveIn;
  bool _submitting = false;
  bool _submitted = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) {
      return AlertDialog(
        title: const Text.localized('Application saved'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: context.nyumba.sageTint,
                child: Icon(
                  Icons.check_rounded,
                  color: context.nyumba.sageDark,
                  size: 32,
                ),
              ),
              SizedBox(height: 18),
              Text.localized(
                'Your application is safely stored on this device and queued for delivery. Nyumba will retry automatically when you are online.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text.localized('Done'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: Text.localized(
        'Apply for this ${widget.listing.unitType == null ? 'rental space' : listingUnitTypeLabel(widget.listing.unitType!).toLowerCase()}',
      ),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text.localized(
                  widget.listing.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _name,
                  decoration: InputDecoration(
                    labelText: context.tr('Full name'),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (value) => (value?.trim().length ?? 0) < 2
                      ? 'Enter your name'
                      : null,
                ),
                const SizedBox(height: 13),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: context.tr('Email address'),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (value) => !(value?.contains('@') ?? false)
                      ? 'Enter a valid email'
                      : null,
                ),
                const SizedBox(height: 13),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: context.tr('Phone number'),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (value) =>
                      !NyumbaMarket.isValidPhone(value?.trim() ?? '')
                      ? 'Enter a valid Ugandan phone number (+256…)'
                      : null,
                ),
                const SizedBox(height: 13),
                AsyncActionButton.outlined(
                  showBusyIndicator: false,
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 730)),
                    );
                    if (date != null) setState(() => _moveIn = date);
                  },
                  icon: const Icon(Icons.event_outlined),
                  child: Text.localized(
                    _moveIn == null
                        ? 'Choose desired move-in date'
                        : 'Move in ${DateFormat('d MMMM y').format(_moveIn!)}',
                  ),
                ),
                const SizedBox(height: 13),
                TextFormField(
                  controller: _message,
                  minLines: 3,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: context.tr('Message to landlord (optional)'),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text.localized(
                    _error!,
                    style: TextStyle(color: context.nyumba.danger),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text.localized('Cancel'),
        ),
        AsyncActionButton.filled(
          onPressed: _submit,
          busy: _submitting,
          child: const Text.localized('Submit application'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(submitRentalApplicationProvider)(
        ApplyForUnitInput(
          listingId: widget.listing.id,
          applicantId: 'anonymous-${_email.text.trim().toLowerCase()}',
          applicantName: _name.text.trim(),
          applicantEmail: _email.text.trim(),
          applicantPhone: _phone.text.trim(),
          message: _message.text.trim(),
          desiredMoveIn: _moveIn,
        ),
      );
      if (mounted) setState(() => _submitted = true);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
