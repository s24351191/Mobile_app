import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/api.dart';
import 'core/store_state.dart';
import 'core/strings.dart';
import 'ui/account.dart';
import 'ui/cart.dart';
import 'ui/catalog.dart';
import 'ui/orders.dart';
import 'ui/widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8001/v1',
  );
  if (kReleaseMode && Uri.parse(baseUrl).scheme != 'https') {
    throw StateError('Release requires an HTTPS API_BASE_URL');
  }
  runApp(ParaApp(store: StoreState(ApiClient(baseUrl: baseUrl))));
}

class ParaApp extends StatefulWidget {
  final StoreState store;
  final bool autostart;
  const ParaApp({super.key, required this.store, this.autostart = true});
  @override
  State<ParaApp> createState() => _ParaAppState();
}

class _ParaAppState extends State<ParaApp> {
  @override
  void initState() {
    super.initState();
    if (widget.autostart) widget.store.bootstrap();
  }

  @override
  Widget build(BuildContext context) => StoreScope(
    store: widget.store,
    child: ListenableBuilder(
      listenable: widget.store,
      builder: (context, child) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'PARA',
        locale: Locale(widget.store.language),
        supportedLocales: const [Locale('ru'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xfff7f6f2),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff1d4338),
            surface: const Color(0xfff7f6f2),
          ),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
          ),
          cardTheme: CardThemeData(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        home: const StoreHome(),
      ),
    ),
  );
}

class StoreHome extends StatefulWidget {
  const StoreHome({super.key});
  @override
  State<StoreHome> createState() => _StoreHomeState();
}

class _StoreHomeState extends State<StoreHome> {
  int index = 0;
  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    if (!store.ready) {
      return Scaffold(
        appBar: AppBar(title: const Text('PARA')),
        body: Center(
          child: store.startupError == null
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  EmptyMessage(text: context.tr('network')),
                  FilledButton(
                    onPressed: store.bootstrap,
                    child: Text(context.tr('retry')),
                  ),
                ],
              ),
            ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'PARA',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 4),
        ),
        actions: [
          IconButton(
            tooltip: context.tr('refresh'),
            icon: const Icon(Icons.refresh),
            onPressed: () => act(context, () async {
              await Future.wait([
                store.refreshCart(),
                store.refreshProfile(),
                store.loadCatalogue(refresh: true),
              ]);
            }),
          ),
        ],
        bottom: store.busy
          ? const PreferredSize(
              preferredSize: Size.fromHeight(3),
              child: LinearProgressIndicator(),
            )
          : null,
      ),
      body: SafeArea(
        child: switch (index) {
          0 => const CataloguePage(),
          1 => const CartPage(),
          2 => const OrdersPage(),
          _ => const AccountPage(),
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.grid_view_outlined),
            label: context.tr('catalog'),
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: (store.cart?.count ?? 0) > 0,
              label: Text('${store.cart?.count ?? 0}'),
              child: const Icon(Icons.shopping_bag_outlined),
            ),
            label: context.tr('cart'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.receipt_long_outlined),
            label: context.tr('orders'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            label: context.tr('account'),
          ),
        ],
      ),
    );
  }
}
