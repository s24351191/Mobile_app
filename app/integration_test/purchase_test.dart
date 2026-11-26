import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:para_mobile/core/api.dart';
import 'package:para_mobile/core/store_state.dart';
import 'package:para_mobile/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Гостевая корзина, покупка и решение сотрудника', (tester) async {
    final storage = DeviceStorage();
    for (final key in ['session', 'staff_session', 'pending_order']) {
      await storage.delete(key);
    }
    await SharedPreferencesAsync().setString('language', 'ru');
    const base = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://10.0.2.2:8015/v1',
    );
    final store = StoreState(
      ApiClient(baseUrl: base),
      storage: storage,
      deviceLanguage: 'ru',
    );
    await tester.pumpWidget(ParaApp(store: store));

    Future<void> settle() async {
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
    }

    Future<void> waitFor(Finder finder) async {
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (finder.evaluate().isNotEmpty) return;
      }
      expect(finder, findsWidgets);
    }

    Future<void> tap(Finder finder) async {
      await tester.ensureVisible(finder.first);
      await tester.tap(finder.first);
      await settle();
    }

    Future<void> field(String label, String text) async {
      final finder = find.byWidgetPredicate(
        (widget) =>
          widget is TextField && widget.decoration?.labelText == label,
      );
      await tester.ensureVisible(finder.first);
      await tester.enterText(finder.first, text);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle();
    }

    Future<void> shot(String name) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await settle();
      await tester.pump();
      const captureScreens = bool.fromEnvironment('CAPTURE_GUIDE');
      if (!captureScreens) return;
      final directory = Directory(
        '/data/user/0/ru.para.shop.para_mobile/files/para_guide',
      );
      await directory.create(recursive: true);
      final confirmation = File('${directory.path}/$name.done');
      if (await confirmation.exists()) await confirmation.delete();
      await File('${directory.path}/$name.ready').writeAsString('ready');
      debugPrint('GUIDE_SCREEN $name');
      for (var i = 0; i < 300; i++) {
        if (await confirmation.exists()) return;
        await tester.pump(const Duration(milliseconds: 100));
      }
      fail('Screenshot capture did not finish for $name');
    }

    Future<void> back() async {
      await tester.tap(find.byType(BackButton).first);
      await settle();
    }

    await waitFor(find.byKey(const Key('product-1')));
    await shot('app_catalog');
    await tap(find.byKey(const Key('product-1')));
    await waitFor(find.text('Выберите размер'));
    await tap(find.widgetWithText(ChoiceChip, '42'));
    await tester.drag(find.byType(ListView).last, const Offset(0, -240));
    await settle();
    expect(find.textContaining('290'), findsWidgets);
    await shot('app_product');
    await tap(find.byKey(const Key('add-cart')));
    await back();
    await tap(find.byKey(const Key('product-2')));
    await waitFor(find.text('Выберите размер'));
    await tap(find.widgetWithText(ChoiceChip, '41'));
    await tap(find.byKey(const Key('add-cart')));
    await back();
    await tap(find.text('Корзина'));
    expect(store.role, 'guest');
    expect(store.cart!.count, 2);
    await shot('app_cart');
    await tap(find.text('Войти для оформления'));
    await field('Телефон', '+79119990001');
    await shot('app_phone');
    await tap(find.text('Продолжить'));
    await waitFor(find.text('Код подтверждения'));
    await shot('app_sms');
    await field('Код подтверждения', '123456');
    await tap(find.text('Подтвердить'));
    await waitFor(find.text('Получатель'));
    expect(store.role, 'customer');
    expect(store.cart!.count, 2);
    await field('Получатель', 'Алексей Иванов');
    await field('Адрес доставки', 'Учебный город, ул. Примерная, дом 10');
    await field('Списать баллы', '249');
    await tester.drag(find.byType(ListView).last, const Offset(0, 650));
    await settle();
    await shot('app_checkout');
    await tap(find.byKey(const Key('place-order')));
    await waitFor(find.text('Ожидает решения'));
    await shot('app_order');
    await back();
    await tap(find.text('Профиль'));
    await tap(find.text('Вход для сотрудника'));
    await field('Логин', 'admin');
    await field('Пароль', 'Admin12345!');
    await shot('app_staff_login');
    await tap(find.text('Продолжить'));
    await waitFor(find.text('Код подтверждения'));
    await shot('app_staff_sms');
    await field('Код подтверждения', '654321');
    await tap(find.text('Подтвердить'));
    await waitFor(find.text('Новая карточка'));
    await shot('app_staff_products');
    await tap(find.text('Изменить').first);
    await shot('app_staff_edit');
    await back();
    await tap(find.text('Размеры и остатки').first);
    await tester.scrollUntilVisible(
      find.textContaining('Размер 42'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await settle();
    await shot('app_inventory');
    await back();
    await tap(find.widgetWithText(Tab, 'Заказы'));
    await waitFor(find.text('Ожидает решения'));
    await tap(find.text('Ожидает решения').first);
    await waitFor(find.text('Принять'));
    await shot('app_staff_orders');
    await tap(find.text('Принять'));
    await tap(find.widgetWithText(FilledButton, 'Подтвердить'));
    await waitFor(find.text('Принят менеджером'));
    await back();
    await back();
    await tap(find.text('Заказы'));
    await waitFor(find.text('Принят менеджером'));
    await tap(find.text('Принят менеджером').first);
    await waitFor(
      find.text('Менеджер принял заказ. Отмена покупателем недоступна.'),
    );
    expect(find.text('Отменить заказ'), findsNothing);
    await shot('app_order_accepted');
    await shot('app_test_scenario');
    await back();
    await tap(find.text('Профиль'));
    await tap(find.text('Вход для сотрудника'));
    await waitFor(find.text('Новая карточка'));
    await tap(find.widgetWithText(Tab, 'Заказы'));
    await waitFor(find.text('Принят менеджером'));
    await tap(find.text('Принят менеджером').first);
    await tap(find.text('Завершить'));
    await tap(find.widgetWithText(FilledButton, 'Подтвердить'));
    await waitFor(find.text('Завершён'));
    await shot('app_order_completed');
    await back();
    await back();
    await store.refreshProfile();
    expect(store.points, 626);
    await shot('app_profile');
    await tap(find.byType(DropdownButtonFormField<String>));
    await tap(find.text('English').last);
    await tap(find.text('Catalogue'));
    await shot('app_language_en');
    await tap(find.text('Account'));
    await tap(find.byType(DropdownButtonFormField<String>));
    await tap(find.text('Русский').last);
    await tap(find.text('Каталог'));
    expect(find.text('Найдите свою пару'), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 8)));
}
