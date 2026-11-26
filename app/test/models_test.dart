import 'package:flutter_test/flutter_test.dart';
import 'package:para_mobile/core/models.dart';
import 'package:para_mobile/core/strings.dart';

void main() {
  test('Стоимость сохраняет точные копейки', () {
    expect(Money.parse('4990.01').kopecks, 499001);
    expect(Money.parse('0.09').decimal, '0.09');
    expect(Money.parse('5290').decimal, '5290.00');
    expect(() => Money.parse('1.001'), throwsFormatException);
  });
  test('Баллы ограничены балансом и тридцатью процентами', () {
    expect(PointRules.limit(Money.parse('4990.00'), 2000), 1497);
    expect(PointRules.limit(Money.parse('4990.00'), 249), 249);
    expect(PointRules.limit(Money.parse('9.99'), 100), 2);
    expect(PointRules.earned(Money.parse('4741.00')), 237);
  });
  test('Для двух языков предусмотрены одинаковые короткие идентификаторы', () {
    expect(texts['ru']!.keys.toSet(), texts['en']!.keys.toSet());
    expect(texts['en']!['cancelLocked'], contains('manager'));
  });
  test('Базовая цена не подменяется минимальной ценой размера', () {
    final product = Product.fromJson({
      'id': 1,
      'stock': 3,
      'name': 'Кеды',
      'name_en': 'Trainers',
      'description': 'Описание',
      'description_en': 'Description',
      'model': 'CW-02',
      'brand': 'PARA',
      'photo': '/static/shoe.webp',
      'price': '4990.00',
      'min_price': '4500.00',
      'is_active': true,
    });
    expect(product.price.kopecks, 499000);
    expect(product.minPrice.kopecks, 450000);
    expect(product.title('en'), 'Trainers');
  });
}
