import 'dart:async';
import 'dart:io' show Platform;

import 'package:android_id/android_id.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart' as secure;

// Adjust
import 'package:adjust_sdk/adjust.dart' as adjust;
import 'package:adjust_sdk/adjust_config.dart' as adjust;
import 'package:adjust_sdk/adjust_event.dart' as adjust;

// RevenueCat
import 'package:purchases_flutter/purchases_flutter.dart';
export 'package:purchases_flutter/purchases_flutter.dart'
    show
        Package,
        Offerings,
        CustomerInfo,
        PurchaseParams,
        PurchaseResult,
        PeriodType;

/// Public configuration for initializing GrowthSdk.
class GrowthSdkConfig {
  GrowthSdkConfig({
    required this.revenueCatApiKeyAndroid,
    required this.revenueCatApiKeyIos,
    required this.adjustAppToken,
    this.adjustEnvironment = GrowthAdjustEnvironment.production,
    this.enableCrashlytics = true,
    this.remoteConfigFetchIntervalSeconds = 3600,
    this.deviceEmailDomain = 'app.com',
    this.enableDebugLogs = false,
    this.adjustEventTokens,
    this.analyticsEventPrefix = 'growth_',
    this.deviceIdStrategy = DeviceIdStrategy.vendorPreferred,
  });

  final String revenueCatApiKeyAndroid;
  final String revenueCatApiKeyIos;
  final String adjustAppToken;
  final GrowthAdjustEnvironment adjustEnvironment;
  final bool enableCrashlytics;
  final int remoteConfigFetchIntervalSeconds;
  final String deviceEmailDomain;
  final bool enableDebugLogs;
  final AdjustEventTokens? adjustEventTokens;
  final String analyticsEventPrefix;
  final DeviceIdStrategy deviceIdStrategy;
}

enum GrowthAdjustEnvironment { sandbox, production }

enum DeviceIdStrategy {
  /// Try platform vendor IDs (iOS IDFV), then fallback to secure UUID.
  vendorPreferred,

  /// Only use a locally generated and securely persisted UUID.
  generatedOnly,

  /// Prefer Firebase Analytics App Instance ID (when available), else secure UUID.
  analyticsAppInstancePreferred,
}

/// IDs resolved during initialization to help with debugging and analytics joins.
class GrowthIdentity {
  GrowthIdentity({
    required this.deviceId,
    required this.deviceEmail,
    required this.firebaseUserId,
    required this.firebaseAppInstanceId,
    required this.adjustAdid,
    required this.revenueCatAppUserId,
  });

  final String deviceId;
  final String deviceEmail;
  final String? firebaseUserId;
  final String? firebaseAppInstanceId;
  final String? adjustAdid;
  final String revenueCatAppUserId;
}

/// Optional Adjust event token mapping for common lifecycle events.
class AdjustEventTokens {
  const AdjustEventTokens({
    this.purchaseStart,
    this.purchaseSuccess,
    this.purchaseFailure,
    this.restoreStart,
    this.restoreSuccess,
    this.restoreFailure,
    this.trialStart,
    this.trialConverted,
    this.cancellation,
  });

  final String? purchaseStart;
  final String? purchaseSuccess;
  final String? purchaseFailure;
  final String? restoreStart;
  final String? restoreSuccess;
  final String? restoreFailure;
  final String? trialStart;
  final String? trialConverted;
  final String? cancellation;
}

/// Main entry for setting up Firebase, Adjust and RevenueCat.
class GrowthSdk {
  GrowthSdk._();

  static GrowthIdentity? _identity;
  static GrowthIdentity? get identity => _identity;
  static GrowthSdkConfig? _config;

  static final StreamController<CustomerInfo> _customerInfoController =
      StreamController<CustomerInfo>.broadcast();
  static Stream<CustomerInfo> get customerInfoUpdates =>
      _customerInfoController.stream;

  // Cache entitlement snapshot to derive lifecycle transitions
  static final Map<String, _EntitlementSnapshot> _lastEntitlements = {};

  /// Initialize and wire Firebase, Adjust, and RevenueCat.
  static Future<GrowthIdentity> initialize(GrowthSdkConfig config) async {
    _config = config;
    // 1) Firebase Core
    await _ensureFirebaseInitialized();

    // 2) Crashlytics
    if (config.enableCrashlytics) {
      _setupCrashlytics();
    }

    // 3) Remote Config
    await _setupRemoteConfig(
      minimumFetchIntervalSeconds: config.remoteConfigFetchIntervalSeconds,
    );

    // 4) Ensure device identity and Firebase Auth login
    final deviceId = await _getOrCreateDeviceId(config.deviceIdStrategy);
    final deviceEmail = _buildDeviceEmail(deviceId, config.deviceEmailDomain);
    final firebaseUserId = await _ensureFirebaseAuthLogin(deviceEmail);
    if (firebaseUserId != null) {
      try {
        await FirebaseAnalytics.instance.setUserId(id: firebaseUserId);
      } catch (_) {}
    }

    // 5) Firebase Analytics app instance id
    final firebaseAppInstanceId =
        await FirebaseAnalytics.instance.appInstanceId;

    // 6) Adjust init + adid
    final adjustAdid = await _initAdjust(
      appToken: config.adjustAppToken,
      environment: config.adjustEnvironment,
      enableDebugLogs: config.enableDebugLogs,
    );

    // 7) RevenueCat init + user linking
    final rcAppUserId = firebaseUserId ?? deviceEmail;
    await _initRevenueCat(
      androidKey: config.revenueCatApiKeyAndroid,
      iosKey: config.revenueCatApiKeyIos,
      appUserId: rcAppUserId,
      firebaseAppInstanceId: firebaseAppInstanceId,
      adjustAdid: adjustAdid,
      enableDebugLogs: config.enableDebugLogs,
    );

    _identity = GrowthIdentity(
      deviceId: deviceId,
      deviceEmail: deviceEmail,
      firebaseUserId: firebaseUserId,
      firebaseAppInstanceId: firebaseAppInstanceId,
      adjustAdid: adjustAdid,
      revenueCatAppUserId: rcAppUserId,
    );
    return _identity!;
  }

  static Future<void> _ensureFirebaseInitialized() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
    } catch (_) {
      // If already initialized or options are handled by the host app, ignore.
    }
  }

  static void _setupCrashlytics() {
    // Flutter framework errors
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

    // Platform errors (Dart zones)
    // ignore: deprecated_member_use
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  static Future<void> _setupRemoteConfig({
    required int minimumFetchIntervalSeconds,
  }) async {
    final rc = FirebaseRemoteConfig.instance;
    await rc.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 30),
        minimumFetchInterval: Duration(seconds: minimumFetchIntervalSeconds),
      ),
    );
    await rc.fetchAndActivate();
  }

  static final secure.FlutterSecureStorage _secureStorage =
      const secure.FlutterSecureStorage();

  static Future<String> _getOrCreateDeviceId(DeviceIdStrategy strategy) async {
    // 1) Strategy: analytics app instance preferred
    if (strategy == DeviceIdStrategy.analyticsAppInstancePreferred) {
      try {
        final appInstanceId = await FirebaseAnalytics.instance.appInstanceId;
        if (appInstanceId != null && appInstanceId.isNotEmpty) {
          return appInstanceId;
        }
      } catch (_) {}
    }

    // 2) Strategy: vendor preferred – iOS uses IDFV, Android uses ANDROID_ID
    if (strategy == DeviceIdStrategy.vendorPreferred) {
      if (Platform.isIOS) {
        try {
          final deviceInfo = DeviceInfoPlugin();
          final ios = await deviceInfo.iosInfo;
          final idfv = ios.identifierForVendor;
          if (idfv != null && idfv.isNotEmpty) {
            return idfv;
          }
        } catch (_) {}
      } else if (Platform.isAndroid) {
        try {
          final androidIdPlugin = AndroidId();
          final aid = await androidIdPlugin.getId() ?? '';
          if (aid.isNotEmpty) return aid;
        } catch (_) {}
      }
    }

    // 3) Secure storage backed UUID (stable across reinstalls on iOS via Keychain)
    const secureKey = 'growth_sdk_device_id';
    try {
      final fromSecure = await _secureStorage.read(key: secureKey);
      if (fromSecure != null && fromSecure.isNotEmpty) return fromSecure;
    } catch (_) {}

    // Fallback: shared preferences (in case secure storage fails)
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(secureKey);
      if (existing != null && existing.isNotEmpty) {
        // Also mirror into secure storage if missing
        try {
          await _secureStorage.write(key: secureKey, value: existing);
        } catch (_) {}
        return existing;
      }
    } catch (_) {}

    // Create and persist new UUID
    final newId = const Uuid().v4();
    try {
      await _secureStorage.write(key: secureKey, value: newId);
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(secureKey, newId);
    } catch (_) {}
    return newId;
  }

  static String _buildDeviceEmail(String deviceId, String domain) {
    return '$deviceId@$domain';
  }

  static Future<String?> _ensureFirebaseAuthLogin(String deviceEmail) async {
    final auth = fb_auth.FirebaseAuth.instance;
    final current = auth.currentUser;
    if (current != null) return current.uid;

    // Persist a generated password for the device-based email
    final prefs = await SharedPreferences.getInstance();
    const pwKey = 'growth_sdk_device_email_password';
    var password = prefs.getString(pwKey);
    password ??= const Uuid().v4();
    await prefs.setString(pwKey, password);

    try {
      final cred = await auth.signInWithEmailAndPassword(
        email: deviceEmail,
        password: password,
      );
      return cred.user?.uid;
    } on fb_auth.FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        try {
          final cred = await auth.createUserWithEmailAndPassword(
            email: deviceEmail,
            password: password,
          );
          return cred.user?.uid;
        } catch (_) {}
      }
      // wrong-password or other errors fall through to anonymous
      final cred = await auth.signInAnonymously();
      return cred.user?.uid;
    } catch (_) {
      // As a fallback, try anonymous sign-in to ensure events map to a user
      final cred = await auth.signInAnonymously();
      return cred.user?.uid;
    }
  }

  static Future<String?> _initAdjust({
    required String appToken,
    required GrowthAdjustEnvironment environment,
    required bool enableDebugLogs,
  }) async {
    final env = environment == GrowthAdjustEnvironment.sandbox
        ? adjust.AdjustEnvironment.sandbox
        : adjust.AdjustEnvironment.production;

    final config = adjust.AdjustConfig(appToken, env)
      ..logLevel = enableDebugLogs
          ? adjust.AdjustLogLevel.verbose
          : adjust.AdjustLogLevel.info;

    adjust.Adjust.initSdk(config);

    try {
      final adid = await adjust.Adjust.getAdid();
      return adid;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _initRevenueCat({
    required String androidKey,
    required String iosKey,
    required String appUserId,
    required String? firebaseAppInstanceId,
    required String? adjustAdid,
    required bool enableDebugLogs,
  }) async {
    if (enableDebugLogs) {
      await Purchases.setLogLevel(LogLevel.debug);
    }

    final apiKey = Platform.isAndroid ? androidKey : iosKey;
    final configuration = PurchasesConfiguration(apiKey);

    await Purchases.configure(configuration);

    // Identify the user in RevenueCat (maps events to this user)
    try {
      await Purchases.logIn(appUserId);
    } catch (_) {
      // If already logged in, ignore
    }

    // Forward Firebase App Instance ID and Adjust adid as attributes for joins
    final attributes = <String, String>{
      if (firebaseAppInstanceId != null)
        'app_instance_id': firebaseAppInstanceId,
      'app_user_origin': 'firebase_login_device_email',
      // Reserved key name can vary by SDK; using attribute for safety
      if (adjustAdid != null) 'adjust_adid': adjustAdid,
    };
    await Purchases.setAttributes(attributes);

    // Seed and forward customer info updates
    try {
      final current = await Purchases.getCustomerInfo();
      _customerInfoController.add(current);
      _handleCustomerInfoUpdate(current);
    } catch (_) {}

    Purchases.addCustomerInfoUpdateListener((customerInfo) {
      _customerInfoController.add(customerInfo);
      _handleCustomerInfoUpdate(customerInfo);
    });
  }

  /// Expose RevenueCat offerings
  static Future<Offerings> getOfferings() async {
    return Purchases.getOfferings();
  }

  /// Expose current customer info
  static Future<CustomerInfo> getCustomerInfo() async {
    return Purchases.getCustomerInfo();
  }

  /// Restore purchases and track events
  static Future<CustomerInfo> restorePurchases() async {
    final cfg = _config;
    try {
      await _trackEvent(
        '${cfg?.analyticsEventPrefix ?? ''}rc_restore_start',
        const {},
        adjustToken: cfg?.adjustEventTokens?.restoreStart,
      );
    } catch (_) {}

    try {
      final info = await Purchases.restorePurchases();
      await _trackEvent(
        '${cfg?.analyticsEventPrefix ?? ''}rc_restore_success',
        const {},
        adjustToken: cfg?.adjustEventTokens?.restoreSuccess,
      );
      return info;
    } catch (e) {
      await _trackEvent(
        '${cfg?.analyticsEventPrefix ?? ''}rc_restore_failure',
        {'error': e.toString()},
        adjustToken: cfg?.adjustEventTokens?.restoreFailure,
      );
      rethrow;
    }
  }

  /// Purchase a RevenueCat package with analytics/adjust tracking.
  static Future<CustomerInfo> purchasePackage(Package package) async {
    final cfg = _config;
    final product = package.storeProduct;
    final Map<String, Object?> startParams = {
      'product_id': product.identifier,
      'price': product.price,
      'currency': product.currencyCode,
      'package_id': package.identifier,
      'offering_id': package.presentedOfferingContext.offeringIdentifier,
    };

    await _trackEvent(
      '${cfg?.analyticsEventPrefix ?? ''}rc_purchase_start',
      startParams,
      adjustToken: cfg?.adjustEventTokens?.purchaseStart,
    );

    try {
      final PurchaseParams params = PurchaseParams.package(package);
      final PurchaseResult result = await Purchases.purchase(params);
      final CustomerInfo info = result.customerInfo;
      await _trackEvent(
        '${cfg?.analyticsEventPrefix ?? ''}rc_purchase_success',
        startParams,
        adjustToken: cfg?.adjustEventTokens?.purchaseSuccess,
        revenue: product.price,
        currency: product.currencyCode,
      );
      return info;
    } catch (e) {
      await _trackEvent(
        '${cfg?.analyticsEventPrefix ?? ''}rc_purchase_failure',
        {...startParams, 'error': e.toString()},
        adjustToken: cfg?.adjustEventTokens?.purchaseFailure,
      );
      rethrow;
    }
  }

  /// Set multiple RevenueCat subscriber attributes at once.
  static Future<void> setAttributes(Map<String, String> attributes) async {
    if (attributes.isEmpty) return;
    await Purchases.setAttributes(attributes);
  }

  /// Log an analytics event to Firebase Analytics.
  static Future<void> logAnalyticsEvent(
    String name, [
    Map<String, Object?> params = const {},
  ]) async {
    try {
      final cleaned = <String, Object>{};
      params.forEach((key, value) {
        if (value != null) cleaned[key] = value;
      });
      await FirebaseAnalytics.instance.logEvent(
        name: name,
        parameters: cleaned,
      );
    } catch (_) {}
  }

  /// Convenience: log a screen view in Analytics
  static Future<void> logScreenView({
    required String screenName,
    String? screenClass,
  }) async {
    try {
      await FirebaseAnalytics.instance.logScreenView(
        screenName: screenName,
        screenClass: screenClass,
      );
    } catch (_) {}
  }

  /// Convenience: UI page enter/exit events with prefixed names
  static Future<void> logPageEnter(
    String pageName, [
    Map<String, Object?> extra = const {},
  ]) async {
    final prefix = _config?.analyticsEventPrefix ?? '';
    await _trackEvent('${prefix}ui_page_enter', {'page': pageName, ...extra});
  }

  static Future<void> logPageExit(
    String pageName, [
    Map<String, Object?> extra = const {},
  ]) async {
    final prefix = _config?.analyticsEventPrefix ?? '';
    await _trackEvent('${prefix}ui_page_exit', {'page': pageName, ...extra});
  }

  /// Convenience: UI button click event with prefixed name
  static Future<void> logButtonClick(
    String buttonId, [
    Map<String, Object?> extra = const {},
  ]) async {
    final prefix = _config?.analyticsEventPrefix ?? '';
    await _trackEvent('${prefix}ui_button_click', {
      'button_id': buttonId,
      ...extra,
    });
  }

  /// Track an Adjust event if you have a token.
  static Future<void> trackAdjustEvent({
    required String token,
    double? revenue,
    String? currency,
    Map<String, String>? callbackParams,
    Map<String, String>? partnerParams,
  }) async {
    try {
      final event = adjust.AdjustEvent(token);
      if (revenue != null && currency != null) {
        event.setRevenue(revenue, currency);
      }
      callbackParams?.forEach(event.addCallbackParameter);
      partnerParams?.forEach(event.addPartnerParameter);
      adjust.Adjust.trackEvent(event);
    } catch (_) {}
  }

  static Future<void> _trackEvent(
    String name,
    Map<String, Object?> params, {
    String? adjustToken,
    double? revenue,
    String? currency,
  }) async {
    await logAnalyticsEvent(name, params);
    if (adjustToken != null) {
      await trackAdjustEvent(
        token: adjustToken,
        revenue: revenue,
        currency: currency,
        callbackParams: _stringifyParams(params),
      );
    }
  }

  static Map<String, String> _stringifyParams(Map<String, Object?> params) {
    return params.map((k, v) => MapEntry(k, v?.toString() ?? ''));
  }

  static void _handleCustomerInfoUpdate(CustomerInfo info) {
    final cfg = _config;
    if (cfg == null) return;
    final entitlements = info.entitlements.all;
    for (final entry in entitlements.entries) {
      final id = entry.key;
      final e = entry.value;
      final now = _EntitlementSnapshot(
        isActive: e.isActive,
        willRenew: e.willRenew,
        periodType: e.periodType,
        productIdentifier: e.productIdentifier,
      );
      final prev = _lastEntitlements[id];

      // trial start
      final bool trialStarted =
          now.isActive &&
          now.periodType == PeriodType.trial &&
          (prev == null || !prev.isActive);
      if (trialStarted) {
        _trackEvent(
          '${cfg.analyticsEventPrefix}rc_trial_start',
          {
            'entitlement_id': id,
            'product_id': now.productIdentifier,
            'will_renew': now.willRenew,
          },
          adjustToken: cfg.adjustEventTokens?.trialStart,
        );
      }

      // trial converted
      final bool trialConverted =
          prev != null &&
          prev.periodType == PeriodType.trial &&
          now.periodType != PeriodType.trial &&
          now.isActive;
      if (trialConverted) {
        _trackEvent(
          '${cfg.analyticsEventPrefix}rc_trial_converted',
          {
            'entitlement_id': id,
            'product_id': now.productIdentifier,
            'will_renew': now.willRenew,
          },
          adjustToken: cfg.adjustEventTokens?.trialConverted,
        );
      }

      // cancellation
      final bool cancelled = prev != null && prev.isActive && !now.isActive;
      if (cancelled) {
        _trackEvent(
          '${cfg.analyticsEventPrefix}rc_cancellation',
          {
            'entitlement_id': id,
            'product_id': now.productIdentifier,
            'will_renew': now.willRenew,
          },
          adjustToken: cfg.adjustEventTokens?.cancellation,
        );
      }

      _lastEntitlements[id] = now;
    }
  }

  /// Paywall telemetry: paywall shown
  static Future<void> logPaywallShown({
    required String offeringId,
    String? placementId,
    String? variantId,
    Map<String, Object?> extra = const {},
  }) async {
    final cfg = _config;
    await _trackEvent('${cfg?.analyticsEventPrefix ?? ''}paywall_shown', {
      'offering_id': offeringId,
      if (placementId != null) 'placement_id': placementId,
      if (variantId != null) 'variant_id': variantId,
      ...extra,
    });
  }

  /// Paywall telemetry: option selected
  static Future<void> logPaywallOptionSelected(
    Package package, {
    String? placementId,
    String? variantId,
    Map<String, Object?> extra = const {},
  }) async {
    final cfg = _config;
    final product = package.storeProduct;
    await _trackEvent(
      '${cfg?.analyticsEventPrefix ?? ''}paywall_option_selected',
      {
        'product_id': product.identifier,
        'price': product.price,
        'currency': product.currencyCode,
        'package_id': package.identifier,
        'offering_id': package.presentedOfferingContext.offeringIdentifier,
        if (placementId != null) 'placement_id': placementId,
        if (variantId != null) 'variant_id': variantId,
        ...extra,
      },
    );
  }

  /// Set a single Analytics user property and mirror to RevenueCat attributes.
  static Future<void> setUserProperty(
    String name,
    String value, {
    bool alsoSetRevenueCatAttribute = true,
  }) async {
    try {
      await FirebaseAnalytics.instance.setUserProperty(
        name: name,
        value: value,
      );
    } catch (_) {}
    if (alsoSetRevenueCatAttribute) {
      await setAttributes({name: value});
    }
  }

  /// Set multiple Analytics user properties and mirror to RevenueCat attributes.
  static Future<void> setUserProperties(
    Map<String, String> properties, {
    bool alsoSetRevenueCatAttributes = true,
  }) async {
    for (final entry in properties.entries) {
      try {
        await FirebaseAnalytics.instance.setUserProperty(
          name: entry.key,
          value: entry.value,
        );
      } catch (_) {}
    }
    if (alsoSetRevenueCatAttributes && properties.isNotEmpty) {
      await setAttributes(properties);
    }
  }

  /// Common growth/user attributes helper (utm, campaign, country, etc.)
  static Future<void> setMarketingAttributes({
    String? utmSource,
    String? utmMedium,
    String? utmCampaign,
    String? utmTerm,
    String? utmContent,
    String? campaign,
    String? adGroup,
    String? adSet,
    String? channel,
    String? country,
    String? language,
  }) async {
    final props = <String, String>{
      if (utmSource != null) 'utm_source': utmSource,
      if (utmMedium != null) 'utm_medium': utmMedium,
      if (utmCampaign != null) 'utm_campaign': utmCampaign,
      if (utmTerm != null) 'utm_term': utmTerm,
      if (utmContent != null) 'utm_content': utmContent,
      if (campaign != null) 'campaign': campaign,
      if (adGroup != null) 'ad_group': adGroup,
      if (adSet != null) 'ad_set': adSet,
      if (channel != null) 'channel': channel,
      if (country != null) 'country': country,
      if (language != null) 'language': language,
    };
    if (props.isEmpty) return;
    await setUserProperties(props);
  }

  /// Convenience: set experiment variant (Analytics user property + RC attribute)
  static Future<void> setExperimentVariant(
    String experimentKey,
    String variant,
  ) async {
    final property = 'exp_${experimentKey.trim()}';
    await setUserProperty(property, variant);
  }

  /// Convenience: fetch a Remote Config string
  static String getRemoteConfigString(String key, {String defaultValue = ''}) {
    try {
      return FirebaseRemoteConfig.instance.getString(key);
    } catch (_) {
      return defaultValue;
    }
  }

  /// Convenience: typed Remote Config getters
  static bool getRemoteConfigBool(String key, {bool defaultValue = false}) {
    try {
      return FirebaseRemoteConfig.instance.getBool(key);
    } catch (_) {
      return defaultValue;
    }
  }

  static int getRemoteConfigInt(String key, {int defaultValue = 0}) {
    try {
      return FirebaseRemoteConfig.instance.getInt(key);
    } catch (_) {
      return defaultValue;
    }
  }

  static double getRemoteConfigDouble(String key, {double defaultValue = 0.0}) {
    try {
      return FirebaseRemoteConfig.instance.getDouble(key);
    } catch (_) {
      return defaultValue;
    }
  }

  /// Force fetch Remote Config and activate
  static Future<bool> forceRemoteConfigRefresh({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      final rc = FirebaseRemoteConfig.instance;
      await rc.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: timeout,
          minimumFetchInterval: Duration.zero,
        ),
      );
      return await rc.fetchAndActivate();
    } catch (_) {
      return false;
    }
  }

  /// Convenience: sync experiment variant from Remote Config to user properties
  static Future<void> syncExperimentVariantFromRemoteConfig({
    required String rcKey,
    required String experimentKey,
  }) async {
    final variant = getRemoteConfigString(rcKey, defaultValue: 'control');
    await setExperimentVariant(experimentKey, variant);
  }

  /// Enable Apple Search Ads attribution collection (iOS only)
  static Future<void> enableAppleSearchAdsAttribution() async {
    if (Platform.isIOS) {
      try {
        await Purchases.enableAdServicesAttributionTokenCollection();
      } catch (_) {}
    }
  }
}

class _EntitlementSnapshot {
  _EntitlementSnapshot({
    required this.isActive,
    required this.willRenew,
    required this.periodType,
    required this.productIdentifier,
  });

  final bool isActive;
  final bool willRenew;
  final PeriodType periodType;
  final String productIdentifier;
}
