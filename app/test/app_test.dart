import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:para_mobile/main.dart';
import 'package:para_mobile/core/api.dart';
import 'package:para_mobile/core/models.dart';
import 'package:para_mobile/core/store_state.dart';

StoreState readyStore(String language) =>
    StoreState(
      ApiClient(baseUrl: 'https://store.example/v1'),
      deviceLanguage: language,
    )
    ..ready = true
    ..cart = Cart.fromJson({
      'items': [],
      'subtotal': '0.00',
      'max_points': 0,
    });

void main() {
  testWidgets('Язык устройства выбирает русский интерфейс', (tester) async {
    final store = readyStore('ru');
    await tester.pumpWidget(ParaApp(store: store, autostart: false));
    await tester.pumpAndSettle();
    expect(find.text('Найдите свою пару'), findsOneWidget);
    expect(find.text('Корзина'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
  testWidgets('Английский интерфейс содержит перевод навигации', (
    tester,
  ) async {
    final store = readyStore('en');
    await tester.pumpWidget(ParaApp(store: store, autostart: false));
    await tester.pumpAndSettle();
    expect(find.text('Find your pair'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
  testWidgets('Гость видит вход в оформление, а не форму чужого заказа', (
    tester,
  ) async {
    final store = readyStore('ru');
    await tester.pumpWidget(ParaApp(store: store, autostart: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Профиль'));
    await tester.pumpAndSettle();
    expect(find.text('Вы вошли как гость'), findsOneWidget);
    expect(find.text('Вход для сотрудника'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
