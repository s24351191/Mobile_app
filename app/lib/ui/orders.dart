import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/store_state.dart';
import '../core/strings.dart';
import 'account.dart';
import 'widgets.dart';

class OrdersPage extends StatefulWidget {
  final bool staff;
  const OrdersPage({super.key, this.staff = false});
  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  Future<List<Order>>? loading;
  Future<List<Order>> load() async {
    final values = await StoreScope.of(context).api.send(
      'GET',
      widget.staff ? '/staff/orders' : '/orders',
      staff: widget.staff,
    );
    return [for (final value in values) Order.fromJson(value)];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.staff || StoreScope.of(context).role == 'customer')
      loading ??= load();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.staff && StoreScope.of(context).role != 'customer') {
      return Center(
        child: FilledButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LoginPage()),
          ),
          child: Text(context.tr('login')),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          loading = load();
        });
        await loading;
      },
      child: FutureBuilder<List<Order>>(
        future: loading,
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return ListView(
              children: [
                EmptyMessage(text: context.tr('network')),
                TextButton(
                  onPressed: () => setState(() {
                    loading = load();
                  }),
                  child: Text(context.tr('retry')),
                ),
              ],
            );
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (snapshot.data!.isEmpty) const EmptyMessage(),
              for (final order in snapshot.data!)
                Card(
                  child: InkWell(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => OrderPage(
                            order.id,
                            initial: order,
                            staff: widget.staff,
                          ),
                        ),
                      );
                      if (mounted)
                        setState(() {
                          loading = load();
                        });
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${context.tr('order')} № ${order.id}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                              Text(order.total.format(context.language)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Chip(label: Text(context.tr(order.status))),
                          for (final item in order.items) LineTile(item),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class OrderPage extends StatefulWidget {
  final int id;
  final Order? initial;
  final bool staff;
  const OrderPage(this.id, {super.key, this.initial, this.staff = false});
  @override
  State<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage> {
  Order? order;
  Future<void> load() async {
    final value = await StoreScope.of(context).api
        .send('GET', '/orders/${widget.id}', staff: widget.staff);
    if (mounted) setState(() => order = Order.fromJson(value));
  }

  @override
  void initState() {
    super.initState();
    order = widget.initial;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (order == null) load();
  }

  Future<void> action(String target) async {
    if (!await confirm(
      context,
      context.tr(target == 'cancelled' ? 'cancel' : target),
    ))
      return;
    if (!mounted) return;
    await act(context, () async {
      final api = StoreScope.of(context).api;
      final value = await api.send(
        'POST',
        widget.staff
            ? '/staff/orders/${widget.id}/status'
            : '/orders/${widget.id}/cancel',
        staff: widget.staff,
        data: widget.staff ? {'target': target} : null,
      );
      if (mounted) setState(() => order = Order.fromJson(value));
      if (!widget.staff && mounted)
        await StoreScope.of(context).refreshProfile();
    });
  }

  @override
  Widget build(BuildContext context) {
    final value = order;
    return Scaffold(
      appBar: AppBar(
        title: Text('${context.tr('order')} № ${widget.id}'),
        actions: [
          IconButton(
            onPressed: () => act(context, load),
            tooltip: context.tr('refresh'),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: value == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(label: Text(context.tr(value.status))),
                ),
                const SizedBox(height: 8),
                Text(
                  value.recipient,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(value.address),
                const SizedBox(height: 16),
                for (final line in value.items) LineTile(line),
                const Divider(),
                PriceRow(
                  context.tr('subtotal'),
                  value.subtotal.format(context.language),
                ),
                PriceRow(context.tr('spent'), '${value.spent}'),
                PriceRow(
                  context.tr('total'),
                  value.total.format(context.language),
                  bold: true,
                ),
                PriceRow(context.tr('earned'), '${value.earned}'),
                if (!widget.staff && value.canCancel)
                  OutlinedButton(
                    onPressed: StoreScope.of(context).busy
                        ? null
                        : () => action('cancelled'),
                    child: Text(context.tr('cancel')),
                  ),
                if (!widget.staff && value.status == 'accepted')
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Text(context.tr('cancelLocked')),
                  ),
                if (widget.staff && value.status == 'new') ...[
                  FilledButton(
                    onPressed: StoreScope.of(context).busy
                        ? null
                        : () => action('accepted'),
                    child: Text(context.tr('accept')),
                  ),
                  OutlinedButton(
                    onPressed: StoreScope.of(context).busy
                        ? null
                        : () => action('rejected'),
                    child: Text(context.tr('reject')),
                  ),
                ],
                if (widget.staff && value.status == 'accepted') ...[
                  FilledButton(
                    onPressed: StoreScope.of(context).busy
                        ? null
                        : () => action('completed'),
                    child: Text(context.tr('complete')),
                  ),
                  OutlinedButton(
                    onPressed: StoreScope.of(context).busy
                        ? null
                        : () => action('cancelled'),
                    child: Text(context.tr('cancel')),
                  ),
                ],
              ],
            ),
    );
  }
}
