import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/localized_material.dart';

import 'widgets/admin_components.dart';

/// Platform reporting.
///
/// Every figure this page would show — payment volume, growth trends, district
/// footprints, generated report history — is an aggregate across every landlord
/// on the platform. Those must be derived server-side from canonical records
/// (see `docs/architecture/README.md`): a client only ever holds a partial,
/// permission-scoped mirror, so any total computed here would be wrong in a way
/// that still looks authoritative. Until that reporting job exists this page
/// says so plainly rather than rendering illustrative numbers.
class AdminReportsScreen extends StatelessWidget {
  const AdminReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      showsDemoData: false,
      title: 'Reports',
      description: 'Platform-wide payment, adoption, and service reporting.',
      children: [
        AdminPanel(
          title: 'Reporting',
          subtitle: 'Aggregated across every landlord',
          child: Column(
            children: [
              const AdminEmptyState(
                title: 'Reporting is not available yet',
                message:
                    'Platform totals have to be aggregated on the server from '
                    'canonical records. This app holds only a permission-scoped '
                    'copy of the data, so any total it calculated would be '
                    'incomplete while still looking authoritative.',
                icon: Icons.query_stats_outlined,
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 24),
                child: Text.localized(
                  'Per-landlord figures on the landlord dashboard are derived '
                  'from that landlord’s own records and are real today.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
