import 'package:flutter/material.dart';
import 'package:growth_flutter_sdk/growth_flutter_sdk.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await GrowthSdk.initialize(
    GrowthSdkConfig(
      revenueCatApiKeyAndroid: 'RC_PUBLIC_SDK_KEY_ANDROID',
      revenueCatApiKeyIos: 'RC_PUBLIC_SDK_KEY_IOS',
      adjustAppToken: 'YOUR_ADJUST_APP_TOKEN',
      adjustEnvironment: GrowthAdjustEnvironment.sandbox,
      deviceEmailDomain: 'app.com',
      enableDebugLogs: true,
    ),
  );

  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const HomePage(),
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String log = '';
  List<Package> packages = [];

  Future<void> _loadOfferings() async {
    setState(() => log = 'Loading offerings...');
    final offerings = await GrowthSdk.getOfferings();
    final current = offerings.current;
    final list = current?.availablePackages ?? [];
    setState(() {
      packages = list;
      log = 'Offerings loaded: ${list.length} packages';
    });
    if (current != null) {
      await GrowthSdk.logPaywallShown(
        offeringId: current.identifier,
        placementId: 'home',
        variantId: 'v1',
      );
    }
  }

  Future<void> _purchaseFirst() async {
    if (packages.isEmpty) {
      setState(() => log = 'No packages. Load offerings first.');
      return;
    }
    final pkg = packages.first;
    await GrowthSdk.logPaywallOptionSelected(
      pkg,
      placementId: 'home',
      variantId: 'v1',
    );
    try {
      final info = await GrowthSdk.purchasePackage(pkg);
      setState(
        () =>
            log = 'Purchase success: ${info.entitlements.active.keys.toList()}',
      );
    } catch (e) {
      setState(() => log = 'Purchase error: $e');
    }
  }

  Future<void> _restore() async {
    try {
      final info = await GrowthSdk.restorePurchases();
      setState(
        () =>
            log = 'Restore success: ${info.entitlements.active.keys.toList()}',
      );
    } catch (e) {
      setState(() => log = 'Restore error: $e');
    }
  }

  Future<void> _telemetry() async {
    await GrowthSdk.logScreenView(screenName: 'HomePage');
    await GrowthSdk.logButtonClick('demo_button', {'section': 'top'});
    setState(() => log = 'Telemetry sent');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('growth_flutter_sdk example')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton(
                  onPressed: _loadOfferings,
                  child: const Text('Load Offerings'),
                ),
                FilledButton(
                  onPressed: _purchaseFirst,
                  child: const Text('Purchase First'),
                ),
                OutlinedButton(
                  onPressed: _restore,
                  child: const Text('Restore'),
                ),
                OutlinedButton(
                  onPressed: _telemetry,
                  child: const Text('Send Telemetry'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Packages:'),
            Expanded(
              child: ListView.builder(
                itemCount: packages.length,
                itemBuilder: (context, index) {
                  final p = packages[index];
                  final sp = p.storeProduct;
                  return ListTile(
                    title: Text(sp.identifier),
                    subtitle: Text('${sp.price} ${sp.currencyCode}'),
                    trailing: Text(p.identifier),
                  );
                },
              ),
            ),
            Text('Log: $log'),
          ],
        ),
      ),
    );
  }
}
