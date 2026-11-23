# iOS journey tracking and Firebase notifications

This feature mirrors the Android `catenary-compose` journey notifier protocol
against `https://notify1.catenarymaps.org` and supports an independent active
journey, a compact guidance bar, saved journey alerts, and transport-mode filters.

## Firebase and Apple setup (required before push works)

1. In the **same Firebase project** used for the Android application and
   `journey-notifier`, add an **Apple app** with bundle ID
   `org.catenarymaps.maps`. Download that app's **GoogleService-Info.plist**
   and add it to the Xcode target's copied resources. This file is an iOS
   client configuration, **not** a Firebase Admin service account.
2. Under Firebase Console → Cloud Messaging, upload an APNs authentication
   key for the Apple developer team and configure its Key ID / Team ID.
3. In Xcode → Signing & Capabilities, verify **Push Notifications** and
   **Background Modes → Remote notifications** are available for both
   development and distribution signing profiles. Provisioning must authorize
   the `aps-environment` entitlement.
4. The Xcode project includes `FirebaseCore` and `FirebaseMessaging`
   through Swift Package Manager. The app configures Firebase only when the
   actual `GoogleService-Info.plist` is bundled; otherwise the rest of the
   journey planner remains operational without push registration.
5. `JourneyNotifierBaseURL` in `CatenaryInfo.plist` defaults to
   `https://notify1.catenarymaps.org`; use an HTTPS endpoint providing
   `POST /v1/devices`, `PUT /v1/devices/{deviceId}`, and
   `POST /v1/journeys/sync`.

Never add a Firebase Admin service-account private key or APNs private key to
this repository. Those credentials remain in the backend or Firebase Console.

## Runtime lifecycle

- At launch, an available Firebase client is configured, the app registers
  for APNs, and the resulting APNs device token is forwarded to FCM.
- On FCM token acquisition or rotation, `JourneyNotifications` registers
  or updates the device. The server-issued device ID and bearer secret are
  stored in Keychain, restricted to the device.
- Saving/removing a bookmark or starting/ending an active journey enqueues
  full-set reconciliation of all saved journeys plus the active journey.
  The notifier deduplicates identities and expects the same leg schema as
  Android (scheduled/expected times, platform, transfer budget, stop/trip IDs).
- The first Start/bookmark requests user permission for visible alerts.
  Foreground notifications are displayed through the UserNotifications
  delegate; tapping a known active journey opens independent active details,
  otherwise it opens saved journeys.
- Active guidance survives navigation and process restarts via a local
  itinerary snapshot. The in-app bar is shown when the trip has begun, or
  within three hours of departure when the user is within 5 km of its origin.
  Timing and progress are derived from itinerary times; no background GPS
  entitlement is requested.
- Transport filtering is sent in the exact OJP-style
  `modeAndModeOfOperationFilter` request field. Filtering off omits the field,
  while a filter with nothing selected includes then excludes TRAIN.

## iOS background behavior

Android's foreground-service notification has no direct iOS equivalent.
The iOS in-app guidance and active-journey screen update while displayed,
and FCM/APNs delivers server-driven alerts when backgrounded. A persistent
Lock Screen progress interface requires a separately provisioned ActivityKit
Live Activity and widget extension; this PR does **not** claim to provide
continuous background progress updates.

iOS may defer or coalesce background remote notifications. Do not rely on
silent pushes for immediate background processing; the backend is responsible
for timely alerts and subscription lifecycle.

## Manual verification

1. Run on a **physical iPhone** signed with Push Notifications. Confirm FCM
   registration and successful device sync on the notifier.
2. Save a journey, revoke a bookmark, start a different journey, and end
   tracking; verify the server receives the correct complete sets.
3. Revoke notification permission and ensure journey planning still works.
4. Rotate the FCM token, relaunch, and confirm credentials are reused.
5. Send delay, cancellation, and platform-change FCM messages in foreground
   and background; verify no duplicated foreground banner and correct tap path.
6. Verify Start/End state after relaunch and in list/map views, all trip-switch
   confirmations, and portrait/landscape/tablet bottom-bar positioning.
7. Verify the eight modes, Coach as a separate checkbox, reset behavior,
   empty-filter encoding, and legacy sessions without filter fields.

The GitHub CI checks and physical-device push/provisioning verification are
separate; a successful source build alone does not prove APNs delivery.
