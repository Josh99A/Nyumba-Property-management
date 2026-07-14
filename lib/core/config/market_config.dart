/// Nyumba launch-market configuration.
///
/// Nyumba launches in **Uganda only**. These constants are the single client
/// source for market facts (currency, phone format, payment rails, listing
/// lifetime, upload limits). Server-owned configuration remains authoritative
/// for anything money- or entitlement-related: the backend must validate every
/// value here independently, and tax computation is never performed on-device.
library;

abstract final class NyumbaMarket {
  /// ISO 3166-1 alpha-2 code of the only supported country at launch.
  static const String countryCode = 'UG';
  static const String countryName = 'Uganda';

  /// UGX has no minor unit in circulation; amounts are still stored in minor
  /// units (cents, /100) across the domain for forward compatibility.
  static const String currencyCode = 'UGX';
  static const String currencyLocale = 'en_UG';
  static const String currencySymbol = 'UGX ';

  /// Presentation/reporting timezone. Storage stays UTC server timestamps.
  static const String reportingTimezone = 'Africa/Kampala';

  /// E.164 phone format: +256 followed by 9 digits (e.g. +256 772 123 456).
  static const String phoneCountryCode = '+256';
  static final RegExp phonePattern = RegExp(r'^\+256\d{9}$');

  /// Normalizes user input (spaces/dashes, leading 0) before validation.
  static bool isValidPhone(String input) {
    var digits = input.replaceAll(RegExp(r'[\s\-()]'), '');
    if (digits.startsWith('0')) {
      digits = '$phoneCountryCode${digits.substring(1)}';
    }
    return phonePattern.hasMatch(digits);
  }

  /// Supported tenant payment rails. Provider integration and settlement are
  /// server-side; the client only renders and initiates.
  static const List<String> paymentMethods = [
    'MTN Mobile Money',
    'Airtel Money',
    'Bank transfer',
    'Cash (recorded by landlord)',
  ];

  /// Uganda VAT applies to platform subscription fees at the standard rate.
  /// The rate is documented here for display copy only — invoices and tax
  /// lines are computed and stored server-side.
  static const double vatRateDisplayOnly = 0.18;

  /// A published listing expires this many days after (re)publication.
  /// Landlords can renew; expiry is enforced by the backend projection job.
  static const int listingLifetimeDays = 30;

  /// Upload limits (mirrored in firebase/storage.rules — keep in sync).
  static const int maxListingPhotos = 10;
  static const int maxImageSizeBytes = 5 * 1024 * 1024; // 5 MB
  static const int maxDocumentSizeBytes = 10 * 1024 * 1024; // 10 MB
  static const List<String> allowedImageTypes = [
    'image/jpeg',
    'image/png',
    'image/webp',
  ];
  static const List<String> allowedDocumentTypes = [
    'application/pdf',
    'image/jpeg',
    'image/png',
  ];

  /// Retention policy (enforced server-side; documented for the client team):
  /// financial records 7 years, deleted listings/media purged after 90 days,
  /// maintenance media 2 years.
  static const int financialRetentionYears = 7;
  static const int deletedMediaPurgeDays = 90;
  static const int maintenanceMediaRetentionYears = 2;
}
