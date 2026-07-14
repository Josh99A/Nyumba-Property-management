import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../app/theme/nyumba_colors.dart';
import '../../../core/config/market_config.dart';
import '../../../core/presentation/nyumba_logo.dart';
import '../../../core/presentation/responsive.dart';
import '../../../core/presentation/surface.dart';
import '../domain/application.dart';
import '../domain/listing.dart';
import 'listing_visuals.dart';

class ListingDetailScreen extends ConsumerWidget {
  const ListingDetailScreen({required this.listingId, super.key});

  final String listingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listings = ref.watch(publicListingsProvider);
    return Scaffold(
      backgroundColor: context.nyumba.softIvory,
      appBar: AppBar(
        toolbarHeight: 70,
        backgroundColor: context.nyumba.surface,
        leading: IconButton(
          tooltip: 'Back to available homes',
          onPressed: () => context.go('/explore'),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const NyumbaLogo(height: 39),
        actions: [
          TextButton(
            onPressed: () => context.go('/sign-in'),
            child: const Text('Sign in'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: listings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) =>
            Center(child: Text('Could not load this home: $error')),
        data: (items) {
          Listing? listing;
          for (final item in items) {
            if (item.id == listingId) listing = item;
          }
          if (listing == null) {
            return _ListingNotFound(onBack: () => context.go('/explore'));
          }
          return _ListingDetails(listing: listing);
        },
      ),
    );
  }
}

class _ListingDetails extends StatelessWidget {
  const _ListingDetails({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(
      locale: 'en_UG',
      symbol: 'UGX ',
      decimalDigits: 0,
    );
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
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
                style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Available homes'),
              ),
              const SizedBox(height: 10),
              Hero(
                tag: 'listing-image-${listing.id}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: context.isCompact ? 4 / 3 : 2.45,
                    child: Image.asset(
                      listingAssetFor(listing),
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(listing.title, style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              Icons.location_on_outlined,
              size: 20,
              color: context.nyumba.mutedInk,
            ),
            const SizedBox(width: 5),
            Text(
              listingLocationFor(listing),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
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
            const _Fact(
              icon: Icons.local_parking_outlined,
              value: 'Secure parking',
            ),
            const _Fact(icon: Icons.water_drop_outlined, value: 'Backup water'),
          ],
        ),
        const SizedBox(height: 30),
        Text('About this home', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        Text(listing.description, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 28),
        Text('What is included', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        const Wrap(
          spacing: 24,
          runSpacing: 14,
          children: [
            _Included(label: '24-hour security'),
            _Included(label: 'Reliable water supply'),
            _Included(label: 'On-site parking'),
            _Included(label: 'Professional management'),
          ],
        ),
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
          Text(
            'Interested in this home?',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Contact the landlord or submit an application.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => _showApplication(context, listing),
            icon: const Icon(Icons.description_outlined),
            label: const Text('Apply for this unit'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _showContact(context, listing),
            icon: const Icon(Icons.phone_outlined),
            label: const Text('Contact landlord'),
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
              Expanded(child: Text('Verified subscribed landlord')),
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
              Expanded(child: Text('Details available offline')),
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
          Text(value),
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
          Expanded(child: Text(label)),
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
            Text(
              'This home is no longer available',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            const Text('Browse the latest verified listings instead.'),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onBack,
              child: const Text('Browse available homes'),
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
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Contact landlord',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Ask about ${listing.title}.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            ListTile(
              contentPadding: EdgeInsets.zero,
              enabled: false,
              leading: const CircleAvatar(child: Icon(Icons.phone_outlined)),
              title: Text(listing.contactPhone ?? '+256 772 000 100'),
              subtitle: const Text(
                'Call or WhatsApp · in-app dialing coming soon',
              ),
            ),
            if (listing.contactEmail != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  child: Icon(Icons.mail_outline_rounded),
                ),
                title: Text(listing.contactEmail!),
                subtitle: const Text('Send an email'),
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
        title: const Text('Application saved'),
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
              Text(
                'Your application is safely stored on this device and queued for delivery. Nyumba will retry automatically when you are online.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Text('Apply for this unit'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.listing.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  textInputAction: TextInputAction.next,
                  validator: (value) => (value?.trim().length ?? 0) < 2
                      ? 'Enter your name'
                      : null,
                ),
                const SizedBox(height: 13),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email address'),
                  textInputAction: TextInputAction.next,
                  validator: (value) => !(value?.contains('@') ?? false)
                      ? 'Enter a valid email'
                      : null,
                ),
                const SizedBox(height: 13),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone number'),
                  textInputAction: TextInputAction.next,
                  validator: (value) =>
                      !NyumbaMarket.isValidPhone(value?.trim() ?? '')
                      ? 'Enter a valid Ugandan phone number (+256…)'
                      : null,
                ),
                const SizedBox(height: 13),
                OutlinedButton.icon(
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 730)),
                    );
                    if (date != null) setState(() => _moveIn = date);
                  },
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
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
                  decoration: const InputDecoration(
                    labelText: 'Message to landlord (optional)',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: context.nyumba.danger)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Submit application'),
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
      await ref
          .read(appDependenciesProvider)
          .applications
          .apply(
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
