## growth_flutter_sdk (Türkçe)

Flutter paketi; Firebase (Analytics, Crashlytics, Remote Config, Auth), Adjust ve RevenueCat’i başlatır ve orkestre eder. Cihaza dayalı Firebase oturum açmayı garanti eder, SDK’lar arasında kimlik eşleştirmesi yapar ve eventlerin doğru kullanıcıya atanmasını sağlar.

### Neler sunar
- Firebase: Analytics, Crashlytics, Remote Config, Authentication
- Adjust: kullanıcı edinimi ve atribüsyon takibi
- RevenueCat: abonelik yönetimi ve event forwarding
- Kimlik eşleştirme: cihaz e-postasıyla Firebase login, RevenueCat kullanıcı tanımlama, Adjust ADID köprüsü

---

## Kurulum

Uygulamanızın `pubspec.yaml` dosyasına ekleyin (tüketici bağımlılıkları bu pakette tanımlıdır):

```yaml
dependencies:
  growth_flutter_sdk: ^0.0.1
```

Ardından platform kurulumlarını tamamlayın:

### Firebase
- iOS: `GoogleService-Info.plist` dosyasını Runner hedefinize ekleyin. Crashlytics/Analytics’i Firebase konsolundan etkinleştirin.
- Android: `google-services.json` dosyasını `app/` içine ekleyin. App modülünde Google Services Gradle eklentisini uygulayın.
- Release için Crashlytics Gradle görevlerinin etkin olduğundan emin olun.

Resmi doküman: `https://firebase.flutter.dev/docs/overview`

### Adjust
- Adjust’ta bir uygulama oluşturup `appToken` alın.
- iOS: `Info.plist` içine Adjust SKAdNetwork ID’lerini ekleyin; gerekiyorsa ATT yapılandırmasını uygulayın.
- Android: Adjust Android SDK manifest/proguard yönergelerini uygulayın.

Resmi doküman: `https://github.com/adjust/flutter_sdk`

### RevenueCat
- Bir proje oluşturun ve iOS/Android API anahtarlarını alın.
- RevenueCat panelinde entegrasyonları etkinleştirin:
  - Firebase (Cloud kısmını uygulamanız gerekmiyor)
  - Adjust (sunucu tarafı bağlantı)

Resmi doküman: `https://www.revenuecat.com/docs`

---

## Kullanım

`main()` içinde (mümkünse `runApp`’ten önce) başlatın:

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
      adjustEnvironment: GrowthAdjustEnvironment.production, // ya da sandbox
      deviceEmailDomain: 'app.com',
      enableDebugLogs: true,
    ),
  );

  // Opsiyonel: kimliklere erişim
  final ids = GrowthSdk.identity;
  // ids?.firebaseUserId, ids?.firebaseAppInstanceId, ids?.adjustAdid, vb.

  runApp(const MyApp());
}
```

### Satın alma & teklifler
```dart
// Offerings/paketleri listeleyin
final offerings = await GrowthSdk.getOfferings();
final current = offerings.current;
final packages = current?.availablePackages ?? [];

// Paywall gösterimi event’i
await GrowthSdk.logPaywallShown(
  offeringId: current?.identifier ?? 'default',
  placementId: 'onboarding',
  variantId: 'v1',
);

// Satın alma öncesi seçenek seçimi event’i
if (packages.isNotEmpty) {
  await GrowthSdk.logPaywallOptionSelected(
    packages.first,
    placementId: 'onboarding',
    variantId: 'v1',
  );

  // Satın alma
  final info = await GrowthSdk.purchasePackage(packages.first);
}

// Geri yükleme
final restored = await GrowthSdk.restorePurchases();
```

### Lifecycle otomatik eventleri
- RevenueCat `CustomerInfo` güncellemeleri üzerinden otomatik tetiklenir:
  - `growth_rc_trial_start`
  - `growth_rc_trial_converted`
  - `growth_rc_cancellation`
- Adjust event token eşlemelerini `GrowthSdkConfig.adjustEventTokens` ile yapabilirsiniz.

### Analytics yardımcıları
```dart
// Ekran görüntülenmesi
await GrowthSdk.logScreenView(screenName: 'Paywall', screenClass: 'PaywallView');

// Sayfa giriş/çıkış
await GrowthSdk.logPageEnter('Onboarding');
await GrowthSdk.logPageExit('Onboarding');

// Buton tıklaması
await GrowthSdk.logButtonClick('cta_subscribe', {'page': 'Paywall'});

// Genel event (prefikssiz)
await GrowthSdk.logAnalyticsEvent('custom_event', {'k': 'v'});
```

### Remote Config & A/B
```dart
// Tiplenmiş getter’lar
final title = GrowthSdk.getRemoteConfigString('paywall_title', defaultValue: 'Welcome');
final enabled = GrowthSdk.getRemoteConfigBool('paywall_enabled', defaultValue: true);
final variantWeight = GrowthSdk.getRemoteConfigDouble('exp_weight', defaultValue: 0.5);

// İhtiyaç halinde (örn. login sonrası) anlık güncelleme
final changed = await GrowthSdk.forceRemoteConfigRefresh();

// Deney varyantını analytics + RC attribute’lara senkronla
await GrowthSdk.syncExperimentVariantFromRemoteConfig(
  rcKey: 'exp_paywall_variant',
  experimentKey: 'paywall',
);

// Manuel ayarlama
await GrowthSdk.setExperimentVariant('paywall', 'v2');
```

### Pazarlama/kullanıcı attribute’ları
```dart
await GrowthSdk.setMarketingAttributes(
  utmSource: 'fb', utmCampaign: 'black_friday', channel: 'paid', country: 'TR');

// Özel attribute’lar
await GrowthSdk.setUserProperties({'cohort': 'Q1-2026'});
```

### Adjust eşleştirmesi
- `GrowthSdkConfig.adjustEventTokens` ile satın alma/geri yükleme/lifecycle eventlerini Adjust’a map edebilirsiniz.
- Başarılı satın almada gelir/para birimi bilgisi Adjust event’ine eklenir.

### Apple Search Ads (opsiyonel)
```dart
await GrowthSdk.enableAppleSearchAdsAttribution();
```

### Notlar
- Remote Config stratejisi: init’te `fetchAndActivate` çağrılır; anlık güncelleme için `forceRemoteConfigRefresh()` kullanabilirsiniz.
- Telemetri/lifecycle eventleri varsayılan olarak `growth_` prefiksiyle loglanır. `logAnalyticsEvent` ise özel eventleri olduğu gibi gönderir.
- Firebase/Adjust/RevenueCat panellerinde ilgili entegrasyonları etkinleştirmeyi unutmayın.

### initialize() neler yapar?
- Firebase ve Crashlytics handler’larını kurar
- Remote Config’i fetch & activate eder
- Cihaz ID üretir/saklar, `deviceId@domain` e‑mail oluşturur
- Firebase Auth’a e‑mail+parola ile giriş yapar (gerekirse anonim fallback)
- Firebase Analytics App Instance ID alır
- Adjust’ı başlatır ve ADID alır
- RevenueCat’i konfigüre eder, Firebase UID (veya cihaz e‑postası) ile login olur, attribute’ları set eder:
  - `app_instance_id`
  - `adjust_adid`
  - `app_user_origin`

Bu sayede RevenueCat eventleri (rc_trial_start, purchases, renewals) doğru kullanıcı kimliğiyle eşleşir ve Firebase Analytics ile Adjust’a tutarlı şekilde iletilir.

---

## Öneriler
- Firebase/Adjust/RevenueCat platform kurulumlarını eksiksiz tamamlayın.
- Apple Search Ads ileride açılırsa, RevenueCat’in önerdiği yöntemle ASA token’ını iletin. Bu paket ASA için kolay genişletilebilir yapıdadır.
- Doğru atribüsyon ve event akışı için `GrowthSdk.initialize` çağrısını olabildiğince erken yapın.


