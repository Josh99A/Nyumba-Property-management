# CI/CD pipeline

The pipeline lives in [`.github/workflows/ci-cd.yml`](../.github/workflows/ci-cd.yml).

## What it does

| Trigger | Jobs |
| --- | --- |
| Pull request to `main` | Analyze + tests only |
| Push to `main` | Analyze + tests → deploy web to Firebase Hosting at <https://nyumba.online> (live) + build APK + build unsigned IPA (artifacts) |
| Push a tag `v*` (e.g. `v1.0.0`) | Analyze + tests → build APK + IPA → attach both to a GitHub Release |
| Manual (`workflow_dispatch`) | Same as push to `main` |

The APK and IPA from every `main` build are downloadable from the workflow
run's **Artifacts** section (kept 90 days). Tagged builds are attached
permanently to the GitHub Release.

The Hosting deployment waits for the backend deployment because `/`,
`/explore`, `/listing/*`, and `/sitemap.xml` rewrite to the `publicSeo`
Function. Keeping that order prevents a first deployment from publishing a
rewrite whose target does not exist yet.

## Required GitHub secrets

`lib/firebase_options.dart`, `android/app/google-services.json`, and
`.firebaserc` are gitignored, so CI recreates the first two from secrets.
Set these in **Repo → Settings → Secrets and variables → Actions**, or with
the `gh` commands below (run from the repo root on a machine that has the
files, e.g. this one).

### 1. `FIREBASE_OPTIONS_BASE64`

Base64 of `lib/firebase_options.dart`:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("lib/firebase_options.dart")) | gh secret set FIREBASE_OPTIONS_BASE64
```

### 2. `GOOGLE_SERVICES_JSON_BASE64`

Base64 of `android/app/google-services.json`:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("android/app/google-services.json")) | gh secret set GOOGLE_SERVICES_JSON_BASE64
```

### 3. `FIREBASE_SERVICE_ACCOUNT`

A Google Cloud service account key used by the hosting deploy action:

1. Open <https://console.firebase.google.com/project/nyumba-property-management/settings/serviceaccounts/adminsdk>
   and click **Generate new private key** (or create a dedicated service
   account with the *Firebase Hosting Admin* role in the Google Cloud
   console — preferred, least privilege).
2. Save the downloaded JSON, then:

```powershell
gh secret set FIREBASE_SERVICE_ACCOUNT < path\to\service-account.json
```

3. Delete the local JSON file afterwards.

### Secret-bound functions

Deploying a function that references a Secret Manager secret (for example
`RESEND_API_KEY` for Resend email) requires the deploy service account to
hold **Secret Manager Viewer** on that secret, or the deploy fails with
`secretmanager.secrets.get` denied. Grant it once per secret:

```powershell
gcloud secrets add-iam-policy-binding RESEND_API_KEY --project <project-id> --member="serviceAccount:<deploy-sa-email>" --role="roles/secretmanager.viewer"
```

The functions *runtime* service account separately needs
`roles/secretmanager.secretAccessor` on the secret; the Firebase CLI grants
that automatically on the first interactive local deploy.

## Notes

- **Android signing**: release APKs are currently signed with the debug key
  (see the TODO in `android/app/build.gradle.kts`). Fine for testing; set up
  a proper keystore before Play Store distribution.
- **iOS signing**: the runner has no Apple certificates, so the IPA is
  **unsigned** — it builds and packages correctly but cannot be installed on
  a device until signed (requires an Apple Developer account; certificates
  and provisioning profiles would be added as additional secrets).
- Flutter version is pinned via the `FLUTTER_VERSION` env var at the top of
  the workflow (currently 3.44.2, matching local development).
