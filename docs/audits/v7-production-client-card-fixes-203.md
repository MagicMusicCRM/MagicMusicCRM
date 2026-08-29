# Production evidence — client card fixes 1.5.23+203

Date: 2026-08-30

Release commit: `4804da078efeddb4b6538de187321a2e79d55181`

Tag: `v1.5.23`

Server image: `magicmusiccrm-server:1.5.23-203-4804da078efe`

Image ID: `sha256:3146ffe0e49b981438e711be046b99e2b1b286312095f58c5b209bb23bd4450c`

Migration: `0144_direct_subscription_payment_isolation`

## Released behavior

- Client card email duplicate conflicts return a Russian business error instead
  of HTTP 500. Direction remains a canonical system field, while system and
  legacy definitions are excluded from the additional-fields editor and typed
  custom-field payload.
- A subscription sale records payment directly against that subscription. The
  linked payment, obligation and corrections no longer alter the personal
  account projection; ordinary account top-ups remain unchanged.
- `Доступ в приложение -> Пригласить` uses the durable email outbox and the
  current card email. The message contains an Android Google Play action and an
  iOS coming-soon action until an App Store URL is configured.
- Subscription and progress cards use one responsive equal-height row that
  remeasures after asynchronous content changes. The sale flow keeps one
  `Оплатить` action.

## Verification before cutover

- Full Flutter suite returned `success=true` in 206 seconds; targeted card,
  subscription and homework matrix passed `112/112`; `flutter analyze` passed.
- Backend passed `268/268` suites and `3384/3384` tests with 4 GB Node heap;
  typecheck and Nest production build passed.
- Windows Release, Setup, signed Android APK and signed AAB builds passed. APK
  is package `magic.crm`, version code `203`, version `1.5.23`, target SDK 36,
  and verifies with APK Signature Scheme v2.
- RepoWise index update and `git diff --check` passed.

## Backup and rollback

- Pre-cutover encrypted backup
  `magicmusiccrm-staging-20260829T211435Z.tgz.enc`, `195360` bytes, SHA-256
  `eba9c08a3ed95e86d8d18290ef12f448585fa079579cce141fa902ae23411bf3`.
- Post-deploy encrypted backup
  `magicmusiccrm-staging-20260829T211837Z.tgz.enc`, `195344` bytes, SHA-256
  `cfe8e10bfb21b101554cfcf513c1b236adb77515cde605abc3e8035b9c726e85`.
- Both backups were copied off-host to
  `C:\Users\Alinka\Documents\MagicMusicCRM Backups\2026-08-30` with matching
  hashes and passed isolated candidate/rollback restore compatibility.
- Immediate server rollback is `magicmusiccrm-server:1.5.22-202-68a63527` on
  retained migration `0144`. Client rollback manifests are in
  `/opt/magicmusiccrm/releases/client-manifest-rollback-202-20260829T213200Z`.

## Production verification

`DEPLOY_API_RELEASE|PASS` selected the exact revision and migration. Public
readiness is healthy; API restart is `0`, OOM is `false`, platform outbox is
`0/0`, two V7 reconciliations returned `issues=[]`, and recent API error lines
and exact Caddy 5xx are `0`. The account projection has zero obligation rows;
two existing subscription-linked payments remain in append-only history but
are isolated from the personal account.

Resend is configured. The only exhausted email row predates this release
(2026-08-13); later OTP deliveries are sent. Invitation rendering and delivery
fallback are covered by the exact-image test suite. No invitation was sent to a
real customer during automated verification.

An initial candidate container briefly used an incorrect full OCI revision
label with the same `4804da07` prefix. The source archive was correct. Before
client publication it was replaced through the guarded deploy path with image
`3146ffe0...`; the final OCI label, `DEPLOYED_REVISION`, Git tag and checkout
all equal `4804da078efeddb4b6538de187321a2e79d55181`.

## Client publication

Both manifests point to `1.5.23+203`. Public HTTPS hashes match local artifacts:

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| Windows ZIP | 19786777 | `3471f02a9009d1084c04b28a0382e356a0b52b6071ac3f73904864f91b7b709d` |
| Windows Setup | 15559951 | `ee1d0d68d69d8f004cf402bdd063350103be3f61b3cdef8e890ca29c78920af6` |
| Android APK | 87679804 | `58de3eb66e3119154d411f7380fd45638cdd45b08aff0e6b023676c7af546823` |
| Android AAB | 61267988 | `de19447bb42fc856d3c373b12419df0abb091e8313b8ace04fda96c1407cef80` |

GitHub Release: `https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.23`.
