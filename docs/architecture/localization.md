# Localization contract

Nyumba supports English (`en`), Luganda (`lg`), Kiswahili (`sw`), and Arabic
(`ar`) on web, Android, and iOS. The supported set is a versioned product and
backend contract; unknown or missing locale values fall back to English.

## Sources and runtime behavior

- `assets/l10n/app_en.arb` is the source catalog. The `lg`, `sw`, and `ar`
  catalogs must keep exact message-key parity with it.
- Flutter generates typed `AppLocalizations` classes through `l10n.yaml`.
  New features use generated getters, ICU plurals/selects, and named
  placeholders. A localized `Text`/`Tooltip` bridge covers existing literal
  copy while it is migrated.
- Placeholder values are data and remain unchanged. Names, property/unit
  labels, user-authored notices, descriptions, enquiries, and application
  messages are not automatically translated.
- The app registers Luganda month and weekday names because `intl` does not
  bundle an `lg` calendar. All other date symbols come from CLDR. Currency
  remains UGX and amounts remain integer minor units in every language.

## Selection and persistence

The language menu is available before sign-in and in the authenticated shell
and profile settings. Selection applies immediately. A best-effort secure
device preference controls signed-out/first-run screens; an authenticated
selection is also saved atomically with the local `user_profiles` record and
its `profile.update` outbox intent. On a new device, the validated server
profile locale is used after session resolution. Precedence is:

1. current local authenticated profile;
2. locale on the resolved server session;
3. secure device preference;
4. English.

Because server-rendered notifications are localized to the `locale` on the
user document, a language chosen while signed out must still reach the account.
When a session first resolves, the app reconciles the effective language to the
server: if it diverges from the stored profile locale, it is persisted through
the same `profile.update` intent (skipping anonymous sessions, and never
writing English over an account that simply has no preference yet). Without
this, a user who picked, say, Kiswahili on the sign-in screen would read the
app in Kiswahili but receive English notifications.

## RTL and accessibility

Arabic sets Flutter and generated PDFs to right-to-left. Layout uses
directional start/end padding, alignment, positioning, borders, and table-cell
alignment. User-entered mixed-direction text remains data. Visible copy,
semantic labels, form labels/errors, tooltips, and built-in controls must all
have localized equivalents. Luganda supplies a small Material localization
delegate for controls Flutter does not provide for `lg`.

## Server output and documents

Notification jobs carry template keys rather than rendered English. Delivery
reads the recipient locale and renders both the durable inbox row and FCM push
from the same four-language template, with English fallback.

Printable documents receive the active language explicitly. PDF labels,
statuses, dates, and controlled document types are localized; user/property
data is preserved. Noto Sans and Noto Naskh Arabic are embedded under the SIL
Open Font License so output works offline and Arabic glyphs shape correctly.

## Quality gate

Automated tests enforce catalog parity, non-empty/clean Unicode messages,
dynamic placeholder preservation, Luganda calendar data, Arabic RTL, localized
notification templates, profile locale sync, and Arabic PDF generation. The
PDF fixture is rendered and visually inspected when document layout changes.
Machine translations remain drafts: a fluent reviewer must approve legal,
financial, safety, tenancy, subscription, and billing wording before a
production release.
