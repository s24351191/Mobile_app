import 'dart:math';

import 'package:intl/intl.dart';

typedef Json = Map<String, dynamic>;

class Money {
  final int kopecks;
  const Money(this.kopecks);
  factory Money.parse(String value) {
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value)) {
      throw FormatException('Invalid money value', value);
    }
    final parts = value.split('.');
    return Money(
      int.parse(parts[0]) * 100 +
          int.parse(parts.length == 1 ? '0' : parts[1].padRight(2,
              '0')),
    );
  }
  String format(String language) => NumberFormat.currency(
        locale: language == 'ru' ? 'ru_RU' : 'en_US',
        symbol: language == 'ru' ? '₽' : 'RUB',
        decimalDigits: 2,
      ).format(kopecks / 100);
  String get decimal =>
      '${kopecks ~/ 100}.${(kopecks % 100).toString().padLeft(2,
          '0')}';
}
class PointRules {
  static int limit(Money subtotal, int balance) =>
      min(balance, subtotal.kopecks * 30 ~/ 10000);
  static int earned(Money paid) => paid.kopecks * 5 ~/ 10000;
}
class ShoeSize {
  final int id, size, stock;
  final Money price;
  final String? customPrice;
  ShoeSize.fromJson(Json json)
    : id = json['id'],
      size = json['size'],
      stock = json['stock'],
      price = Money.parse(json['price']),
      customPrice = json['custom_price'];
}

class Product {
  final int id, stock;
  final String name, nameEn, description, descriptionEn, model, brand, photo;
  final Money price, minPrice;
  final bool active;
  final List<ShoeSize> sizes;
  Product.fromJson(Json json)
    : id = json['id'],
      stock = (json['stock'] as num? ?? 0).toInt(),
      name = json['name'],
      nameEn = json['name_en'],
      description = json['description'],
      descriptionEn = json['description_en'],
      model = json['model'],
      brand = json['brand'],
      photo = json['photo'],
      price = Money.parse(json['price']),
      minPrice = Money.parse(json['min_price'] ?? json['price']),
      active = json['is_active'],
      sizes = [
        for (final value in json['variants'] ?? []) ShoeSize.fromJson(value),
      ];
  String title(String language) =>
      language == 'en' && nameEn.isNotEmpty ? nameEn : name;
  String text(String language) => language == 'en' && descriptionEn.isNotEmpty
      ? descriptionEn
      : description;
  String get brandText => brand.toLowerCase() == 'napa' ? 'PARA' : brand;
}

class PurchaseLine {
  final int variantId, size, quantity;
  final String name, nameEn, model, photo;
  final Money price, total;
  PurchaseLine.fromJson(Json json)
    : variantId = json['variant_id'],
      size = json['size'],
      quantity = json['quantity'],
      name = json['name'],
      nameEn = json['name_en'],
      model = json['model'],
      photo = json['photo'],
      price = Money.parse(json['price'] ?? json['unit_price']),
      total = Money.parse(json['line_total']);
  String title(String language) =>
      language == 'en' && nameEn.isNotEmpty ? nameEn : name;
}

class Cart {
  final List<PurchaseLine> items;
  final Money subtotal;
  final int maxPoints;
  Cart.fromJson(Json json)
    : items = [for (final value in json['items']) PurchaseLine.fromJson(value)],
      subtotal = Money.parse(json['subtotal']),
      maxPoints = json['max_points'];
  int get count => items.fold(0, (sum, item) => sum + item.quantity);
}

class Order {
  final int id, spent, earned;
  final String status, recipient, address, createdAt;
  final Money subtotal, total;
  final List<PurchaseLine> items;
  Order.fromJson(Json json)
    : id = json['id'],
      spent = json['points_spent'],
      earned = json['points_earned'],
      status = json['status'],
      recipient = json['recipient_name'],
      address = json['address'],
      createdAt = json['created_at'],
      subtotal = Money.parse(json['subtotal']),
      total = Money.parse(json['total']),
      items = [for (final value in json['items']) PurchaseLine.fromJson(value)];
  bool get canCancel => status == 'new';
}
