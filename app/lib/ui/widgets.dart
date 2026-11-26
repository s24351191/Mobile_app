import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/store_state.dart';
import '../core/strings.dart';

Future<T?> act<T>(BuildContext context, Future<T> Function() action) async {
  final store = StoreScope.of(context);
  if (store.busy) return null;
  store.busy = true;
  store.changed();
  try {
    return await action();
  } catch (error) {
    if (context.mounted) {
      final text = error is ApiException ? error.message : context.tr('error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(text == 'network' ? context.tr('network') : text),
        ),
      );
    }
    return null;
  } finally {
    store.busy = false;
    store.changed();
  }
}

Future<bool> confirm(BuildContext context, String message) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(context.tr('confirm')),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(context.tr('no')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(context.tr('yes')),
          ),
        ],
      ),
    ) ??
    false;

class ShopPhoto extends StatelessWidget {
  final String path;
  final double? height, width;
  const ShopPhoto(this.path, {super.key, this.height, this.width});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: Image.network(
      StoreScope.of(context).api.imageUrl(path),
      height: height,
      width: width,
      fit: BoxFit.cover,
      cacheWidth: 800,
      errorBuilder: (_, error, stack) => SizedBox(
        height: height ?? 120,
        width: width,
        child: const Icon(Icons.image_outlined, size: 48),
      ),
    ),
  );
}

class EmptyMessage extends StatelessWidget {
  final String? text;
  const EmptyMessage({super.key, this.text});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.shopping_bag_outlined, size: 56),
        const SizedBox(height: 16),
        Text(text ?? context.tr('empty'), textAlign: TextAlign.center),
      ],
    ),
  );
}

class PriceRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const PriceRow(this.label, this.value, {super.key, this.bold = false});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          value,
          style: TextStyle(
            fontSize: bold ? 21 : 16,
            fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
      ],
    ),
  );
}

class LineTile extends StatelessWidget {
  final PurchaseLine line;
  final Widget? actions;
  const LineTile(this.line, {super.key, this.actions});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShopPhoto(line.photo, width: 92, height: 106),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.title(context.language),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text('${line.model} · ${context.tr('size')} ${line.size}'),
              const SizedBox(height: 6),
              Text('${line.price.format(context.language)} × ${line.quantity}'),
              ?actions,
              Text(
                line.total.format(context.language),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool secret, enabled;
  final int lines;
  final TextInputType? keyboard;
  const Field(
    this.label,
    this.controller, {
    super.key,
    this.secret = false,
    this.enabled = true,
    this.lines = 1,
    this.keyboard,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      obscureText: secret,
      enabled: enabled,
      maxLines: lines,
      keyboardType: keyboard,
      validator: (value) => value == null || value.trim().isEmpty
        ? context.tr('fieldRequired')
        : null,
    ),
  );
}
