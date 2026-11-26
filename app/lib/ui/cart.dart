import 'package:flutter/material.dart';

import '../core/store_state.dart';
import '../core/models.dart';
import '../core/strings.dart';
import 'account.dart';
import 'orders.dart';
import 'widgets.dart';

class CartPage extends StatelessWidget {
  const CartPage({super.key});
  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context), cart = StoreScope.of(context).cart;
    if (cart == null || cart.items.isEmpty)
      return const Center(child: EmptyMessage());
    return RefreshIndicator(
      onRefresh: store.refreshCart,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          for (final item in cart.items)
            LineTile(
              item,
              actions: Row(
                children: [
                  IconButton(
                    tooltip: '-',
                    onPressed: store.busy
                      ? null
                      : () => act(
                        context,
                        () => store.changeCart(
                          item.variantId,
                          item.quantity - 1,
                        ),
                      ),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('${item.quantity}'),
                  IconButton(
                    tooltip: '+',
                    onPressed: store.busy
                      ? null
                      : () => act(
                        context,
                        () => store.changeCart(
                          item.variantId,
                          item.quantity + 1,
                        ),
                      ),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            ),
          const Divider(),
          PriceRow(
            context.tr('subtotal'),
            cart.subtotal.format(context.language),
            bold: true,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: store.busy
              ? null
              : () async {
                if (store.role != 'customer') {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginPage()),
                  );
                }
                if (context.mounted && store.role == 'customer') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CheckoutPage()),
                  );
                }
              },
            child: Text(
              context.tr(
                store.role == 'customer' ? 'checkout' : 'loginCheckout',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key});
  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final form = GlobalKey<FormState>();
  final recipient = TextEditingController(),
    address = TextEditingController(),
    points = TextEditingController(text: '0');
  bool loaded = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!loaded) {
      final pending = StoreScope.of(context).pendingOrder;
      if (pending != null) {
        recipient.text = pending['recipient'];
        address.text = pending['address'];
        points.text = '${pending['points']}';
      }
      loaded = true;
    }
  }

  @override
  void dispose() {
    recipient.dispose();
    address.dispose();
    points.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context),
      pending = StoreScope.of(context).pendingOrder != null;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('checkout'))),
      body: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            for (final line in store.cart?.items ?? []) LineTile(line),
            Field(
              context.tr('recipient'),
              recipient,
              enabled: !pending && !store.busy,
            ),
            Field(
              context.tr('address'),
              address,
              lines: 2,
              enabled: !pending && !store.busy,
            ),
            Text(
              '${context.tr('points')} ${store.points} · ${context.tr('usePoints')} ≤ ${store.cart?.maxPoints ?? 0}',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: points,
              enabled: !pending && !store.busy,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: context.tr('usePoints')),
              validator: (text) {
                final number = int.tryParse(text ?? '');
                return number == null ||
                    number < 0 ||
                    number > (store.cart?.maxPoints ?? 0)
                  ? context.tr('invalidPoints')
                  : null;
              },
            ),
            const SizedBox(height: 12),
            Text(context.tr('pointsHint')),
            Text(context.tr('earnHint')),
            const SizedBox(height: 20),
            if (store.cart != null)
              PriceRow(
                context.tr('subtotal'),
                store.cart!.subtotal.format(context.language),
                bold: true,
              ),
            if (store.cart != null)
              ValueListenableBuilder(
                valueListenable: points,
                builder: (context, value, child) => PriceRow(
                  context.tr('total'),
                  Money(
                    store.cart!.subtotal.kopecks -
                      (int.tryParse(value.text) ?? 0).clamp(
                        0,
                        store.cart!.maxPoints,
                      ) *
                      100,
                  ).format(context.language),
                  bold: true,
                ),
              ),
            if (pending) Text(context.tr('pendingHint')),
            FilledButton(
              key: const Key('place-order'),
              onPressed: store.busy
                ? null
                : () async {
                    if (!form.currentState!.validate()) return;
                    final order = await act(
                      context,
                      () => store.checkout(
                        recipient.text,
                        address.text,
                        int.parse(points.text),
                      ),
                    );
                    if (order != null && context.mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => OrderPage(order.id, initial: order),
                        ),
                      );
                    }
                  },
              child: Text(context.tr(pending ? 'pending' : 'place')),
            ),
          ],
        ),
      ),
    );
  }
}
