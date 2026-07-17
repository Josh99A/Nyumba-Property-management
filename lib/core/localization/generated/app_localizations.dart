import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';
import 'app_localizations_lg.dart';
import 'app_localizations_sw.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('lg'),
    Locale('sw'),
    Locale('ar'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Nyumba Property Management'**
  String get appTitle;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @chooseLanguage.
  ///
  /// In en, this message translates to:
  /// **'Choose language'**
  String get chooseLanguage;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @luganda.
  ///
  /// In en, this message translates to:
  /// **'Luganda'**
  String get luganda;

  /// No description provided for @kiswahili.
  ///
  /// In en, this message translates to:
  /// **'Kiswahili'**
  String get kiswahili;

  /// No description provided for @arabic.
  ///
  /// In en, this message translates to:
  /// **'Arabic'**
  String get arabic;

  /// No description provided for @languageApplied.
  ///
  /// In en, this message translates to:
  /// **'Language applied and saved on this device.'**
  String get languageApplied;

  /// No description provided for @languageSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Language changed for this session, but it could not be saved.'**
  String get languageSaveFailed;

  /// No description provided for @welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get welcomeBack;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAccount;

  /// No description provided for @emailAddress.
  ///
  /// In en, this message translates to:
  /// **'Email address'**
  String get emailAddress;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPassword;

  /// No description provided for @continueLabel.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @viewAll.
  ///
  /// In en, this message translates to:
  /// **'View all'**
  String get viewAll;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get saveChanges;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get saving;

  /// No description provided for @saveDraft.
  ///
  /// In en, this message translates to:
  /// **'Save draft'**
  String get saveDraft;

  /// No description provided for @publish.
  ///
  /// In en, this message translates to:
  /// **'Publish'**
  String get publish;

  /// No description provided for @unpublishListing.
  ///
  /// In en, this message translates to:
  /// **'Unpublish listing'**
  String get unpublishListing;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @filter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filter;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @date.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get date;

  /// No description provided for @amount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amount;

  /// No description provided for @reference.
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get reference;

  /// No description provided for @details.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get details;

  /// No description provided for @role.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get role;

  /// No description provided for @selected.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get selected;

  /// No description provided for @profileSettings.
  ///
  /// In en, this message translates to:
  /// **'Profile settings'**
  String get profileSettings;

  /// No description provided for @profileDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage your personal details, appearance, language, and notifications.'**
  String get profileDescription;

  /// No description provided for @personalDetails.
  ///
  /// In en, this message translates to:
  /// **'Personal details'**
  String get personalDetails;

  /// No description provided for @personalDetailsDescription.
  ///
  /// In en, this message translates to:
  /// **'These details identify you across your Nyumba workspace.'**
  String get personalDetailsDescription;

  /// No description provided for @fullName.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get fullName;

  /// No description provided for @phoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get phoneNumber;

  /// No description provided for @accountRole.
  ///
  /// In en, this message translates to:
  /// **'Account role'**
  String get accountRole;

  /// No description provided for @rolesManagedByAdmin.
  ///
  /// In en, this message translates to:
  /// **'Roles are managed by an administrator.'**
  String get rolesManagedByAdmin;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @appearanceDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose how Nyumba looks on this device.'**
  String get appearanceDescription;

  /// No description provided for @system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get system;

  /// No description provided for @light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// No description provided for @dark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get dark;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @notificationsDescription.
  ///
  /// In en, this message translates to:
  /// **'Select the updates you want to receive.'**
  String get notificationsDescription;

  /// No description provided for @emailNotifications.
  ///
  /// In en, this message translates to:
  /// **'Email notifications'**
  String get emailNotifications;

  /// No description provided for @emailNotificationsDescription.
  ///
  /// In en, this message translates to:
  /// **'Receive important account updates by email.'**
  String get emailNotificationsDescription;

  /// No description provided for @pushNotifications.
  ///
  /// In en, this message translates to:
  /// **'Push notifications'**
  String get pushNotifications;

  /// No description provided for @pushNotificationsDescription.
  ///
  /// In en, this message translates to:
  /// **'Allow alerts on this device.'**
  String get pushNotificationsDescription;

  /// No description provided for @rentReminders.
  ///
  /// In en, this message translates to:
  /// **'Rent reminders'**
  String get rentReminders;

  /// No description provided for @rentRemindersDescription.
  ///
  /// In en, this message translates to:
  /// **'Upcoming and overdue rent notices.'**
  String get rentRemindersDescription;

  /// No description provided for @maintenanceUpdates.
  ///
  /// In en, this message translates to:
  /// **'Maintenance updates'**
  String get maintenanceUpdates;

  /// No description provided for @maintenanceUpdatesDescription.
  ///
  /// In en, this message translates to:
  /// **'Status changes and new comments.'**
  String get maintenanceUpdatesDescription;

  /// No description provided for @settingsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Saved settings could not be loaded on this device.'**
  String get settingsLoadFailed;

  /// No description provided for @settingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Settings saved on this device and queued for confirmation.'**
  String get settingsSaved;

  /// No description provided for @settingsSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Settings could not be saved. Your edits are intact.'**
  String get settingsSaveFailed;

  /// No description provided for @enterFullName.
  ///
  /// In en, this message translates to:
  /// **'Enter your full name.'**
  String get enterFullName;

  /// No description provided for @enterValidEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address.'**
  String get enterValidEmail;

  /// No description provided for @enterValidUgandaPhone.
  ///
  /// In en, this message translates to:
  /// **'Use a valid Uganda phone number.'**
  String get enterValidUgandaPhone;

  /// No description provided for @dashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get dashboard;

  /// No description provided for @properties.
  ///
  /// In en, this message translates to:
  /// **'Properties'**
  String get properties;

  /// No description provided for @property.
  ///
  /// In en, this message translates to:
  /// **'Property'**
  String get property;

  /// No description provided for @rentalSpaces.
  ///
  /// In en, this message translates to:
  /// **'Rental spaces'**
  String get rentalSpaces;

  /// No description provided for @rentalSpace.
  ///
  /// In en, this message translates to:
  /// **'Rental space'**
  String get rentalSpace;

  /// No description provided for @tenants.
  ///
  /// In en, this message translates to:
  /// **'Tenants'**
  String get tenants;

  /// No description provided for @tenant.
  ///
  /// In en, this message translates to:
  /// **'Tenant'**
  String get tenant;

  /// No description provided for @payments.
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get payments;

  /// No description provided for @documents.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get documents;

  /// No description provided for @maintenance.
  ///
  /// In en, this message translates to:
  /// **'Maintenance'**
  String get maintenance;

  /// No description provided for @workOrders.
  ///
  /// In en, this message translates to:
  /// **'Work orders'**
  String get workOrders;

  /// No description provided for @notices.
  ///
  /// In en, this message translates to:
  /// **'Notices'**
  String get notices;

  /// No description provided for @advertise.
  ///
  /// In en, this message translates to:
  /// **'Advertise'**
  String get advertise;

  /// No description provided for @subscriptions.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions'**
  String get subscriptions;

  /// No description provided for @users.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get users;

  /// No description provided for @reports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get reports;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @availableHomes.
  ///
  /// In en, this message translates to:
  /// **'Available homes'**
  String get availableHomes;

  /// No description provided for @browseAvailableHomes.
  ///
  /// In en, this message translates to:
  /// **'Browse available homes'**
  String get browseAvailableHomes;

  /// No description provided for @browseVerifiedHomes.
  ///
  /// In en, this message translates to:
  /// **'Browse verified available rental spaces and contact landlords directly.'**
  String get browseVerifiedHomes;

  /// No description provided for @contactLandlord.
  ///
  /// In en, this message translates to:
  /// **'Contact landlord'**
  String get contactLandlord;

  /// No description provided for @submitApplication.
  ///
  /// In en, this message translates to:
  /// **'Submit application'**
  String get submitApplication;

  /// No description provided for @applicationSaved.
  ///
  /// In en, this message translates to:
  /// **'Application saved'**
  String get applicationSaved;

  /// No description provided for @listingDetails.
  ///
  /// In en, this message translates to:
  /// **'Listing details'**
  String get listingDetails;

  /// No description provided for @location.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get location;

  /// No description provided for @amenities.
  ///
  /// In en, this message translates to:
  /// **'Amenities'**
  String get amenities;

  /// No description provided for @accessibility.
  ///
  /// In en, this message translates to:
  /// **'Accessibility'**
  String get accessibility;

  /// No description provided for @costsAndTerms.
  ///
  /// In en, this message translates to:
  /// **'Costs and terms'**
  String get costsAndTerms;

  /// No description provided for @utilitiesIncluded.
  ///
  /// In en, this message translates to:
  /// **'Utilities included'**
  String get utilitiesIncluded;

  /// No description provided for @furnished.
  ///
  /// In en, this message translates to:
  /// **'Furnished'**
  String get furnished;

  /// No description provided for @viewing.
  ///
  /// In en, this message translates to:
  /// **'Viewing'**
  String get viewing;

  /// No description provided for @anyPrice.
  ///
  /// In en, this message translates to:
  /// **'Any price'**
  String get anyPrice;

  /// No description provided for @newestFirst.
  ///
  /// In en, this message translates to:
  /// **'Newest first'**
  String get newestFirst;

  /// No description provided for @clearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get clearFilters;

  /// No description provided for @noHomesMatch.
  ///
  /// In en, this message translates to:
  /// **'No homes match those filters'**
  String get noHomesMatch;

  /// No description provided for @tryBroaderSearch.
  ///
  /// In en, this message translates to:
  /// **'Try a broader search or a different price range.'**
  String get tryBroaderSearch;

  /// No description provided for @offlineFiles.
  ///
  /// In en, this message translates to:
  /// **'Offline files'**
  String get offlineFiles;

  /// No description provided for @syncStatus.
  ///
  /// In en, this message translates to:
  /// **'Sync status'**
  String get syncStatus;

  /// No description provided for @pending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pending;

  /// No description provided for @synced.
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get synced;

  /// No description provided for @offline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get offline;

  /// No description provided for @connecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get connecting;

  /// No description provided for @live.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get live;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @createListing.
  ///
  /// In en, this message translates to:
  /// **'Create listing'**
  String get createListing;

  /// No description provided for @addProperty.
  ///
  /// In en, this message translates to:
  /// **'Add property'**
  String get addProperty;

  /// No description provided for @addRentalSpace.
  ///
  /// In en, this message translates to:
  /// **'Add rental space'**
  String get addRentalSpace;

  /// No description provided for @addTenant.
  ///
  /// In en, this message translates to:
  /// **'Add tenant'**
  String get addTenant;

  /// No description provided for @recordPayment.
  ///
  /// In en, this message translates to:
  /// **'Record payment'**
  String get recordPayment;

  /// No description provided for @createMaintenanceRequest.
  ///
  /// In en, this message translates to:
  /// **'Create maintenance request'**
  String get createMaintenanceRequest;

  /// No description provided for @newMaintenanceRequest.
  ///
  /// In en, this message translates to:
  /// **'New maintenance request'**
  String get newMaintenanceRequest;

  /// No description provided for @priority.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get priority;

  /// No description provided for @category.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get category;

  /// No description provided for @normal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get normal;

  /// No description provided for @high.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get high;

  /// No description provided for @urgent.
  ///
  /// In en, this message translates to:
  /// **'Urgent'**
  String get urgent;

  /// No description provided for @requestTimeline.
  ///
  /// In en, this message translates to:
  /// **'Request timeline'**
  String get requestTimeline;

  /// No description provided for @paymentHistory.
  ///
  /// In en, this message translates to:
  /// **'Payment history'**
  String get paymentHistory;

  /// No description provided for @receipt.
  ///
  /// In en, this message translates to:
  /// **'Receipt'**
  String get receipt;

  /// No description provided for @rentInvoice.
  ///
  /// In en, this message translates to:
  /// **'Rent invoice'**
  String get rentInvoice;

  /// No description provided for @leaseAgreement.
  ///
  /// In en, this message translates to:
  /// **'Lease agreement'**
  String get leaseAgreement;

  /// No description provided for @downloadShare.
  ///
  /// In en, this message translates to:
  /// **'Download / share'**
  String get downloadShare;

  /// No description provided for @print.
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get print;

  /// No description provided for @openDocument.
  ///
  /// In en, this message translates to:
  /// **'Open document'**
  String get openDocument;

  /// No description provided for @subscription.
  ///
  /// In en, this message translates to:
  /// **'Subscription'**
  String get subscription;

  /// No description provided for @choosePlan.
  ///
  /// In en, this message translates to:
  /// **'Choose plan'**
  String get choosePlan;

  /// No description provided for @confirmPayment.
  ///
  /// In en, this message translates to:
  /// **'Confirm payment'**
  String get confirmPayment;

  /// No description provided for @approveLandlord.
  ///
  /// In en, this message translates to:
  /// **'Approve landlord'**
  String get approveLandlord;

  /// No description provided for @suspendAccess.
  ///
  /// In en, this message translates to:
  /// **'Suspend access'**
  String get suspendAccess;

  /// No description provided for @restoreAccess.
  ///
  /// In en, this message translates to:
  /// **'Restore access'**
  String get restoreAccess;

  /// No description provided for @archivedStatus.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get archivedStatus;

  /// No description provided for @archivedMetricCaption.
  ///
  /// In en, this message translates to:
  /// **'Awaiting restore or permanent deletion'**
  String get archivedMetricCaption;

  /// No description provided for @archiveUser.
  ///
  /// In en, this message translates to:
  /// **'Archive user'**
  String get archiveUser;

  /// No description provided for @restoreFromArchive.
  ///
  /// In en, this message translates to:
  /// **'Restore from archive'**
  String get restoreFromArchive;

  /// No description provided for @deletePermanently.
  ///
  /// In en, this message translates to:
  /// **'Delete permanently'**
  String get deletePermanently;

  /// No description provided for @archiveUserQuestion.
  ///
  /// In en, this message translates to:
  /// **'Archive this user?'**
  String get archiveUserQuestion;

  /// No description provided for @restoreArchivedUserQuestion.
  ///
  /// In en, this message translates to:
  /// **'Restore this user from the archive?'**
  String get restoreArchivedUserQuestion;

  /// No description provided for @deleteUserQuestion.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete this user?'**
  String get deleteUserQuestion;

  /// No description provided for @restoreUser.
  ///
  /// In en, this message translates to:
  /// **'Restore user'**
  String get restoreUser;

  /// No description provided for @reasonUserRequested.
  ///
  /// In en, this message translates to:
  /// **'Requested by the user'**
  String get reasonUserRequested;

  /// No description provided for @changeRole.
  ///
  /// In en, this message translates to:
  /// **'Change role'**
  String get changeRole;

  /// No description provided for @changeRoleQuestion.
  ///
  /// In en, this message translates to:
  /// **'Change this user\'s role?'**
  String get changeRoleQuestion;

  /// No description provided for @newRole.
  ///
  /// In en, this message translates to:
  /// **'New role'**
  String get newRole;

  /// No description provided for @activityHistory.
  ///
  /// In en, this message translates to:
  /// **'Activity history'**
  String get activityHistory;

  /// No description provided for @noUnreadNotifications.
  ///
  /// In en, this message translates to:
  /// **'No unread notifications'**
  String get noUnreadNotifications;

  /// No description provided for @noDataYet.
  ///
  /// In en, this message translates to:
  /// **'No data yet.'**
  String get noDataYet;

  /// No description provided for @couldNotOpenPage.
  ///
  /// In en, this message translates to:
  /// **'We could not open this page'**
  String get couldNotOpenPage;

  /// No description provided for @legacy_dd84ce5b3c8c.
  ///
  /// In en, this message translates to:
  /// **'+256 772 123 456'**
  String get legacy_dd84ce5b3c8c;

  /// No description provided for @legacy_836220fbdff5.
  ///
  /// In en, this message translates to:
  /// **'A secure property with varied rental spaces close to local amenities.'**
  String get legacy_836220fbdff5;

  /// No description provided for @legacy_8140937ee325.
  ///
  /// In en, this message translates to:
  /// **'About this home'**
  String get legacy_8140937ee325;

  /// No description provided for @legacy_e432b071bdbb.
  ///
  /// In en, this message translates to:
  /// **'Above UGX 1.4M'**
  String get legacy_e432b071bdbb;

  /// No description provided for @legacy_496c064365cc.
  ///
  /// In en, this message translates to:
  /// **'Access & operations'**
  String get legacy_496c064365cc;

  /// No description provided for @legacy_d41593be9f3f.
  ///
  /// In en, this message translates to:
  /// **'Accessibility features'**
  String get legacy_d41593be9f3f;

  /// No description provided for @legacy_9eb9d46a6790.
  ///
  /// In en, this message translates to:
  /// **'Account actions'**
  String get legacy_9eb9d46a6790;

  /// No description provided for @legacy_17be95e1a188.
  ///
  /// In en, this message translates to:
  /// **'Account details'**
  String get legacy_17be95e1a188;

  /// No description provided for @legacy_d7dbd54072e4.
  ///
  /// In en, this message translates to:
  /// **'Account directory is unavailable'**
  String get legacy_d7dbd54072e4;

  /// No description provided for @legacy_7fb5995bca43.
  ///
  /// In en, this message translates to:
  /// **'Account menu'**
  String get legacy_7fb5995bca43;

  /// No description provided for @legacy_adf69e75cc7d.
  ///
  /// In en, this message translates to:
  /// **'Action required'**
  String get legacy_adf69e75cc7d;

  /// No description provided for @legacy_f3715ab16636.
  ///
  /// In en, this message translates to:
  /// **'Activation requires a verified payment reference and is recorded'**
  String get legacy_f3715ab16636;

  /// No description provided for @legacy_df0a5aac1933.
  ///
  /// In en, this message translates to:
  /// **'Active subscriptions'**
  String get legacy_df0a5aac1933;

  /// No description provided for @legacy_59a5c54d5f44.
  ///
  /// In en, this message translates to:
  /// **'Active subscriptions by tier'**
  String get legacy_59a5c54d5f44;

  /// No description provided for @legacy_bbdb3cafea65.
  ///
  /// In en, this message translates to:
  /// **'Active tenants'**
  String get legacy_bbdb3cafea65;

  /// No description provided for @legacy_35aa97b5d006.
  ///
  /// In en, this message translates to:
  /// **'Activity feed needs a live admin session'**
  String get legacy_35aa97b5d006;

  /// No description provided for @legacy_409c81e0b451.
  ///
  /// In en, this message translates to:
  /// **'Add 1–5 photos. The primary photo appears first.'**
  String get legacy_409c81e0b451;

  /// No description provided for @legacy_19271cc17a6a.
  ///
  /// In en, this message translates to:
  /// **'Add a property and rental space before logging a request.'**
  String get legacy_19271cc17a6a;

  /// No description provided for @legacy_65da21f513a4.
  ///
  /// In en, this message translates to:
  /// **'Add a tenancy before creating a tenant document.'**
  String get legacy_65da21f513a4;

  /// No description provided for @legacy_c1ad18af83ca.
  ///
  /// In en, this message translates to:
  /// **'Add a tenant before recording a payment.'**
  String get legacy_c1ad18af83ca;

  /// No description provided for @legacy_8f2944b489cd.
  ///
  /// In en, this message translates to:
  /// **'Add a vacant rental space before creating a listing.'**
  String get legacy_8f2944b489cd;

  /// No description provided for @legacy_7b0a3d74494a.
  ///
  /// In en, this message translates to:
  /// **'Add photos'**
  String get legacy_7b0a3d74494a;

  /// No description provided for @legacy_76a62e2add71.
  ///
  /// In en, this message translates to:
  /// **'Add to demo directory'**
  String get legacy_76a62e2add71;

  /// No description provided for @legacy_ad821ad7776a.
  ///
  /// In en, this message translates to:
  /// **'Admin accounts'**
  String get legacy_ad821ad7776a;

  /// No description provided for @legacy_bfd25bae866f.
  ///
  /// In en, this message translates to:
  /// **'Admin overview'**
  String get legacy_bfd25bae866f;

  /// No description provided for @legacy_c7f971aaa56c.
  ///
  /// In en, this message translates to:
  /// **'Advertise vacant rental spaces and review incoming applications.'**
  String get legacy_c7f971aaa56c;

  /// No description provided for @legacy_c90380ba8212.
  ///
  /// In en, this message translates to:
  /// **'Advertising enabled · Pro plan'**
  String get legacy_c90380ba8212;

  /// No description provided for @legacy_80325413f717.
  ///
  /// In en, this message translates to:
  /// **'After setup, choose a subscription. The landlord'**
  String get legacy_80325413f717;

  /// No description provided for @legacy_3a005cda58b5.
  ///
  /// In en, this message translates to:
  /// **'Aggregated across every landlord'**
  String get legacy_3a005cda58b5;

  /// No description provided for @legacy_91c395c3c9e0.
  ///
  /// In en, this message translates to:
  /// **'Airtel Money'**
  String get legacy_91c395c3c9e0;

  /// No description provided for @legacy_f4f6813aa30f.
  ///
  /// In en, this message translates to:
  /// **'All accounts'**
  String get legacy_f4f6813aa30f;

  /// No description provided for @legacy_53d8bdbb9179.
  ///
  /// In en, this message translates to:
  /// **'All tenants'**
  String get legacy_53d8bdbb9179;

  /// No description provided for @legacy_51b946e53b02.
  ///
  /// In en, this message translates to:
  /// **'Allow access while I am away'**
  String get legacy_51b946e53b02;

  /// No description provided for @legacy_0f5b1d1f5fc8.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? Sign in'**
  String get legacy_0f5b1d1f5fc8;

  /// No description provided for @legacy_391637f961c6.
  ///
  /// In en, this message translates to:
  /// **'Amount payable'**
  String get legacy_391637f961c6;

  /// No description provided for @legacy_af57182af6cc.
  ///
  /// In en, this message translates to:
  /// **'Apartment A1'**
  String get legacy_af57182af6cc;

  /// No description provided for @legacy_1eecee53eeeb.
  ///
  /// In en, this message translates to:
  /// **'Appearance could not be saved. Please try again.'**
  String get legacy_1eecee53eeeb;

  /// No description provided for @legacy_4ad9787575c1.
  ///
  /// In en, this message translates to:
  /// **'Applications awaiting a decision'**
  String get legacy_4ad9787575c1;

  /// No description provided for @legacy_5afdb4123634.
  ///
  /// In en, this message translates to:
  /// **'Approvals need a live admin session'**
  String get legacy_5afdb4123634;

  /// No description provided for @legacy_7e69169c53b0.
  ///
  /// In en, this message translates to:
  /// **'Approve this landlord?'**
  String get legacy_7e69169c53b0;

  /// No description provided for @legacy_0e45076864a6.
  ///
  /// In en, this message translates to:
  /// **'Approx. latitude (optional)'**
  String get legacy_0e45076864a6;

  /// No description provided for @legacy_6f3f9072548b.
  ///
  /// In en, this message translates to:
  /// **'Approx. longitude (optional)'**
  String get legacy_6f3f9072548b;

  /// No description provided for @legacy_deae4e88374f.
  ///
  /// In en, this message translates to:
  /// **'Archive property'**
  String get legacy_deae4e88374f;

  /// No description provided for @legacy_532c5ad6fd0b.
  ///
  /// In en, this message translates to:
  /// **'Archive rental space'**
  String get legacy_532c5ad6fd0b;

  /// No description provided for @legacy_be7f19fc7e71.
  ///
  /// In en, this message translates to:
  /// **'Archive rental spaces first'**
  String get legacy_be7f19fc7e71;

  /// No description provided for @legacy_dd2a5ea1d87c.
  ///
  /// In en, this message translates to:
  /// **'Assign contractor'**
  String get legacy_dd2a5ea1d87c;

  /// No description provided for @legacy_569ef18ca840.
  ///
  /// In en, this message translates to:
  /// **'Audit logs'**
  String get legacy_569ef18ca840;

  /// No description provided for @legacy_30d6c7e26614.
  ///
  /// In en, this message translates to:
  /// **'Available offline'**
  String get legacy_30d6c7e26614;

  /// No description provided for @legacy_7c2788959f35.
  ///
  /// In en, this message translates to:
  /// **'Awaiting payment'**
  String get legacy_7c2788959f35;

  /// No description provided for @legacy_bcda28449091.
  ///
  /// In en, this message translates to:
  /// **'Awaiting payment confirmation'**
  String get legacy_bcda28449091;

  /// No description provided for @legacy_7ac2866d5b9e.
  ///
  /// In en, this message translates to:
  /// **'Awaiting receipt'**
  String get legacy_7ac2866d5b9e;

  /// No description provided for @legacy_bb8750bbb386.
  ///
  /// In en, this message translates to:
  /// **'Back to available homes'**
  String get legacy_bb8750bbb386;

  /// No description provided for @legacy_5948743ed42f.
  ///
  /// In en, this message translates to:
  /// **'Back to properties'**
  String get legacy_5948743ed42f;

  /// No description provided for @legacy_409c0423a738.
  ///
  /// In en, this message translates to:
  /// **'Backend operations'**
  String get legacy_409c0423a738;

  /// No description provided for @legacy_c7dea812c6cd.
  ///
  /// In en, this message translates to:
  /// **'Balances up to date'**
  String get legacy_c7dea812c6cd;

  /// No description provided for @legacy_09498ef7bc36.
  ///
  /// In en, this message translates to:
  /// **'Bedroom door lock is loose'**
  String get legacy_09498ef7bc36;

  /// No description provided for @legacy_78177aa17721.
  ///
  /// In en, this message translates to:
  /// **'Bedsitter B3'**
  String get legacy_78177aa17721;

  /// No description provided for @legacy_4442bbcbe48e.
  ///
  /// In en, this message translates to:
  /// **'Bright homes close to offices, schools, and everyday services.'**
  String get legacy_4442bbcbe48e;

  /// No description provided for @legacy_79ad9eb8bd70.
  ///
  /// In en, this message translates to:
  /// **'Browse the latest verified listings instead.'**
  String get legacy_79ad9eb8bd70;

  /// No description provided for @legacy_5d1a39689bde.
  ///
  /// In en, this message translates to:
  /// **'Built to keep landlords and tenants moving—even when the connection does not.'**
  String get legacy_5d1a39689bde;

  /// No description provided for @legacy_42aa58c476c7.
  ///
  /// In en, this message translates to:
  /// **'Business name (optional)'**
  String get legacy_42aa58c476c7;

  /// No description provided for @legacy_9e8f004ad32f.
  ///
  /// In en, this message translates to:
  /// **'Call property emergency line'**
  String get legacy_9e8f004ad32f;

  /// No description provided for @legacy_56196683592d.
  ///
  /// In en, this message translates to:
  /// **'Cancel request'**
  String get legacy_56196683592d;

  /// No description provided for @legacy_1046a5651648.
  ///
  /// In en, this message translates to:
  /// **'Cancel this request?'**
  String get legacy_1046a5651648;

  /// No description provided for @legacy_13dfa16f1ac9.
  ///
  /// In en, this message translates to:
  /// **'Canceled or expired'**
  String get legacy_13dfa16f1ac9;

  /// No description provided for @legacy_7c4f7e970e2e.
  ///
  /// In en, this message translates to:
  /// **'Card (Bank)'**
  String get legacy_7c4f7e970e2e;

  /// No description provided for @legacy_1abbfc6b813f.
  ///
  /// In en, this message translates to:
  /// **'Check for my invitation'**
  String get legacy_1abbfc6b813f;

  /// No description provided for @legacy_ae1b6f51f5f5.
  ///
  /// In en, this message translates to:
  /// **'Check payment status'**
  String get legacy_ae1b6f51f5f5;

  /// No description provided for @legacy_7732287944e2.
  ///
  /// In en, this message translates to:
  /// **'Check your email'**
  String get legacy_7732287944e2;

  /// No description provided for @legacy_6ee37a380f57.
  ///
  /// In en, this message translates to:
  /// **'Choose how you will use Nyumba to finish setting up.'**
  String get legacy_6ee37a380f57;

  /// No description provided for @legacy_fcefe2e09cef.
  ///
  /// In en, this message translates to:
  /// **'Choose the language used throughout Nyumba.'**
  String get legacy_fcefe2e09cef;

  /// No description provided for @legacy_7b268823822d.
  ///
  /// In en, this message translates to:
  /// **'City or town'**
  String get legacy_7b268823822d;

  /// No description provided for @legacy_25c57a564163.
  ///
  /// In en, this message translates to:
  /// **'Close notifications'**
  String get legacy_25c57a564163;

  /// No description provided for @legacy_f8ccedba8628.
  ///
  /// In en, this message translates to:
  /// **'Comma-separated, for example water, internet'**
  String get legacy_f8ccedba8628;

  /// No description provided for @legacy_05c0313edba1.
  ///
  /// In en, this message translates to:
  /// **'Commercial guardrails'**
  String get legacy_05c0313edba1;

  /// No description provided for @legacy_ef9e99594229.
  ///
  /// In en, this message translates to:
  /// **'Configure local plan drafts for the demo workspace.'**
  String get legacy_ef9e99594229;

  /// No description provided for @legacy_5ac265f396a2.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get legacy_5ac265f396a2;

  /// No description provided for @legacy_07243f1fb7aa.
  ///
  /// In en, this message translates to:
  /// **'Contact phone'**
  String get legacy_07243f1fb7aa;

  /// No description provided for @legacy_4bd14d1bbe44.
  ///
  /// In en, this message translates to:
  /// **'Contact requests'**
  String get legacy_4bd14d1bbe44;

  /// No description provided for @legacy_868753cfdbdb.
  ///
  /// In en, this message translates to:
  /// **'Contact the landlord or submit an application.'**
  String get legacy_868753cfdbdb;

  /// No description provided for @legacy_61cb93aa1978.
  ///
  /// In en, this message translates to:
  /// **'Continue to subscriptions'**
  String get legacy_61cb93aa1978;

  /// No description provided for @legacy_777e1c1cee34.
  ///
  /// In en, this message translates to:
  /// **'Contractor visit'**
  String get legacy_777e1c1cee34;

  /// No description provided for @legacy_67db30fee78e.
  ///
  /// In en, this message translates to:
  /// **'Could not load subscriptions'**
  String get legacy_67db30fee78e;

  /// No description provided for @legacy_0c3abc3568cd.
  ///
  /// In en, this message translates to:
  /// **'Could not load the account directory'**
  String get legacy_0c3abc3568cd;

  /// No description provided for @legacy_2efe55a8b400.
  ///
  /// In en, this message translates to:
  /// **'Counted from the live subscription documents'**
  String get legacy_2efe55a8b400;

  /// No description provided for @legacy_65a5a1d823df.
  ///
  /// In en, this message translates to:
  /// **'Create a local draft awaiting sync'**
  String get legacy_65a5a1d823df;

  /// No description provided for @legacy_ac6e978406f2.
  ///
  /// In en, this message translates to:
  /// **'Create document'**
  String get legacy_ac6e978406f2;

  /// No description provided for @legacy_e841a7dc5b16.
  ///
  /// In en, this message translates to:
  /// **'Create tenant'**
  String get legacy_e841a7dc5b16;

  /// No description provided for @legacy_13ec31314043.
  ///
  /// In en, this message translates to:
  /// **'Create your landlord account'**
  String get legacy_13ec31314043;

  /// No description provided for @legacy_f65cbe878563.
  ///
  /// In en, this message translates to:
  /// **'Credits applied'**
  String get legacy_f65cbe878563;

  /// No description provided for @legacy_988a691f049e.
  ///
  /// In en, this message translates to:
  /// **'Current balance'**
  String get legacy_988a691f049e;

  /// No description provided for @legacy_850d391fccde.
  ///
  /// In en, this message translates to:
  /// **'Demo data — the figures on this page are seeded examples,'**
  String get legacy_850d391fccde;

  /// No description provided for @legacy_33cd45a2fcfb.
  ///
  /// In en, this message translates to:
  /// **'Demo only: this entry stays on this device and no'**
  String get legacy_33cd45a2fcfb;

  /// No description provided for @legacy_e708aa6b3128.
  ///
  /// In en, this message translates to:
  /// **'Describe the issue'**
  String get legacy_e708aa6b3128;

  /// No description provided for @legacy_f6cbe2f0c1f8.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get legacy_f6cbe2f0c1f8;

  /// No description provided for @legacy_68aca33ffb28.
  ///
  /// In en, this message translates to:
  /// **'Details available offline'**
  String get legacy_68aca33ffb28;

  /// No description provided for @legacy_7485facc4094.
  ///
  /// In en, this message translates to:
  /// **'District (optional)'**
  String get legacy_7485facc4094;

  /// No description provided for @legacy_7df8249c898d.
  ///
  /// In en, this message translates to:
  /// **'District or city area'**
  String get legacy_7df8249c898d;

  /// No description provided for @legacy_97fa0725b718.
  ///
  /// In en, this message translates to:
  /// **'Document actions'**
  String get legacy_97fa0725b718;

  /// No description provided for @legacy_331b273e05e4.
  ///
  /// In en, this message translates to:
  /// **'Document date'**
  String get legacy_331b273e05e4;

  /// No description provided for @legacy_7802d1acd234.
  ///
  /// In en, this message translates to:
  /// **'Document request sent'**
  String get legacy_7802d1acd234;

  /// No description provided for @legacy_5b81f70d59bd.
  ///
  /// In en, this message translates to:
  /// **'Document type'**
  String get legacy_5b81f70d59bd;

  /// No description provided for @legacy_66cf55d1e126.
  ///
  /// In en, this message translates to:
  /// **'Draft monthly revenue'**
  String get legacy_66cf55d1e126;

  /// No description provided for @legacy_a80582b7f67b.
  ///
  /// In en, this message translates to:
  /// **'Draft plan configuration'**
  String get legacy_a80582b7f67b;

  /// No description provided for @legacy_050e91760531.
  ///
  /// In en, this message translates to:
  /// **'Draft saved locally. You can publish it when ready.'**
  String get legacy_050e91760531;

  /// No description provided for @legacy_b29f8aea102d.
  ///
  /// In en, this message translates to:
  /// **'e.g. Bathroom light not working'**
  String get legacy_b29f8aea102d;

  /// No description provided for @legacy_4452cbdbee0f.
  ///
  /// In en, this message translates to:
  /// **'Edit draft'**
  String get legacy_4452cbdbee0f;

  /// No description provided for @legacy_eb1d952e8e05.
  ///
  /// In en, this message translates to:
  /// **'Edit listing'**
  String get legacy_eb1d952e8e05;

  /// No description provided for @legacy_3fed45fc96a0.
  ///
  /// In en, this message translates to:
  /// **'Edit property'**
  String get legacy_3fed45fc96a0;

  /// No description provided for @legacy_6870ec2186ce.
  ///
  /// In en, this message translates to:
  /// **'Edit rental space'**
  String get legacy_6870ec2186ce;

  /// No description provided for @legacy_ab9ccf99c5b7.
  ///
  /// In en, this message translates to:
  /// **'Emergency help'**
  String get legacy_ab9ccf99c5b7;

  /// No description provided for @legacy_213cc828f5ab.
  ///
  /// In en, this message translates to:
  /// **'Enter workspace'**
  String get legacy_213cc828f5ab;

  /// No description provided for @legacy_c06bf9670174.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get legacy_c06bf9670174;

  /// No description provided for @legacy_d8a74fb9672b.
  ///
  /// In en, this message translates to:
  /// **'Every property, payment and request in one calm workspace.'**
  String get legacy_d8a74fb9672b;

  /// No description provided for @legacy_efc85bc4f92b.
  ///
  /// In en, this message translates to:
  /// **'Every rentable space has its own rent, occupancy, lease, and maintenance history.'**
  String get legacy_efc85bc4f92b;

  /// No description provided for @legacy_a6d62f9d816a.
  ///
  /// In en, this message translates to:
  /// **'Explore the role demos'**
  String get legacy_a6d62f9d816a;

  /// No description provided for @legacy_556d19d720a5.
  ///
  /// In en, this message translates to:
  /// **'Export report'**
  String get legacy_556d19d720a5;

  /// No description provided for @legacy_33dc0aa02105.
  ///
  /// In en, this message translates to:
  /// **'Family homes with green shared spaces and reliable water.'**
  String get legacy_33dc0aa02105;

  /// No description provided for @legacy_4b572516ced9.
  ///
  /// In en, this message translates to:
  /// **'Filter resources'**
  String get legacy_4b572516ced9;

  /// No description provided for @legacy_91dba648725e.
  ///
  /// In en, this message translates to:
  /// **'Find a place that feels like home.'**
  String get legacy_91dba648725e;

  /// No description provided for @legacy_ab50eb11b4d4.
  ///
  /// In en, this message translates to:
  /// **'Floor area (m²)'**
  String get legacy_ab50eb11b4d4;

  /// No description provided for @legacy_58b3246548b0.
  ///
  /// In en, this message translates to:
  /// **'For fire, immediate danger, or a serious medical emergency,'**
  String get legacy_58b3246548b0;

  /// No description provided for @legacy_677c7571b991.
  ///
  /// In en, this message translates to:
  /// **'From the server audit log'**
  String get legacy_677c7571b991;

  /// No description provided for @legacy_ae4f7a8cbc1a.
  ///
  /// In en, this message translates to:
  /// **'Full CRUD'**
  String get legacy_ae4f7a8cbc1a;

  /// No description provided for @legacy_40c6b37a520b.
  ///
  /// In en, this message translates to:
  /// **'Generate an unsigned local draft'**
  String get legacy_40c6b37a520b;

  /// No description provided for @legacy_840a9ed3cdca.
  ///
  /// In en, this message translates to:
  /// **'Generate invoices'**
  String get legacy_840a9ed3cdca;

  /// No description provided for @legacy_d069a9dcd1a8.
  ///
  /// In en, this message translates to:
  /// **'Generated by Nyumba Property Management'**
  String get legacy_d069a9dcd1a8;

  /// No description provided for @legacy_5ad3dbd1242a.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get legacy_5ad3dbd1242a;

  /// No description provided for @legacy_8a3200303760.
  ///
  /// In en, this message translates to:
  /// **'Growth and revenue must be aggregated across every landlord by a'**
  String get legacy_8a3200303760;

  /// No description provided for @legacy_e9f976f216fe.
  ///
  /// In en, this message translates to:
  /// **'Health checks are not wired up'**
  String get legacy_e9f976f216fe;

  /// No description provided for @legacy_11ec97e063c1.
  ///
  /// In en, this message translates to:
  /// **'Here is what is happening with your home.'**
  String get legacy_11ec97e063c1;

  /// No description provided for @legacy_187bc899879d.
  ///
  /// In en, this message translates to:
  /// **'How accounts are created'**
  String get legacy_187bc899879d;

  /// No description provided for @legacy_b3d88eda879e.
  ///
  /// In en, this message translates to:
  /// **'How payments work'**
  String get legacy_b3d88eda879e;

  /// No description provided for @legacy_bbb05d01d090.
  ///
  /// In en, this message translates to:
  /// **'How was it paid?'**
  String get legacy_bbb05d01d090;

  /// No description provided for @legacy_bd87508bf1c0.
  ///
  /// In en, this message translates to:
  /// **'Illustrative monthly price (UGX)'**
  String get legacy_bd87508bf1c0;

  /// No description provided for @legacy_c1f88e9d6c41.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get legacy_c1f88e9d6c41;

  /// No description provided for @legacy_7f8c5b20c8e0.
  ///
  /// In en, this message translates to:
  /// **'In-app mobile money checkout is not available yet'**
  String get legacy_7f8c5b20c8e0;

  /// No description provided for @legacy_fb5d66cab94c.
  ///
  /// In en, this message translates to:
  /// **'Include the location and when it started.'**
  String get legacy_fb5d66cab94c;

  /// No description provided for @legacy_5d230402c696.
  ///
  /// In en, this message translates to:
  /// **'Interested in this home?'**
  String get legacy_5d230402c696;

  /// No description provided for @legacy_2aa44ed00a61.
  ///
  /// In en, this message translates to:
  /// **'Invitations pending'**
  String get legacy_2aa44ed00a61;

  /// No description provided for @legacy_320de51a0fea.
  ///
  /// In en, this message translates to:
  /// **'Invite a user'**
  String get legacy_320de51a0fea;

  /// No description provided for @legacy_6ac487a0242c.
  ///
  /// In en, this message translates to:
  /// **'Invite user'**
  String get legacy_6ac487a0242c;

  /// No description provided for @legacy_2864b372fa2c.
  ///
  /// In en, this message translates to:
  /// **'Invoice amount (UGX)'**
  String get legacy_2864b372fa2c;

  /// No description provided for @legacy_8f953aa4b317.
  ///
  /// In en, this message translates to:
  /// **'JPEG, PNG, or WebP; up to 5 MB each and 10 photos.'**
  String get legacy_8f953aa4b317;

  /// No description provided for @legacy_3259de868228.
  ///
  /// In en, this message translates to:
  /// **'Keep request'**
  String get legacy_3259de868228;

  /// No description provided for @legacy_a4e70f65da38.
  ///
  /// In en, this message translates to:
  /// **'Keep this document for your records.'**
  String get legacy_a4e70f65da38;

  /// No description provided for @legacy_4ac4c025a16c.
  ///
  /// In en, this message translates to:
  /// **'Landlord accounts'**
  String get legacy_4ac4c025a16c;

  /// No description provided for @legacy_e484fc62d975.
  ///
  /// In en, this message translates to:
  /// **'Landlord approvals'**
  String get legacy_e484fc62d975;

  /// No description provided for @legacy_7f580c55dacf.
  ///
  /// In en, this message translates to:
  /// **'Landlords list verified rental spaces; you contact them directly.'**
  String get legacy_7f580c55dacf;

  /// No description provided for @legacy_3fab8ebaa9b0.
  ///
  /// In en, this message translates to:
  /// **'Landlords with a portfolio'**
  String get legacy_3fab8ebaa9b0;

  /// No description provided for @legacy_bcdf701c4dfb.
  ///
  /// In en, this message translates to:
  /// **'Last active'**
  String get legacy_bcdf701c4dfb;

  /// No description provided for @legacy_9eade28f426b.
  ///
  /// In en, this message translates to:
  /// **'Last recorded payment'**
  String get legacy_9eade28f426b;

  /// No description provided for @legacy_15e2eaa05567.
  ///
  /// In en, this message translates to:
  /// **'Leaking tap in kitchen'**
  String get legacy_15e2eaa05567;

  /// No description provided for @legacy_2d82afb098e0.
  ///
  /// In en, this message translates to:
  /// **'Lease term'**
  String get legacy_2d82afb098e0;

  /// No description provided for @legacy_e9943936f8dd.
  ///
  /// In en, this message translates to:
  /// **'Leases ending soon'**
  String get legacy_e9943936f8dd;

  /// No description provided for @legacy_8d5940a39442.
  ///
  /// In en, this message translates to:
  /// **'Limited access'**
  String get legacy_8d5940a39442;

  /// No description provided for @legacy_44d28c3aa0d6.
  ///
  /// In en, this message translates to:
  /// **'Listing actions'**
  String get legacy_44d28c3aa0d6;

  /// No description provided for @legacy_135ef3946f27.
  ///
  /// In en, this message translates to:
  /// **'Listing changes saved locally and queued to sync.'**
  String get legacy_135ef3946f27;

  /// No description provided for @legacy_6943109f8f3d.
  ///
  /// In en, this message translates to:
  /// **'Listing created'**
  String get legacy_6943109f8f3d;

  /// No description provided for @legacy_7b3fbf322e7e.
  ///
  /// In en, this message translates to:
  /// **'Listing photos'**
  String get legacy_7b3fbf322e7e;

  /// No description provided for @legacy_ba77096dda3d.
  ///
  /// In en, this message translates to:
  /// **'Listing title'**
  String get legacy_ba77096dda3d;

  /// No description provided for @legacy_3c770ae553ba.
  ///
  /// In en, this message translates to:
  /// **'Live server-owned subscription records. Activation is an audited'**
  String get legacy_3c770ae553ba;

  /// No description provided for @legacy_bf9882dd91e8.
  ///
  /// In en, this message translates to:
  /// **'Local history of edits to this demo directory'**
  String get legacy_bf9882dd91e8;

  /// No description provided for @legacy_c905013aab29.
  ///
  /// In en, this message translates to:
  /// **'Local only'**
  String get legacy_c905013aab29;

  /// No description provided for @legacy_258cc45f07b0.
  ///
  /// In en, this message translates to:
  /// **'Local-first • Secure sync • Multi-platform'**
  String get legacy_258cc45f07b0;

  /// No description provided for @legacy_12cd222fe203.
  ///
  /// In en, this message translates to:
  /// **'Maintenance requests'**
  String get legacy_12cd222fe203;

  /// No description provided for @legacy_07d68ed8fbd7.
  ///
  /// In en, this message translates to:
  /// **'Make primary'**
  String get legacy_07d68ed8fbd7;

  /// No description provided for @legacy_0fc5fd0d0fb1.
  ///
  /// In en, this message translates to:
  /// **'Manage properties, tenants, and payments in one calm'**
  String get legacy_0fc5fd0d0fb1;

  /// No description provided for @legacy_24d581a75cfe.
  ///
  /// In en, this message translates to:
  /// **'Manage rent, invoices, receipts, and your payment history.'**
  String get legacy_24d581a75cfe;

  /// No description provided for @legacy_42ed7a36a346.
  ///
  /// In en, this message translates to:
  /// **'Manage tenant records, leases, balances, and contact details.'**
  String get legacy_42ed7a36a346;

  /// No description provided for @legacy_390c7a10e587.
  ///
  /// In en, this message translates to:
  /// **'Manageable rental-space limit'**
  String get legacy_390c7a10e587;

  /// No description provided for @legacy_fb5130c348cd.
  ///
  /// In en, this message translates to:
  /// **'Managed rental spaces'**
  String get legacy_fb5130c348cd;

  /// No description provided for @legacy_7ada8b311457.
  ///
  /// In en, this message translates to:
  /// **'Message manager'**
  String get legacy_7ada8b311457;

  /// No description provided for @legacy_8d447b507b8a.
  ///
  /// In en, this message translates to:
  /// **'Message to landlord (optional)'**
  String get legacy_8d447b507b8a;

  /// No description provided for @legacy_1fe846efc73d.
  ///
  /// In en, this message translates to:
  /// **'Minimum lease'**
  String get legacy_1fe846efc73d;

  /// No description provided for @legacy_7fe5206985b1.
  ///
  /// In en, this message translates to:
  /// **'Minimum lease (months)'**
  String get legacy_7fe5206985b1;

  /// No description provided for @legacy_4295960ebfdb.
  ///
  /// In en, this message translates to:
  /// **'Monitor adoption, approvals, and service health.'**
  String get legacy_4295960ebfdb;

  /// No description provided for @legacy_8f87ccbbfe24.
  ///
  /// In en, this message translates to:
  /// **'Monitor landlord subscriptions and confirm payments.'**
  String get legacy_8f87ccbbfe24;

  /// No description provided for @legacy_27460b369d97.
  ///
  /// In en, this message translates to:
  /// **'Monthly rent'**
  String get legacy_27460b369d97;

  /// No description provided for @legacy_742f88bd39b3.
  ///
  /// In en, this message translates to:
  /// **'Monthly rent collection trend'**
  String get legacy_742f88bd39b3;

  /// No description provided for @legacy_83854a1ef89c.
  ///
  /// In en, this message translates to:
  /// **'Monthly service charge'**
  String get legacy_83854a1ef89c;

  /// No description provided for @legacy_6e384dbfedd8.
  ///
  /// In en, this message translates to:
  /// **'Monthly service charge (UGX)'**
  String get legacy_6e384dbfedd8;

  /// No description provided for @legacy_57b68256e28f.
  ///
  /// In en, this message translates to:
  /// **'MTN Mobile Money'**
  String get legacy_57b68256e28f;

  /// No description provided for @legacy_abc1dbd4107a.
  ///
  /// In en, this message translates to:
  /// **'New account updates will appear here.'**
  String get legacy_abc1dbd4107a;

  /// No description provided for @legacy_fb3cfa87b84e.
  ///
  /// In en, this message translates to:
  /// **'New rental spaces and subscription revenue'**
  String get legacy_fb3cfa87b84e;

  /// No description provided for @legacy_5977ded363b2.
  ///
  /// In en, this message translates to:
  /// **'New request'**
  String get legacy_5977ded363b2;

  /// No description provided for @legacy_30436eb5a2f2.
  ///
  /// In en, this message translates to:
  /// **'New requests, notes, and photos save on this device first.'**
  String get legacy_30436eb5a2f2;

  /// No description provided for @legacy_6c55f6e6eb78.
  ///
  /// In en, this message translates to:
  /// **'New tenant notice'**
  String get legacy_6c55f6e6eb78;

  /// No description provided for @legacy_ac51ad3e86a0.
  ///
  /// In en, this message translates to:
  /// **'New to Nyumba? Create a landlord account'**
  String get legacy_ac51ad3e86a0;

  /// No description provided for @legacy_894bb2b7ac07.
  ///
  /// In en, this message translates to:
  /// **'Next photo'**
  String get legacy_894bb2b7ac07;

  /// No description provided for @legacy_9b1f0823459d.
  ///
  /// In en, this message translates to:
  /// **'No access'**
  String get legacy_9b1f0823459d;

  /// No description provided for @legacy_0efad23779a4.
  ///
  /// In en, this message translates to:
  /// **'No active subscriptions yet.'**
  String get legacy_0efad23779a4;

  /// No description provided for @legacy_ecf67187425e.
  ///
  /// In en, this message translates to:
  /// **'No audited commands recorded yet.'**
  String get legacy_ecf67187425e;

  /// No description provided for @legacy_a2a5fa88dea9.
  ///
  /// In en, this message translates to:
  /// **'No documents in this category yet.'**
  String get legacy_a2a5fa88dea9;

  /// No description provided for @legacy_6d3adfb7de47.
  ///
  /// In en, this message translates to:
  /// **'No documents match'**
  String get legacy_6d3adfb7de47;

  /// No description provided for @legacy_05e85dbd0259.
  ///
  /// In en, this message translates to:
  /// **'No landlord applications are waiting right now.'**
  String get legacy_05e85dbd0259;

  /// No description provided for @legacy_0bf2ed95bf62.
  ///
  /// In en, this message translates to:
  /// **'No listings match this filter.'**
  String get legacy_0bf2ed95bf62;

  /// No description provided for @legacy_e39668b06363.
  ///
  /// In en, this message translates to:
  /// **'No local directory edits recorded yet.'**
  String get legacy_e39668b06363;

  /// No description provided for @legacy_b2fe1b89cf31.
  ///
  /// In en, this message translates to:
  /// **'No maintenance requests found'**
  String get legacy_b2fe1b89cf31;

  /// No description provided for @legacy_cd48706661b3.
  ///
  /// In en, this message translates to:
  /// **'No notices yet'**
  String get legacy_cd48706661b3;

  /// No description provided for @legacy_37ecf3603dbf.
  ///
  /// In en, this message translates to:
  /// **'No notifications yet'**
  String get legacy_37ecf3603dbf;

  /// No description provided for @legacy_24a7ec2badbb.
  ///
  /// In en, this message translates to:
  /// **'No payments match this filter.'**
  String get legacy_24a7ec2badbb;

  /// No description provided for @legacy_e728248f4f4e.
  ///
  /// In en, this message translates to:
  /// **'No payments recorded yet'**
  String get legacy_e728248f4f4e;

  /// No description provided for @legacy_032714804b6d.
  ///
  /// In en, this message translates to:
  /// **'No power in the living room'**
  String get legacy_032714804b6d;

  /// No description provided for @legacy_4898d2cc8c62.
  ///
  /// In en, this message translates to:
  /// **'No public catalog entries are published yet. Entitlements'**
  String get legacy_4898d2cc8c62;

  /// No description provided for @legacy_3272c50bc15b.
  ///
  /// In en, this message translates to:
  /// **'No resources match this access filter.'**
  String get legacy_3272c50bc15b;

  /// No description provided for @legacy_813df4ea6edc.
  ///
  /// In en, this message translates to:
  /// **'No subscription commands in the recent audit log.'**
  String get legacy_813df4ea6edc;

  /// No description provided for @legacy_0fae97d2b09d.
  ///
  /// In en, this message translates to:
  /// **'No subscription data yet.'**
  String get legacy_0fae97d2b09d;

  /// No description provided for @legacy_c07c32f4c2f7.
  ///
  /// In en, this message translates to:
  /// **'No subscriptions are waiting on a payment.'**
  String get legacy_c07c32f4c2f7;

  /// No description provided for @legacy_f7da4afe440b.
  ///
  /// In en, this message translates to:
  /// **'No tenancy on this device yet'**
  String get legacy_f7da4afe440b;

  /// No description provided for @legacy_178f473438a3.
  ///
  /// In en, this message translates to:
  /// **'No tenants match your search.'**
  String get legacy_178f473438a3;

  /// No description provided for @legacy_7446e6eb6016.
  ///
  /// In en, this message translates to:
  /// **'No vacant rental spaces are available for a new tenancy.'**
  String get legacy_7446e6eb6016;

  /// No description provided for @legacy_9702912500e7.
  ///
  /// In en, this message translates to:
  /// **'No work orders match this filter.'**
  String get legacy_9702912500e7;

  /// No description provided for @legacy_ebeef712d082.
  ///
  /// In en, this message translates to:
  /// **'Note for your property manager (optional)'**
  String get legacy_ebeef712d082;

  /// No description provided for @legacy_21ad0f972eb1.
  ///
  /// In en, this message translates to:
  /// **'Nothing needs attention'**
  String get legacy_21ad0f972eb1;

  /// No description provided for @legacy_518072163805.
  ///
  /// In en, this message translates to:
  /// **'Notice queued locally. It sends after the next sync.'**
  String get legacy_518072163805;

  /// No description provided for @legacy_ec3d1d69b143.
  ///
  /// In en, this message translates to:
  /// **'Notice text'**
  String get legacy_ec3d1d69b143;

  /// No description provided for @legacy_b2ce9a0df1af.
  ///
  /// In en, this message translates to:
  /// **'Notices from your property'**
  String get legacy_b2ce9a0df1af;

  /// No description provided for @legacy_095e15b88673.
  ///
  /// In en, this message translates to:
  /// **'Notices your property manager publishes will appear here.'**
  String get legacy_095e15b88673;

  /// No description provided for @legacy_5a1247ecd820.
  ///
  /// In en, this message translates to:
  /// **'Notifications could not be loaded'**
  String get legacy_5a1247ecd820;

  /// No description provided for @legacy_30ae7b84b775.
  ///
  /// In en, this message translates to:
  /// **'Nyumba Property Management · Kampala, Uganda'**
  String get legacy_30ae7b84b775;

  /// No description provided for @legacy_986b8d849268.
  ///
  /// In en, this message translates to:
  /// **'Occupancy rate across all properties'**
  String get legacy_986b8d849268;

  /// No description provided for @legacy_ba2e05f3807f.
  ///
  /// In en, this message translates to:
  /// **'Occupancy status'**
  String get legacy_ba2e05f3807f;

  /// No description provided for @legacy_38b9d88c1fdb.
  ///
  /// In en, this message translates to:
  /// **'On this device'**
  String get legacy_38b9d88c1fdb;

  /// No description provided for @legacy_79fc721e25ac.
  ///
  /// In en, this message translates to:
  /// **'Open (3)'**
  String get legacy_79fc721e25ac;

  /// No description provided for @legacy_9d955b4540b8.
  ///
  /// In en, this message translates to:
  /// **'Open lease'**
  String get legacy_9d955b4540b8;

  /// No description provided for @legacy_d2d30e93af2d.
  ///
  /// In en, this message translates to:
  /// **'Open requests'**
  String get legacy_d2d30e93af2d;

  /// No description provided for @legacy_b3e34b185d06.
  ///
  /// In en, this message translates to:
  /// **'Open workspace'**
  String get legacy_b3e34b185d06;

  /// No description provided for @legacy_45613881f8cd.
  ///
  /// In en, this message translates to:
  /// **'Paid on'**
  String get legacy_45613881f8cd;

  /// No description provided for @legacy_c0f9c50e948f.
  ///
  /// In en, this message translates to:
  /// **'Parking spaces'**
  String get legacy_c0f9c50e948f;

  /// No description provided for @legacy_af3e3987675f.
  ///
  /// In en, this message translates to:
  /// **'Past due'**
  String get legacy_af3e3987675f;

  /// No description provided for @legacy_b6ff37684253.
  ///
  /// In en, this message translates to:
  /// **'Paying inside Nyumba is not available yet. Record a'**
  String get legacy_b6ff37684253;

  /// No description provided for @legacy_b948ac04b854.
  ///
  /// In en, this message translates to:
  /// **'Payment method'**
  String get legacy_b948ac04b854;

  /// No description provided for @legacy_5b0aebbbbf83.
  ///
  /// In en, this message translates to:
  /// **'Payment recorded locally and queued to sync — awaiting confirmation.'**
  String get legacy_5b0aebbbbf83;

  /// No description provided for @legacy_b246432fe4c3.
  ///
  /// In en, this message translates to:
  /// **'Payment records with this status will appear here.'**
  String get legacy_b246432fe4c3;

  /// No description provided for @legacy_4f8609a5debe.
  ///
  /// In en, this message translates to:
  /// **'Payment reference (required)'**
  String get legacy_4f8609a5debe;

  /// No description provided for @legacy_34d6b2ea59bf.
  ///
  /// In en, this message translates to:
  /// **'Payment report exported.'**
  String get legacy_34d6b2ea59bf;

  /// No description provided for @legacy_bb33a7f41817.
  ///
  /// In en, this message translates to:
  /// **'Pending approval'**
  String get legacy_bb33a7f41817;

  /// No description provided for @legacy_0405f4b67edd.
  ///
  /// In en, this message translates to:
  /// **'Pending approvals'**
  String get legacy_0405f4b67edd;

  /// No description provided for @legacy_e45ceb73ca49.
  ///
  /// In en, this message translates to:
  /// **'Pending sync'**
  String get legacy_e45ceb73ca49;

  /// No description provided for @legacy_c036d89453f7.
  ///
  /// In en, this message translates to:
  /// **'People create their own accounts by signing in to Nyumba:'**
  String get legacy_c036d89453f7;

  /// No description provided for @legacy_ede970bbd2e5.
  ///
  /// In en, this message translates to:
  /// **'Per-landlord figures on the landlord dashboard are derived'**
  String get legacy_ede970bbd2e5;

  /// No description provided for @legacy_bfc8abe9aab0.
  ///
  /// In en, this message translates to:
  /// **'Pets policy'**
  String get legacy_bfc8abe9aab0;

  /// No description provided for @legacy_35878f0bd6c1.
  ///
  /// In en, this message translates to:
  /// **'Phone (optional)'**
  String get legacy_35878f0bd6c1;

  /// No description provided for @legacy_05a027aeae0a.
  ///
  /// In en, this message translates to:
  /// **'Plan available'**
  String get legacy_05a027aeae0a;

  /// No description provided for @legacy_ca1e54086cc6.
  ///
  /// In en, this message translates to:
  /// **'Plan capacity details could not be loaded right now,'**
  String get legacy_ca1e54086cc6;

  /// No description provided for @legacy_b80f24b5897a.
  ///
  /// In en, this message translates to:
  /// **'Plan catalogue'**
  String get legacy_b80f24b5897a;

  /// No description provided for @legacy_897f33fc0789.
  ///
  /// In en, this message translates to:
  /// **'Plan unavailable'**
  String get legacy_897f33fc0789;

  /// No description provided for @legacy_5489dddccd3e.
  ///
  /// In en, this message translates to:
  /// **'planCatalog documents — server-owned, read-only here'**
  String get legacy_5489dddccd3e;

  /// No description provided for @legacy_014d6ce68194.
  ///
  /// In en, this message translates to:
  /// **'Planned water maintenance'**
  String get legacy_014d6ce68194;

  /// No description provided for @legacy_1911a6821ddb.
  ///
  /// In en, this message translates to:
  /// **'Platform activity'**
  String get legacy_1911a6821ddb;

  /// No description provided for @legacy_f8def09651e8.
  ///
  /// In en, this message translates to:
  /// **'Platform configuration'**
  String get legacy_f8def09651e8;

  /// No description provided for @legacy_baf8ecfb939f.
  ///
  /// In en, this message translates to:
  /// **'Platform events come from the server audit log, which a demo'**
  String get legacy_baf8ecfb939f;

  /// No description provided for @legacy_c99540913e04.
  ///
  /// In en, this message translates to:
  /// **'Platform growth'**
  String get legacy_c99540913e04;

  /// No description provided for @legacy_111ec5778725.
  ///
  /// In en, this message translates to:
  /// **'Platform overview'**
  String get legacy_111ec5778725;

  /// No description provided for @legacy_7ea85559c9e0.
  ///
  /// In en, this message translates to:
  /// **'Platform totals have to be aggregated on the server from'**
  String get legacy_7ea85559c9e0;

  /// No description provided for @legacy_66f436a407a6.
  ///
  /// In en, this message translates to:
  /// **'Platform-wide payment, adoption, and service reporting.'**
  String get legacy_66f436a407a6;

  /// No description provided for @legacy_18f31833e854.
  ///
  /// In en, this message translates to:
  /// **'Policy source'**
  String get legacy_18f31833e854;

  /// No description provided for @legacy_499b60800cd3.
  ///
  /// In en, this message translates to:
  /// **'Portfolio overview'**
  String get legacy_499b60800cd3;

  /// No description provided for @legacy_2343b47fcfcb.
  ///
  /// In en, this message translates to:
  /// **'Potential monthly rent'**
  String get legacy_2343b47fcfcb;

  /// No description provided for @legacy_2f55863e032e.
  ///
  /// In en, this message translates to:
  /// **'Previous photo'**
  String get legacy_2f55863e032e;

  /// No description provided for @legacy_9b268ca3f4d1.
  ///
  /// In en, this message translates to:
  /// **'Print and share invoices, receipts, leases, and notices.'**
  String get legacy_9b268ca3f4d1;

  /// No description provided for @legacy_652d6bff4378.
  ///
  /// In en, this message translates to:
  /// **'Print receipt'**
  String get legacy_652d6bff4378;

  /// No description provided for @legacy_4a8120e5f71b.
  ///
  /// In en, this message translates to:
  /// **'Print statement'**
  String get legacy_4a8120e5f71b;

  /// No description provided for @legacy_657add154fb3.
  ///
  /// In en, this message translates to:
  /// **'Private contact email (optional)'**
  String get legacy_657add154fb3;

  /// No description provided for @legacy_750fab6debca.
  ///
  /// In en, this message translates to:
  /// **'Private listings'**
  String get legacy_750fab6debca;

  /// No description provided for @legacy_2c55b63a694e.
  ///
  /// In en, this message translates to:
  /// **'Private to your tenancy'**
  String get legacy_2c55b63a694e;

  /// No description provided for @legacy_728442402aea.
  ///
  /// In en, this message translates to:
  /// **'Private, routed contact'**
  String get legacy_728442402aea;

  /// No description provided for @legacy_3f4f74e6d1d8.
  ///
  /// In en, this message translates to:
  /// **'Profiles & settings'**
  String get legacy_3f4f74e6d1d8;

  /// No description provided for @legacy_ca946b1e7df8.
  ///
  /// In en, this message translates to:
  /// **'Properties and rental spaces'**
  String get legacy_ca946b1e7df8;

  /// No description provided for @legacy_3038fa43b656.
  ///
  /// In en, this message translates to:
  /// **'Property changes saved locally and queued to sync.'**
  String get legacy_3038fa43b656;

  /// No description provided for @legacy_1e52d3fbfae3.
  ///
  /// In en, this message translates to:
  /// **'PROPERTY MANAGEMENT'**
  String get legacy_1e52d3fbfae3;

  /// No description provided for @legacy_366e5ff4c24b.
  ///
  /// In en, this message translates to:
  /// **'Property name'**
  String get legacy_366e5ff4c24b;

  /// No description provided for @legacy_094c2aac774a.
  ///
  /// In en, this message translates to:
  /// **'Property not found'**
  String get legacy_094c2aac774a;

  /// No description provided for @legacy_044733ac70bc.
  ///
  /// In en, this message translates to:
  /// **'Property photos'**
  String get legacy_044733ac70bc;

  /// No description provided for @legacy_9d65e9ee9d0d.
  ///
  /// In en, this message translates to:
  /// **'Property saved locally and added to the sync queue.'**
  String get legacy_9d65e9ee9d0d;

  /// No description provided for @legacy_c6a28d4dcbfd.
  ///
  /// In en, this message translates to:
  /// **'Provider transaction ID or manual reference'**
  String get legacy_c6a28d4dcbfd;

  /// No description provided for @legacy_300106cfb886.
  ///
  /// In en, this message translates to:
  /// **'Public listings'**
  String get legacy_300106cfb886;

  /// No description provided for @legacy_06b61c2493c9.
  ///
  /// In en, this message translates to:
  /// **'Public; do not enter an exact address'**
  String get legacy_06b61c2493c9;

  /// No description provided for @legacy_d165bd37ec33.
  ///
  /// In en, this message translates to:
  /// **'Publication request saved locally. It will become public after server validation.'**
  String get legacy_d165bd37ec33;

  /// No description provided for @legacy_b1c8fca481c6.
  ///
  /// In en, this message translates to:
  /// **'Queue notice'**
  String get legacy_b1c8fca481c6;

  /// No description provided for @legacy_385692330c01.
  ///
  /// In en, this message translates to:
  /// **'Quiet apartment living with secure parking in Ntinda.'**
  String get legacy_385692330c01;

  /// No description provided for @legacy_8ac767353080.
  ///
  /// In en, this message translates to:
  /// **'Read only'**
  String get legacy_8ac767353080;

  /// No description provided for @legacy_c648d2e87fd6.
  ///
  /// In en, this message translates to:
  /// **'Reason recorded in the audit log'**
  String get legacy_c648d2e87fd6;

  /// No description provided for @legacy_c865144ce19b.
  ///
  /// In en, this message translates to:
  /// **'Receipts remain available on this device while offline.'**
  String get legacy_c865144ce19b;

  /// No description provided for @legacy_6cb44b56336a.
  ///
  /// In en, this message translates to:
  /// **'Recent activity'**
  String get legacy_6cb44b56336a;

  /// No description provided for @legacy_79ef5400cc73.
  ///
  /// In en, this message translates to:
  /// **'Recent demo activity'**
  String get legacy_79ef5400cc73;

  /// No description provided for @legacy_4f26fbf98e6e.
  ///
  /// In en, this message translates to:
  /// **'Recent payments'**
  String get legacy_4f26fbf98e6e;

  /// No description provided for @legacy_df8eadb8ff89.
  ///
  /// In en, this message translates to:
  /// **'Recent platform activity'**
  String get legacy_df8eadb8ff89;

  /// No description provided for @legacy_56c7ab899221.
  ///
  /// In en, this message translates to:
  /// **'Recent security and billing events'**
  String get legacy_56c7ab899221;

  /// No description provided for @legacy_3b7a75051a8d.
  ///
  /// In en, this message translates to:
  /// **'Recent subscription activity'**
  String get legacy_3b7a75051a8d;

  /// No description provided for @legacy_91776bf2f7ca.
  ///
  /// In en, this message translates to:
  /// **'Recorded on this device or confirmed by the server'**
  String get legacy_91776bf2f7ca;

  /// No description provided for @legacy_980e6180b4ac.
  ///
  /// In en, this message translates to:
  /// **'Records saved on this device stay available offline.'**
  String get legacy_980e6180b4ac;

  /// No description provided for @legacy_aeb4ef20acf5.
  ///
  /// In en, this message translates to:
  /// **'Rent collected'**
  String get legacy_aeb4ef20acf5;

  /// No description provided for @legacy_1a420e6140a1.
  ///
  /// In en, this message translates to:
  /// **'Rent collection'**
  String get legacy_1a420e6140a1;

  /// No description provided for @legacy_2649074572c0.
  ///
  /// In en, this message translates to:
  /// **'Rent payments recorded against your tenancy will appear'**
  String get legacy_2649074572c0;

  /// No description provided for @legacy_d5853af8fd56.
  ///
  /// In en, this message translates to:
  /// **'Rent period'**
  String get legacy_d5853af8fd56;

  /// No description provided for @legacy_e35d0e06f31d.
  ///
  /// In en, this message translates to:
  /// **'Rent statement'**
  String get legacy_e35d0e06f31d;

  /// No description provided for @legacy_a30edd3b0446.
  ///
  /// In en, this message translates to:
  /// **'Rental applications'**
  String get legacy_a30edd3b0446;

  /// No description provided for @legacy_82f1a754255d.
  ///
  /// In en, this message translates to:
  /// **'Rental space actions'**
  String get legacy_82f1a754255d;

  /// No description provided for @legacy_102f528329d2.
  ///
  /// In en, this message translates to:
  /// **'Rental space cannot be archived yet'**
  String get legacy_102f528329d2;

  /// No description provided for @legacy_3eb1b4ca96c5.
  ///
  /// In en, this message translates to:
  /// **'Rental space changes saved locally and queued to sync.'**
  String get legacy_3eb1b4ca96c5;

  /// No description provided for @legacy_53071a46e6e6.
  ///
  /// In en, this message translates to:
  /// **'Rental space name or number'**
  String get legacy_53071a46e6e6;

  /// No description provided for @legacy_4415411e65a5.
  ///
  /// In en, this message translates to:
  /// **'Rental space saved locally and queued to sync.'**
  String get legacy_4415411e65a5;

  /// No description provided for @legacy_f971c74fc2f2.
  ///
  /// In en, this message translates to:
  /// **'Rental space type'**
  String get legacy_f971c74fc2f2;

  /// No description provided for @legacy_7476b0476840.
  ///
  /// In en, this message translates to:
  /// **'Renting through Nyumba?'**
  String get legacy_7476b0476840;

  /// No description provided for @legacy_53de38dec81e.
  ///
  /// In en, this message translates to:
  /// **'Report a problem'**
  String get legacy_53de38dec81e;

  /// No description provided for @legacy_2c42721075bf.
  ///
  /// In en, this message translates to:
  /// **'Report a problem any time — requests are saved on this'**
  String get legacy_2c42721075bf;

  /// No description provided for @legacy_02390eb8850b.
  ///
  /// In en, this message translates to:
  /// **'Report an issue and follow every update through resolution.'**
  String get legacy_02390eb8850b;

  /// No description provided for @legacy_71cb207a12da.
  ///
  /// In en, this message translates to:
  /// **'Report an urgent property issue'**
  String get legacy_71cb207a12da;

  /// No description provided for @legacy_c170bc77f0f0.
  ///
  /// In en, this message translates to:
  /// **'Reported by'**
  String get legacy_c170bc77f0f0;

  /// No description provided for @legacy_c65b80305a4f.
  ///
  /// In en, this message translates to:
  /// **'Reporting is not available yet'**
  String get legacy_c65b80305a4f;

  /// No description provided for @legacy_453a7baffe73.
  ///
  /// In en, this message translates to:
  /// **'Request a document'**
  String get legacy_453a7baffe73;

  /// No description provided for @legacy_ca9ed239601a.
  ///
  /// In en, this message translates to:
  /// **'Request document'**
  String get legacy_ca9ed239601a;

  /// No description provided for @legacy_d1a773d243bb.
  ///
  /// In en, this message translates to:
  /// **'Request saved locally and added to the sync queue.'**
  String get legacy_d1a773d243bb;

  /// No description provided for @legacy_6402d96e5fc7.
  ///
  /// In en, this message translates to:
  /// **'Resend invitation'**
  String get legacy_6402d96e5fc7;

  /// No description provided for @legacy_02a223dfa387.
  ///
  /// In en, this message translates to:
  /// **'Restore this landlord?'**
  String get legacy_02a223dfa387;

  /// No description provided for @legacy_358a0f2643b2.
  ///
  /// In en, this message translates to:
  /// **'Review applications'**
  String get legacy_358a0f2643b2;

  /// No description provided for @legacy_c86faf3dc472.
  ///
  /// In en, this message translates to:
  /// **'Review in Users'**
  String get legacy_c86faf3dc472;

  /// No description provided for @legacy_2d8b0a7ed3fc.
  ///
  /// In en, this message translates to:
  /// **'Save payment'**
  String get legacy_2d8b0a7ed3fc;

  /// No description provided for @legacy_a9f1bf6c78f5.
  ///
  /// In en, this message translates to:
  /// **'Save property'**
  String get legacy_a9f1bf6c78f5;

  /// No description provided for @legacy_0b9d2dc54846.
  ///
  /// In en, this message translates to:
  /// **'Save rental space'**
  String get legacy_0b9d2dc54846;

  /// No description provided for @legacy_d756eb992add.
  ///
  /// In en, this message translates to:
  /// **'Save request'**
  String get legacy_d756eb992add;

  /// No description provided for @legacy_c8a44d2d60d8.
  ///
  /// In en, this message translates to:
  /// **'Scheduled visits'**
  String get legacy_c8a44d2d60d8;

  /// No description provided for @legacy_4ce4c983673d.
  ///
  /// In en, this message translates to:
  /// **'Search by neighborhood or property'**
  String get legacy_4ce4c983673d;

  /// No description provided for @legacy_a9213976e451.
  ///
  /// In en, this message translates to:
  /// **'Search documents or references'**
  String get legacy_a9213976e451;

  /// No description provided for @legacy_6f7a52f9a942.
  ///
  /// In en, this message translates to:
  /// **'Search issue, category, or request ID'**
  String get legacy_6f7a52f9a942;

  /// No description provided for @legacy_91c4f2d22a3b.
  ///
  /// In en, this message translates to:
  /// **'Search name, email, or business'**
  String get legacy_91c4f2d22a3b;

  /// No description provided for @legacy_53cc3db97d18.
  ///
  /// In en, this message translates to:
  /// **'Search payments'**
  String get legacy_53cc3db97d18;

  /// No description provided for @legacy_8ccb6303d68b.
  ///
  /// In en, this message translates to:
  /// **'Search properties'**
  String get legacy_8ccb6303d68b;

  /// No description provided for @legacy_efa700f6ca99.
  ///
  /// In en, this message translates to:
  /// **'Search tenants'**
  String get legacy_efa700f6ca99;

  /// No description provided for @legacy_17f924241968.
  ///
  /// In en, this message translates to:
  /// **'Search workspace'**
  String get legacy_17f924241968;

  /// No description provided for @legacy_4dd032aa5e1f.
  ///
  /// In en, this message translates to:
  /// **'Security deposit'**
  String get legacy_4dd032aa5e1f;

  /// No description provided for @legacy_55c6ce44991f.
  ///
  /// In en, this message translates to:
  /// **'Security deposit (UGX)'**
  String get legacy_55c6ce44991f;

  /// No description provided for @legacy_00cd5e6e13bd.
  ///
  /// In en, this message translates to:
  /// **'Seeded subscriber mix'**
  String get legacy_00cd5e6e13bd;

  /// No description provided for @legacy_147534e692b3.
  ///
  /// In en, this message translates to:
  /// **'Seeded subscribers'**
  String get legacy_147534e692b3;

  /// No description provided for @legacy_3a69f897298e.
  ///
  /// In en, this message translates to:
  /// **'Send request'**
  String get legacy_3a69f897298e;

  /// No description provided for @legacy_178e55753cfa.
  ///
  /// In en, this message translates to:
  /// **'Server audit log, newest first'**
  String get legacy_178e55753cfa;

  /// No description provided for @legacy_e0ebfc14e117.
  ///
  /// In en, this message translates to:
  /// **'Server plan catalog'**
  String get legacy_e0ebfc14e117;

  /// No description provided for @legacy_d0e3ac194ca5.
  ///
  /// In en, this message translates to:
  /// **'Server-owned audit log — append-only, admin-read-only'**
  String get legacy_d0e3ac194ca5;

  /// No description provided for @legacy_270a68904b9a.
  ///
  /// In en, this message translates to:
  /// **'Service charges'**
  String get legacy_270a68904b9a;

  /// No description provided for @legacy_cce5eda33f91.
  ///
  /// In en, this message translates to:
  /// **'Service status'**
  String get legacy_cce5eda33f91;

  /// No description provided for @legacy_482893bc419f.
  ///
  /// In en, this message translates to:
  /// **'Service status has to come from real probes. Reporting everything'**
  String get legacy_482893bc419f;

  /// No description provided for @legacy_bd6f8dc16903.
  ///
  /// In en, this message translates to:
  /// **'Set up a landlord workspace'**
  String get legacy_bd6f8dc16903;

  /// No description provided for @legacy_e73018efbee0.
  ///
  /// In en, this message translates to:
  /// **'Share of the demo fixtures by tier'**
  String get legacy_e73018efbee0;

  /// No description provided for @legacy_ce4050732e69.
  ///
  /// In en, this message translates to:
  /// **'Shared documents'**
  String get legacy_ce4050732e69;

  /// No description provided for @legacy_34d7fc9ae5e2.
  ///
  /// In en, this message translates to:
  /// **'Shop G2'**
  String get legacy_34d7fc9ae5e2;

  /// No description provided for @legacy_0d142aa8971a.
  ///
  /// In en, this message translates to:
  /// **'Short title'**
  String get legacy_0d142aa8971a;

  /// No description provided for @legacy_e1c9ee7b6ef7.
  ///
  /// In en, this message translates to:
  /// **'Show all payments'**
  String get legacy_e1c9ee7b6ef7;

  /// No description provided for @legacy_89cb6802d43a.
  ///
  /// In en, this message translates to:
  /// **'Show all requests'**
  String get legacy_89cb6802d43a;

  /// No description provided for @legacy_cb076376cef4.
  ///
  /// In en, this message translates to:
  /// **'Shown as selectable during subscription'**
  String get legacy_cb076376cef4;

  /// No description provided for @legacy_9e019f6440b4.
  ///
  /// In en, this message translates to:
  /// **'Sign in to manage your Nyumba workspace.'**
  String get legacy_9e019f6440b4;

  /// No description provided for @legacy_3272427a6298.
  ///
  /// In en, this message translates to:
  /// **'Smoking policy'**
  String get legacy_3272427a6298;

  /// No description provided for @legacy_172b9808872e.
  ///
  /// In en, this message translates to:
  /// **'Sockets on the living-room wall stopped working overnight.'**
  String get legacy_172b9808872e;

  /// No description provided for @legacy_787f7e4471dc.
  ///
  /// In en, this message translates to:
  /// **'Staff actions are server-validated and audited.'**
  String get legacy_787f7e4471dc;

  /// No description provided for @legacy_8a386dd14cb9.
  ///
  /// In en, this message translates to:
  /// **'Street address'**
  String get legacy_8a386dd14cb9;

  /// No description provided for @legacy_917e144e4bc3.
  ///
  /// In en, this message translates to:
  /// **'Submit request'**
  String get legacy_917e144e4bc3;

  /// No description provided for @legacy_783ba425ad70.
  ///
  /// In en, this message translates to:
  /// **'Subscription data is unavailable'**
  String get legacy_783ba425ad70;

  /// No description provided for @legacy_11170cb2d277.
  ///
  /// In en, this message translates to:
  /// **'Subscription records are server-owned and need a'**
  String get legacy_11170cb2d277;

  /// No description provided for @legacy_1f7b8eb9b0b9.
  ///
  /// In en, this message translates to:
  /// **'Subscription tiers'**
  String get legacy_1f7b8eb9b0b9;

  /// No description provided for @legacy_0217d7fc98ed.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions apply to landlords and property managers'**
  String get legacy_0217d7fc98ed;

  /// No description provided for @legacy_cd55f733e210.
  ///
  /// In en, this message translates to:
  /// **'Super Admin'**
  String get legacy_cd55f733e210;

  /// No description provided for @legacy_f742675fb4b0.
  ///
  /// In en, this message translates to:
  /// **'Super Admin accounts'**
  String get legacy_f742675fb4b0;

  /// No description provided for @legacy_d48725356945.
  ///
  /// In en, this message translates to:
  /// **'Suspend this landlord?'**
  String get legacy_d48725356945;

  /// No description provided for @legacy_8a046cc90ab0.
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get legacy_8a046cc90ab0;

  /// No description provided for @legacy_982649422d26.
  ///
  /// In en, this message translates to:
  /// **'System health'**
  String get legacy_982649422d26;

  /// No description provided for @legacy_5a40ce2d274f.
  ///
  /// In en, this message translates to:
  /// **'Target landlord account ID'**
  String get legacy_5a40ce2d274f;

  /// No description provided for @legacy_b6bd706e204a.
  ///
  /// In en, this message translates to:
  /// **'Tenant and rental space'**
  String get legacy_b6bd706e204a;

  /// No description provided for @legacy_54cf074e001d.
  ///
  /// In en, this message translates to:
  /// **'Tenant directory'**
  String get legacy_54cf074e001d;

  /// No description provided for @legacy_c1eddf81e652.
  ///
  /// In en, this message translates to:
  /// **'Tenant notice'**
  String get legacy_c1eddf81e652;

  /// No description provided for @legacy_704edabce59b.
  ///
  /// In en, this message translates to:
  /// **'Tenant records'**
  String get legacy_704edabce59b;

  /// No description provided for @legacy_149e3a879b97.
  ///
  /// In en, this message translates to:
  /// **'Tenant saved locally. Invitation will send when online.'**
  String get legacy_149e3a879b97;

  /// No description provided for @legacy_1b3e8afa6b85.
  ///
  /// In en, this message translates to:
  /// **'Tenants are added by their landlord — there is'**
  String get legacy_1b3e8afa6b85;

  /// No description provided for @legacy_75c52fdd8938.
  ///
  /// In en, this message translates to:
  /// **'The approval queue reads server-owned landlord accounts, which'**
  String get legacy_75c52fdd8938;

  /// No description provided for @legacy_ee18a9b760a2.
  ///
  /// In en, this message translates to:
  /// **'The archive request will be queued. The property stays marked as'**
  String get legacy_ee18a9b760a2;

  /// No description provided for @legacy_15817c5eff46.
  ///
  /// In en, this message translates to:
  /// **'The directory reads live from the server and needs a'**
  String get legacy_15817c5eff46;

  /// No description provided for @legacy_64334fe2be61.
  ///
  /// In en, this message translates to:
  /// **'The kitchen mixer tap drips continuously, even when fully closed.'**
  String get legacy_64334fe2be61;

  /// No description provided for @legacy_b84983720252.
  ///
  /// In en, this message translates to:
  /// **'The listing stays marked as unpublishing until the server removes'**
  String get legacy_b84983720252;

  /// No description provided for @legacy_2d990810a60d.
  ///
  /// In en, this message translates to:
  /// **'The live directory could not be read:'**
  String get legacy_2d990810a60d;

  /// No description provided for @legacy_d8a9177cb262.
  ///
  /// In en, this message translates to:
  /// **'The lock barrel turns without engaging; needs refitting.'**
  String get legacy_d8a9177cb262;

  /// No description provided for @legacy_ea34669953e9.
  ///
  /// In en, this message translates to:
  /// **'The manager must confirm before entry'**
  String get legacy_ea34669953e9;

  /// No description provided for @legacy_57e354c7e52e.
  ///
  /// In en, this message translates to:
  /// **'The property manager will be notified. You can create a new request'**
  String get legacy_57e354c7e52e;

  /// No description provided for @legacy_008f6716b258.
  ///
  /// In en, this message translates to:
  /// **'The rental space stays marked as archive pending until the server'**
  String get legacy_008f6716b258;

  /// No description provided for @legacy_429aec7053a5.
  ///
  /// In en, this message translates to:
  /// **'The request saves locally and will send to your'**
  String get legacy_429aec7053a5;

  /// No description provided for @legacy_9d16ef9d2939.
  ///
  /// In en, this message translates to:
  /// **'The server directory could not be read:'**
  String get legacy_9d16ef9d2939;

  /// No description provided for @legacy_7776e3d81010.
  ///
  /// In en, this message translates to:
  /// **'The shower drain backs up after a few minutes of use.'**
  String get legacy_7776e3d81010;

  /// No description provided for @legacy_3768651aa270.
  ///
  /// In en, this message translates to:
  /// **'These listings are saved on your device, so you can keep browsing offline.'**
  String get legacy_3768651aa270;

  /// No description provided for @legacy_40eb8b4fccc0.
  ///
  /// In en, this message translates to:
  /// **'These rules apply to every tier and cannot be paywalled'**
  String get legacy_40eb8b4fccc0;

  /// No description provided for @legacy_65dff1bed1b6.
  ///
  /// In en, this message translates to:
  /// **'This creates a local draft and queues it for server'**
  String get legacy_65dff1bed1b6;

  /// No description provided for @legacy_6a623bb1209c.
  ///
  /// In en, this message translates to:
  /// **'This home is no longer available'**
  String get legacy_6a623bb1209c;

  /// No description provided for @legacy_fd787ef3d46c.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get legacy_fd787ef3d46c;

  /// No description provided for @legacy_fef68e8a5c7e.
  ///
  /// In en, this message translates to:
  /// **'This notification could not be marked as read.'**
  String get legacy_fef68e8a5c7e;

  /// No description provided for @legacy_6e793c13afe4.
  ///
  /// In en, this message translates to:
  /// **'This request can be saved without a connection and'**
  String get legacy_6e793c13afe4;

  /// No description provided for @legacy_d42c8d4256ec.
  ///
  /// In en, this message translates to:
  /// **'Track rent, record receipts, and keep every balance honest.'**
  String get legacy_d42c8d4256ec;

  /// No description provided for @legacy_3c476ad4566b.
  ///
  /// In en, this message translates to:
  /// **'Triage tenant requests and keep every repair moving.'**
  String get legacy_3c476ad4566b;

  /// No description provided for @legacy_83763011a21b.
  ///
  /// In en, this message translates to:
  /// **'Try another filter or report a new issue.'**
  String get legacy_83763011a21b;

  /// No description provided for @legacy_066acc86a2b2.
  ///
  /// In en, this message translates to:
  /// **'Try another search, category, or starred filter.'**
  String get legacy_066acc86a2b2;

  /// No description provided for @legacy_b85c6a89c7d4.
  ///
  /// In en, this message translates to:
  /// **'UGX 1M–1.4M'**
  String get legacy_b85c6a89c7d4;

  /// No description provided for @legacy_874356efc1a1.
  ///
  /// In en, this message translates to:
  /// **'Under UGX 1M'**
  String get legacy_874356efc1a1;

  /// No description provided for @legacy_86172af572ca.
  ///
  /// In en, this message translates to:
  /// **'Unpublish request saved locally and awaiting server confirmation.'**
  String get legacy_86172af572ca;

  /// No description provided for @legacy_28d3668a56f7.
  ///
  /// In en, this message translates to:
  /// **'Updates are kept on this device and sync when you reconnect.'**
  String get legacy_28d3668a56f7;

  /// No description provided for @legacy_0200725fbeeb.
  ///
  /// In en, this message translates to:
  /// **'Updates shared by your manager'**
  String get legacy_0200725fbeeb;

  /// No description provided for @legacy_a1e965e236ec.
  ///
  /// In en, this message translates to:
  /// **'Urgent (3)'**
  String get legacy_a1e965e236ec;

  /// No description provided for @legacy_9db22b50e531.
  ///
  /// In en, this message translates to:
  /// **'Use the application form to send your details securely. Direct contact is not part of the public listing.'**
  String get legacy_9db22b50e531;

  /// No description provided for @legacy_d1a70b08464e.
  ///
  /// In en, this message translates to:
  /// **'Used for routed enquiries; not shown publicly'**
  String get legacy_d1a70b08464e;

  /// No description provided for @legacy_cd877a11b45e.
  ///
  /// In en, this message translates to:
  /// **'User accounts'**
  String get legacy_cd877a11b45e;

  /// No description provided for @legacy_7967e089a7b9.
  ///
  /// In en, this message translates to:
  /// **'User ID'**
  String get legacy_7967e089a7b9;

  /// No description provided for @legacy_ee64c15b73bb.
  ///
  /// In en, this message translates to:
  /// **'Users & access'**
  String get legacy_ee64c15b73bb;

  /// No description provided for @legacy_7e2c95f53b94.
  ///
  /// In en, this message translates to:
  /// **'Vacant rental space'**
  String get legacy_7e2c95f53b94;

  /// No description provided for @legacy_e82390d9bbc5.
  ///
  /// In en, this message translates to:
  /// **'Verified subscribed landlord'**
  String get legacy_e82390d9bbc5;

  /// No description provided for @legacy_bb265946234f.
  ///
  /// In en, this message translates to:
  /// **'Verify your email'**
  String get legacy_bb265946234f;

  /// No description provided for @legacy_b8fb93f81c2e.
  ///
  /// In en, this message translates to:
  /// **'Video or virtual-tour URL (optional)'**
  String get legacy_b8fb93f81c2e;

  /// No description provided for @legacy_4071433234fe.
  ///
  /// In en, this message translates to:
  /// **'View account'**
  String get legacy_4071433234fe;

  /// No description provided for @legacy_b9db058fd79e.
  ///
  /// In en, this message translates to:
  /// **'View all activity'**
  String get legacy_b9db058fd79e;

  /// No description provided for @legacy_4eaca8aee795.
  ///
  /// In en, this message translates to:
  /// **'View all operations'**
  String get legacy_4eaca8aee795;

  /// No description provided for @legacy_f86daaf6282e.
  ///
  /// In en, this message translates to:
  /// **'View all payments'**
  String get legacy_f86daaf6282e;

  /// No description provided for @legacy_85f341899f26.
  ///
  /// In en, this message translates to:
  /// **'View plan'**
  String get legacy_85f341899f26;

  /// No description provided for @legacy_b9be4291bd73.
  ///
  /// In en, this message translates to:
  /// **'View public listing'**
  String get legacy_b9be4291bd73;

  /// No description provided for @legacy_82f471a6c6e7.
  ///
  /// In en, this message translates to:
  /// **'View tenant details'**
  String get legacy_82f471a6c6e7;

  /// No description provided for @legacy_fb0bb746dde7.
  ///
  /// In en, this message translates to:
  /// **'View, print, and keep important tenancy records together.'**
  String get legacy_fb0bb746dde7;

  /// No description provided for @legacy_d420eccfae3c.
  ///
  /// In en, this message translates to:
  /// **'Viewing instructions'**
  String get legacy_d420eccfae3c;

  /// No description provided for @legacy_5ff39c8b280a.
  ///
  /// In en, this message translates to:
  /// **'Visible CRUD permissions for every platform resource'**
  String get legacy_5ff39c8b280a;

  /// No description provided for @legacy_4647b65986bf.
  ///
  /// In en, this message translates to:
  /// **'Water not draining in bathroom'**
  String get legacy_4647b65986bf;

  /// No description provided for @legacy_fe2311bf2470.
  ///
  /// In en, this message translates to:
  /// **'What needs attention?'**
  String get legacy_fe2311bf2470;

  /// No description provided for @legacy_6eaee82d3fa6.
  ///
  /// In en, this message translates to:
  /// **'Work order actions'**
  String get legacy_6eaee82d3fa6;

  /// No description provided for @legacy_53e6cdc30765.
  ///
  /// In en, this message translates to:
  /// **'you@example.com'**
  String get legacy_53e6cdc30765;

  /// No description provided for @legacy_b4727df40f3a.
  ///
  /// In en, this message translates to:
  /// **'Your access & operations'**
  String get legacy_b4727df40f3a;

  /// No description provided for @legacy_eb7e1337d46a.
  ///
  /// In en, this message translates to:
  /// **'Your application is safely stored on this device and queued for delivery. Nyumba will retry automatically when you are online.'**
  String get legacy_eb7e1337d46a;

  /// No description provided for @legacy_d7737f8d47b3.
  ///
  /// In en, this message translates to:
  /// **'Your existing local data is still available.'**
  String get legacy_d7737f8d47b3;

  /// No description provided for @legacy_b9e4df82e8d5.
  ///
  /// In en, this message translates to:
  /// **'Your home'**
  String get legacy_b9e4df82e8d5;

  /// No description provided for @legacy_77a18e56681b.
  ///
  /// In en, this message translates to:
  /// **'Your home, balance, and documents will appear after your'**
  String get legacy_77a18e56681b;

  /// No description provided for @legacy_e39a7432989d.
  ///
  /// In en, this message translates to:
  /// **'Your landlord account is awaiting review. You can prepare your'**
  String get legacy_e39a7432989d;

  /// No description provided for @legacy_b65fdf85d685.
  ///
  /// In en, this message translates to:
  /// **'Your lease details will appear after your landlord'**
  String get legacy_b65fdf85d685;

  /// No description provided for @legacy_dadbc887f26c.
  ///
  /// In en, this message translates to:
  /// **'Your portfolio at a glance'**
  String get legacy_dadbc887f26c;

  /// No description provided for @legacy_0b541593e3a7.
  ///
  /// In en, this message translates to:
  /// **'Your properties'**
  String get legacy_0b541593e3a7;

  /// No description provided for @legacy_ef5d3aa3c485.
  ///
  /// In en, this message translates to:
  /// **'Your property manager will prepare this document and share it here.'**
  String get legacy_ef5d3aa3c485;

  /// No description provided for @legacy_dc7cb9e237d1.
  ///
  /// In en, this message translates to:
  /// **'Your workspace stays available offline after your first secure sign-in.'**
  String get legacy_dc7cb9e237d1;

  /// No description provided for @welcomeBackName.
  ///
  /// In en, this message translates to:
  /// **'Welcome back, {name}.'**
  String welcomeBackName(Object name);

  /// No description provided for @welcomeName.
  ///
  /// In en, this message translates to:
  /// **'Welcome, {name}'**
  String welcomeName(Object name);

  /// No description provided for @editName.
  ///
  /// In en, this message translates to:
  /// **'Edit {name}'**
  String editName(Object name);

  /// No description provided for @archiveNameQuestion.
  ///
  /// In en, this message translates to:
  /// **'Archive {name}?'**
  String archiveNameQuestion(Object name);

  /// No description provided for @addRentalSpaceToName.
  ///
  /// In en, this message translates to:
  /// **'Add rental space to {name}'**
  String addRentalSpaceToName(Object name);

  /// No description provided for @archiveQueuedName.
  ///
  /// In en, this message translates to:
  /// **'Archive queued for {name}; awaiting server confirmation.'**
  String archiveQueuedName(Object name);

  /// No description provided for @savedLocalDraft.
  ///
  /// In en, this message translates to:
  /// **'{title} saved as a local draft.'**
  String savedLocalDraft(Object title);

  /// No description provided for @rentalSpacesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} rental spaces'**
  String rentalSpacesCount(Object count);

  /// No description provided for @rentalSpacesLimit.
  ///
  /// In en, this message translates to:
  /// **'{count} of {limit} rental spaces'**
  String rentalSpacesLimit(Object count, Object limit);

  /// No description provided for @listingActiveUntil.
  ///
  /// In en, this message translates to:
  /// **'Listing active until {date}'**
  String listingActiveUntil(Object date);

  /// No description provided for @endsOn.
  ///
  /// In en, this message translates to:
  /// **'Ends {date}'**
  String endsOn(Object date);

  /// No description provided for @recordMethodPayment.
  ///
  /// In en, this message translates to:
  /// **'Record {method} payment'**
  String recordMethodPayment(Object method);

  /// No description provided for @recordMonthRentPayment.
  ///
  /// In en, this message translates to:
  /// **'Record {month} rent payment'**
  String recordMonthRentPayment(Object month);

  /// No description provided for @documentsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} documents'**
  String documentsCount(Object count);

  /// No description provided for @verifiedDigitalCopy.
  ///
  /// In en, this message translates to:
  /// **'Verified digital copy • {reference}'**
  String verifiedDigitalCopy(Object reference);

  /// No description provided for @unreadTitle.
  ///
  /// In en, this message translates to:
  /// **'Unread: {title}'**
  String unreadTitle(Object title);

  /// No description provided for @cloudLiveMessage.
  ///
  /// In en, this message translates to:
  /// **'Connected to Nyumba cloud. Showing live data.'**
  String get cloudLiveMessage;

  /// No description provided for @cloudConnectingMessage.
  ///
  /// In en, this message translates to:
  /// **'Contacting Nyumba cloud…'**
  String get cloudConnectingMessage;

  /// No description provided for @cloudOfflineMessage.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach Nyumba cloud. Showing data saved on this device.'**
  String get cloudOfflineMessage;

  /// No description provided for @cloudDemoMessage.
  ///
  /// In en, this message translates to:
  /// **'Not connected to a Nyumba project. These are local demo records.'**
  String get cloudDemoMessage;

  /// No description provided for @locationAvailableOnRequest.
  ///
  /// In en, this message translates to:
  /// **'Location available on request'**
  String get locationAvailableOnRequest;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en', 'lg', 'sw'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
    case 'lg':
      return AppLocalizationsLg();
    case 'sw':
      return AppLocalizationsSw();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
