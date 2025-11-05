## 0.0.1

Initial release:
- Unified init for Firebase (Analytics, Crashlytics, Remote Config, Auth), Adjust, RevenueCat
- Device-based Firebase Auth login (deviceId@domain), identity linking across SDKs
- RevenueCat configure + attributes: app_instance_id, adjust_adid
- Purchases: offerings listing, purchasePackage, restorePurchases
- Lifecycle auto-events: trial_start, trial_converted, cancellation (to Analytics/Adjust)
- Telemetry: paywall shown/option selected, purchase/restore start/success/failure
- Analytics helpers: screen view, page enter/exit, button click, custom events
- Remote Config: typed getters, force refresh, A/B helpers (sync variant)
- Marketing/user attributes: UTM/channel/country + mirrored to RC attributes
