## Growth Flutter SDK 🆙📊📈 

Flutter package to initialize and orchestrate Firebase (Analytics, Crashlytics, Remote Config, Auth), Adjust, and RevenueCat. It ensures device-based Firebase login, wires identities across SDKs, and enables event attribution to the correct user.

### What you get
- Firebase: Analytics, Crashlytics, Remote Config, Authentication
- Adjust: user acquisition and attribution
- RevenueCat: subscription management and event forwarding
- Identity linking: Firebase login via device-based email, RevenueCat user identification, Adjust ADID bridging

---

## Installation

Add to your app’s `pubspec.yaml` (this package already declares the required dependencies for consumers):

```yaml
dependencies:
  growth_flutter_sdk: ^0.0.1
```

Then complete platform setup:

### Firebase setup
- iOS: Add `GoogleService-Info.plist` to Runner target. Enable Crashlytics/Analytics in Firebase console.
- Android: Add `google-services.json` to `app/`. Apply the Google Services Gradle plugin in your app module.
- Ensure Crashlytics Gradle tasks are enabled for release builds.

Official docs: `https://firebase.flutter.dev/docs/overview`

### Adjust setup
- Create an Adjust app and get your `appToken`.
- iOS: Add SKAdNetwork IDs for Adjust in `Info.plist` and configure App Tracking Transparency as needed.
- Android: Follow Adjust Android SDK manifest/proguard integration guidance.

Official docs: `https://github.com/adjust/flutter_sdk`

### RevenueCat setup
- Create a project and obtain API keys for iOS and Android.
- Enable integrations in the RevenueCat dashboard:
  - Firebase (Cloud part is NOT required per your spec)
  - Adjust (server-side connection)

Official docs: `https://www.revenuecat.com/docs`

---

## Usage

Call initialize early in `main()` (before `runApp`):

```dart
import 'package:flutter/widgets.dart';
import 'package:growth_flutter_sdk/growth_flutter_sdk.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await GrowthSdk.initialize(
    GrowthSdkConfig(
      revenueCatApiKeyAndroid: 'rc_public_sdk_key_android',
      revenueCatApiKeyIos: 'rc_public_sdk_key_ios',
      adjustAppToken: 'YOUR_ADJUST_APP_TOKEN',
      adjustEnvironment: GrowthAdjustEnvironment.production, // or sandbox
      deviceEmailDomain: 'app.com',
      enableDebugLogs: true,
    ),
  );

  // Optional: access resolved identities
  final ids = GrowthSdk.identity;
  // ids?.firebaseUserId, ids?.firebaseAppInstanceId, ids?.adjustAdid, etc.

  runApp(const MyApp());
}
```

### Purchases & offerings
```dart
// List offerings/packages
final offerings = await GrowthSdk.getOfferings();
final current = offerings.current;
final packages = current?.availablePackages ?? [];

// Track paywall shown
await GrowthSdk.logPaywallShown(
  offeringId: current?.identifier ?? 'default',
  placementId: 'onboarding',
  variantId: 'v1',
);

// Track option selection (before purchase)
if (packages.isNotEmpty) {
  await GrowthSdk.logPaywallOptionSelected(packages.first,
      placementId: 'onboarding', variantId: 'v1');

  // Purchase
  final info = await GrowthSdk.purchasePackage(packages.first);
}

// Restore
final restored = await GrowthSdk.restorePurchases();
```

### Lifecycle auto-events
- Automatically triggered from RevenueCat `CustomerInfo` updates:
  - `growth_rc_trial_start`
  - `growth_rc_trial_converted`
  - `growth_rc_cancellation`
- Map to Adjust using `GrowthSdkConfig.adjustEventTokens`.

### Analytics helpers
```dart
// Screen view
await GrowthSdk.logScreenView(screenName: 'Paywall', screenClass: 'PaywallView');

// Page enter/exit
await GrowthSdk.logPageEnter('Onboarding');
await GrowthSdk.logPageExit('Onboarding');

// Button click
await GrowthSdk.logButtonClick('cta_subscribe', {'page': 'Paywall'});

// Generic event (no prefix)
await GrowthSdk.logAnalyticsEvent('custom_event', {'k': 'v'});
```

### Remote Config & A/B
```dart
// Typed getters
final title = GrowthSdk.getRemoteConfigString('paywall_title', defaultValue: 'Welcome');
final enabled = GrowthSdk.getRemoteConfigBool('paywall_enabled', defaultValue: true);
final variantWeight = GrowthSdk.getRemoteConfigDouble('exp_weight', defaultValue: 0.5);

// Force refresh on demand (e.g., after login)
final changed = await GrowthSdk.forceRemoteConfigRefresh();

// Sync experiment variant to analytics+RC attributes
await GrowthSdk.syncExperimentVariantFromRemoteConfig(
  rcKey: 'exp_paywall_variant',
  experimentKey: 'paywall',
);

// Or set explicitly
await GrowthSdk.setExperimentVariant('paywall', 'v2');
```

### Marketing/user attributes
```dart
await GrowthSdk.setMarketingAttributes(
  utmSource: 'fb', utmCampaign: 'black_friday', channel: 'paid', country: 'TR');

// Any custom
await GrowthSdk.setUserProperties({'cohort': 'Q1-2026'});
```

### Adjust mapping
- Use `GrowthSdkConfig.adjustEventTokens` to map purchase/restore/lifecycle events to Adjust.
- Revenue/currency is added to the Adjust event on successful purchase.

### Apple Search Ads (optional)
```dart
await GrowthSdk.enableAppleSearchAdsAttribution();
```

### Notes
- Remote Config fetch strategy: `fetchAndActivate` is called during init; use `forceRemoteConfigRefresh()` for on-demand updates.
- Telemetry/lifecycle analytics event names are logged with the `growth_` prefix by default. `logAnalyticsEvent` sends custom events as-is.
- Don’t forget to enable the corresponding integrations in Firebase/Adjust/RevenueCat dashboards.

### What initialize() does
- Initializes Firebase and Crashlytics handlers
- Fetches & activates Remote Config
- Generates/persists a device ID, builds `deviceId@domain` email
- Logs into Firebase Auth with email+stored-password (or anonymous fallback)
- Grabs Firebase Analytics App Instance ID
- Starts Adjust and fetches ADID
- Configures RevenueCat, logs in with Firebase UID (or device email), sets attributes:
  - `app_instance_id`
  - `adjust_adid`
  - `app_user_origin`

This allows RevenueCat events (rc_trial_start, purchases, renewals) to be tied to the same user identity and forwarded to Firebase Analytics and Adjust consistently.

---

## Notes & recommendations
- Consumers must provide Firebase config files and complete platform steps for Firebase, Adjust, and RevenueCat.
- If Apple Search Ads is enabled later, expose the token to RevenueCat using their recommended method. This package is structured to extend easily for ASA.
- Prefer calling `GrowthSdk.initialize` as early as possible so attribution and events start correctly.
