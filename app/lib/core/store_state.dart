import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'models.dart';

abstract class SessionStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class DeviceStorage implements SessionStorage {
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  @override
  Future<String?> read(String key) => storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => storage.delete(key: key);
}

class StoreState extends ChangeNotifier {
  final ApiClient api;
  final SessionStorage storage;
  SharedPreferencesAsync? _preferences;
  SharedPreferencesAsync get preferences =>
      _preferences ??= SharedPreferencesAsync();
  final String deviceLanguage;
  String? languageOverride;
  bool ready = false, busy = false;
  String? startupError;
  String role = 'guest', phone = '';
  int points = 0;
  Cart? cart;
  List<Product> products = [];
  List<String> brands = [], models = [];
  String query = '', brand = '', model = '';
  Json? pendingOrder;
  StoreState(
    this.api, {
    SessionStorage? storage,
    this._preferences,
    String? deviceLanguage,
  }) : storage = storage ?? DeviceStorage(),
       deviceLanguage =
           deviceLanguage ??
           WidgetsBinding.instance.platformDispatcher.locale.languageCode;
  String get language =>
      languageOverride ?? (deviceLanguage == 'ru' ? 'ru' : 'en');
  void changed() => notifyListeners();

  Future<void> bootstrap() async {
    startupError = null;
    ready = false;
    notifyListeners();
    try {
      languageOverride = await preferences.getString('language');
      api.language = language;
      api.token = await storage.read('session');
      api.staffToken = await storage.read('staff_session');
      if (api.token != null) {
        try {
          await refreshProfile();
        } on ApiException catch (error) {
          if (error.status != 401) rethrow;
          api.token = null;
        }
      }
      if (api.token == null) await newGuest();
      final saved = await storage.read('pending_order');
      pendingOrder = saved == null ? null : jsonDecode(saved);
      await Future.wait([
        refreshProfile(),
        refreshCart(),
        loadCatalogue(refresh: true),
      ]);
      ready = true;
    } catch (error) {
      startupError = error.toString();
    }
    notifyListeners();
  }

  Future<void> newGuest() async {
    final Json value = await api.send('POST', '/session');
    api.token = value['token'];
    role = 'guest';
    await storage.write('session', api.token!);
  }

  Future<void> refreshProfile() async {
    final Json value = await api.send('GET', '/profile');
    role = value['role'];
    phone = value['phone'] ?? '';
    points = value['points_balance'];
    notifyListeners();
  }

  Future<void> refreshCart() async {
    cart = Cart.fromJson(await api.send('GET', '/cart'));
    notifyListeners();
  }

  Future<void> loadCatalogue({bool refresh = false}) async {
    var value = await api.catalogue(query, brand, model, refresh: refresh);
    if (brand.isNotEmpty &&
        !List<String>.from(value['brands']).contains(brand)) {
      brand = '';
      model = '';
      value = await api.catalogue(query, brand, model, refresh: true);
    }
    if (model.isNotEmpty &&
        !List<String>.from(value['models']).contains(model)) {
      model = '';
      value = await api.catalogue(query, brand, model, refresh: true);
    }
    products = [
      for (final product in value['products']) Product.fromJson(product),
    ];
    brands = List<String>.from(value['brands']);
    models = List<String>.from(value['models']);
    notifyListeners();
  }

  Future<void> changeCart(
    int identifier,
    int quantity, {
    bool add = false,
  }) async {
    cart = Cart.fromJson(
      await api.send(
        'PATCH',
        '/cart/$identifier',
        data: {'quantity': quantity, 'add': add},
      ),
    );
    notifyListeners();
  }

  Future<Json> beginPhone(String phone) async =>
      await api.send('POST', '/auth/phone', data: {'phone': phone});
  Future<Json> beginStaff(String login, String password) async =>
      await api.send(
        'POST',
        '/auth/staff',
        data: {'login': login, 'password': password},
      );
  Future<void> verify(Json challenge, String code, {bool staff = false}) async {
    final Json value = await api.send(
      'POST',
      '/auth/verify',
      data: {'challenge': challenge['challenge'], 'code': code},
    );
    if (staff) {
      api.staffToken = value['token'];
      await storage.write('staff_session', api.staffToken!);
    } else {
      api.token = value['token'];
      await storage.write('session', api.token!);
      await Future.wait([refreshCart(), refreshProfile()]);
    }
    notifyListeners();
  }

  Future<void> logout({bool staff = false}) async {
    try {
      await api.send('DELETE', '/session', staff: staff);
    } on ApiException catch (error) {
      if (error.status != 401) rethrow;
    }
    if (staff) {
      api.staffToken = null;
      await storage.delete('staff_session');
    } else {
      await storage.delete('session');
      await storage.delete('pending_order');
      pendingOrder = null;
      await newGuest();
      await Future.wait([refreshProfile(), refreshCart()]);
    }
    notifyListeners();
  }

  Future<Order> checkout(
    String recipient,
    String address,
    int usedPoints,
  ) async {
    if (pendingOrder == null) {
      final random = Random.secure();
      final token = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      pendingOrder = {
        'token': token,
        'recipient': recipient.trim(),
        'address': address.trim(),
        'points': usedPoints,
      };
      await storage.write('pending_order', jsonEncode(pendingOrder));
    }
    try {
      final order = Order.fromJson(
        await api.send('POST', '/orders', data: pendingOrder),
      );
      pendingOrder = null;
      await storage.delete('pending_order');
      await Future.wait([refreshCart(), refreshProfile()]);
      return order;
    } on ApiException catch (error) {
      if (error.status >= 400 && error.status < 500) {
        pendingOrder = null;
        await storage.delete('pending_order');
      }
      rethrow;
    }
  }

  Future<void> changeLanguage(String? value) async {
    languageOverride = value;
    api.language = language;
    api.clearCatalogue();
    if (value == null) {
      await preferences.remove('language');
    } else {
      await preferences.setString('language', value);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    api.close();
    super.dispose();
  }
}

class StoreScope extends InheritedNotifier<StoreState> {
  const StoreScope({super.key, required StoreState store, required super.child})
    : super(notifier: store);
  static StoreState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StoreScope>()!.notifier!;
}
