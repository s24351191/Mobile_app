import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/models.dart';
import '../core/store_state.dart';
import '../core/strings.dart';
import 'orders.dart';
import 'widgets.dart';

class StaffPage extends StatelessWidget {
  const StaffPage({super.key});
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: Text(context.tr('manage')),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: context.tr('logout'),
            onPressed: () async {
              final done = await act(context, () async {
                await StoreScope.of(context).logout(staff: true);
                return true;
              });
              if (done == true && context.mounted) Navigator.pop(context);
            },
          ),
        ],
        bottom: TabBar(
          tabs: [
            Tab(text: context.tr('products')),
            Tab(text: context.tr('orders')),
          ],
        ),
      ),
      body: const TabBarView(
        children: [StaffProducts(), OrdersPage(staff: true)],
      ),
    ),
  );
}

class StaffProducts extends StatefulWidget {
  const StaffProducts({super.key});
  @override
  State<StaffProducts> createState() => _StaffProductsState();
}

class _StaffProductsState extends State<StaffProducts> {
  Future<List<Product>>? loading;
  Future<List<Product>> load() async {
    final value = await StoreScope.of(context).api
        .send('GET', '/staff/products', staff: true);
    return [for (final product in value['products']) Product.fromJson(product)];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    loading ??= load();
  }

  Future<void> edit([Product? product]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProductForm(product: product)),
    );
    if (mounted)
      setState(() {
        loading = load();
      });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Product>>(
    future: loading,
    builder: (context, snapshot) {
      if (snapshot.hasError)
        return Center(child: Text(context.tr('staffExpired')));
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          FilledButton.icon(
            onPressed: () => edit(),
            icon: const Icon(Icons.add),
            label: Text(context.tr('newProduct')),
          ),
          if (!snapshot.hasData)
            const Center(child: CircularProgressIndicator()),
          for (final product in snapshot.data ?? [])
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        ShopPhoto(product.photo, height: 84, width: 84),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(product.title(context.language)),
                              Text('${product.model} · ${product.brandText}'),
                              Text('${context.tr('stock')} ${product.stock}'),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 12,
                      children: [
                        TextButton(
                          onPressed: () => edit(product),
                          child: Text(context.tr('edit')),
                        ),
                        TextButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => InventoryPage(product.id),
                            ),
                          ),
                          child: Text(context.tr('inventory')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

class ProductForm extends StatefulWidget {
  final Product? product;
  const ProductForm({super.key, this.product});
  @override
  State<ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<ProductForm> {
  final form = GlobalKey<FormState>();
  final names = [
    'name',
    'name_en',
    'brand',
    'model',
    'description',
    'description_en',
    'price',
  ];
  late final Map<String, TextEditingController> inputs;
  XFile? photo;
  bool active = true;
  @override
  void initState() {
    super.initState();
    final p = widget.product;
    final values = p == null
        ? <String, String>{}
        : {
            'name': p.name,
            'name_en': p.nameEn,
            'brand': p.brand,
            'model': p.model,
            'description': p.description,
            'description_en': p.descriptionEn,
            'price': p.price.decimal,
          };
    inputs = {
      for (final key in names)
        key: TextEditingController(text: values[key] ?? ''),
    };
    active = p?.active ?? true;
  }

  @override
  void dispose() {
    for (final value in inputs.values) {
      value.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    const labels = {
      'name': 'name',
      'name_en': 'nameEn',
      'brand': 'brand',
      'model': 'model',
      'description': 'description',
      'description_en': 'descriptionEn',
      'price': 'price',
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(widget.product == null ? 'newProduct' : 'edit')),
      ),
      body: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (widget.product != null)
              ShopPhoto(widget.product!.photo, height: 170),
            for (final key in names)
              Field(
                context.tr(labels[key]!),
                inputs[key]!,
                lines: key.startsWith('description') ? 3 : 1,
                keyboard: key == 'price'
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : null,
              ),
            OutlinedButton.icon(
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(
                context.tr(photo == null ? 'photo' : 'photoSelected'),
              ),
              onPressed: store.busy
                  ? null
                  : () async {
                      final selected = await ImagePicker().pickImage(
                        source: ImageSource.gallery,
                      );
                      if (selected != null && mounted)
                        setState(() => photo = selected);
                    },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('active')),
              value: active,
              onChanged: (value) => setState(() => active = value),
            ),
            FilledButton(
              onPressed: store.busy
                  ? null
                  : () async {
                      if (!form.currentState!.validate()) return;
                      final saved = await act(context, () async {
                        final Json fields = {
                          for (final key in names)
                            key: inputs[key]!.text.trim(),
                          'is_active': active,
                          if (widget.product != null) 'id': widget.product!.id,
                        };
                        fields['price'] = fields['price'].replaceAll(',', '.');
                        final data = await photo?.readAsBytes();
                        await store.api.saveProduct(fields, data, photo?.name);
                        await store.loadCatalogue(refresh: true);
                        return true;
                      });
                      if (saved == true && context.mounted)
                        Navigator.pop(context);
                    },
              child: Text(context.tr('save')),
            ),
          ],
        ),
      ),
    );
  }
}

class InventoryPage extends StatefulWidget {
  final int id;
  const InventoryPage(this.id, {super.key});
  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  Product? product;
  Future<void> load() async {
    final value = await StoreScope.of(context).api
        .send('GET', '/staff/products/${widget.id}', staff: true);
    if (mounted) setState(() => product = Product.fromJson(value));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (product == null) load();
  }

  Future<void> change(ShoeSize size, bool price) async {
    final input = TextEditingController(
      text: price ? size.customPrice ?? '' : '1',
    );
    final value = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('${context.tr('size')} ${size.size}'),
        content: TextField(
          controller: input,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: context.tr(price ? 'customPrice' : 'quantity'),
            helperText: price ? context.tr('defaultPrice') : null,
            helperMaxLines: 3,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: Text(context.tr('no')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, input.text.trim()),
            child: Text(context.tr('save')),
          ),
        ],
      ),
    );
    input.dispose();
    if (value == null || !mounted) return;
    final store = StoreScope.of(context);
    await act(context, () async {
      await store.api.send(
        price ? 'PATCH' : 'POST',
        '/staff/variants/${size.id}/${price ? 'price' : 'stock'}',
        staff: true,
        data: price
            ? {'price': value.isEmpty ? null : value.replaceAll(',', '.')}
            : {'quantity': int.tryParse(value) ?? 0},
      );
      store.api.clearCatalogue();
      await load();
      await store.loadCatalogue(refresh: true);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('inventory'))),
    body: product == null
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                product!.title(context.language),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (final size in product!.sizes)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${context.tr('size')} ${size.size} • ${context.tr('stock')} ${size.stock}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(size.price.format(context.language)),
                        Wrap(
                          spacing: 10,
                          children: [
                            TextButton(
                              onPressed: StoreScope.of(context).busy
                                  ? null
                                  : () => change(size, true),
                              child: Text(context.tr('customPrice')),
                            ),
                            TextButton(
                              onPressed: StoreScope.of(context).busy
                                  ? null
                                  : () => change(size, false),
                              child: Text(context.tr('replenish')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
  );
}
