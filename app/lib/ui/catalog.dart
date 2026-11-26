import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/store_state.dart';
import '../core/strings.dart';
import 'widgets.dart';

class CataloguePage extends StatefulWidget {
  const CataloguePage({super.key});
  @override
  State<CataloguePage> createState() => _CataloguePageState();
}

class _CataloguePageState extends State<CataloguePage> {
  final search = TextEditingController();
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return RefreshIndicator(
      onRefresh: () => store.loadCatalogue(refresh: true),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            context.tr('headline'),
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(context.tr('subtitle')),
          const SizedBox(height: 20),
          TextField(
            key: const Key('search'),
            controller: search,
            decoration: InputDecoration(
              labelText: context.tr('search'),
              suffixIcon: IconButton(
                tooltip: context.tr('search'),
                icon: const Icon(Icons.search),
                onPressed: () => act(context, () async {
                  store.query = search.text.trim();
                  await store.loadCatalogue();
                }),
              ),
            ),
            onSubmitted: (value) => act(context, () async {
              store.query = value.trim();
              await store.loadCatalogue();
            }),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  key: ValueKey('brand-${store.brand}'),
                  initialValue: store.brand,
                  decoration: InputDecoration(labelText: context.tr('brand')),
                  items: [
                    DropdownMenuItem(value: '', child: Text(context.tr('all'))),
                    for (final value in store.brands)
                      DropdownMenuItem(
                        value: value,
                        child: Text(
                          value.toLowerCase() == 'пара' ? 'PARA' : value,
                        ),
                      ),
                  ],
                  onChanged: store.busy
                      ? null
                      : (value) => act(context, () async {
                          store.brand = value!;
                          store.model = '';
                          await store.loadCatalogue();
                        }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  key: ValueKey('model-${store.brand}-${store.model}'),
                  initialValue: store.model,
                  decoration: InputDecoration(labelText: context.tr('model')),
                  items: [
                    DropdownMenuItem(value: '', child: Text(context.tr('all'))),
                    for (final value in store.models)
                      DropdownMenuItem(value: value, child: Text(value)),
                  ],
                  onChanged: store.busy
                      ? null
                      : (value) => act(context, () async {
                          store.model = value!;
                          await store.loadCatalogue();
                        }),
                ),
              ),
            ],
          ),
          if (store.query.isNotEmpty ||
              store.brand.isNotEmpty ||
              store.model.isNotEmpty)
            TextButton(
              onPressed: () => act(context, () async {
                search.clear();
                store.query = store.brand = store.model = '';
                await store.loadCatalogue(refresh: true);
                setState(() {});
              }),
              child: Text(context.tr('clearFilters')),
            ),
          const SizedBox(height: 20),
          if (store.products.isEmpty) const EmptyMessage(),
          LayoutBuilder(
            builder: (context, constraints) => GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: store.products.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: MediaQuery.textScalerOf(context).scale(1) > 1.3
                    ? 1
                    : constraints.maxWidth > 650
                    ? 3
                    : 2,
                mainAxisExtent: MediaQuery.textScalerOf(context).scale(1) > 1.3
                    ? 370
                    : 292,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemBuilder: (context, index) {
                final product = store.products[index];
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: Key('product-${product.id}'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProductPage(product.id),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ShopPhoto(product.photo, height: 160),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${product.brandText} · ${product.model}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                product.title(context.language),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                product.minPrice.format(context.language),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ProductPage extends StatefulWidget {
  final int id;
  const ProductPage(this.id, {super.key});
  @override
  State<ProductPage> createState() => _ProductPageState();
}

class _ProductPageState extends State<ProductPage> {
  Future<Product>? loading;
  ShoeSize? selected;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    loading ??= StoreScope.of(context).api
        .send('GET', '/products/${widget.id}')
        .then((value) => Product.fromJson(value));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('PARA')),
    body: FutureBuilder<Product>(
      future: loading,
      builder: (context, snapshot) {
        if (snapshot.hasError) return EmptyMessage(text: context.tr('network'));
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final product = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ShopPhoto(product.photo, height: 300),
            const SizedBox(height: 20),
            Text('${product.brandText} · ${product.model}'),
            const SizedBox(height: 8),
            Text(
              product.title(context.language),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            Text(
              (selected?.price ?? product.price).format(context.language),
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Text(context.tr('sizes')),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final size in product.sizes)
                  ChoiceChip(
                    label: Text('${size.size}'),
                    selected: selected?.id == size.id,
                    onSelected: size.stock == 0
                        ? null
                        : (_) => setState(() => selected = size),
                  ),
              ],
            ),
            if (selected != null)
              Text('${context.tr('stock')} ${selected!.stock}'),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('add-cart'),
              onPressed: selected == null || StoreScope.of(context).busy
                  ? null
                  : () => act(context, () async {
                      await StoreScope.of(context)
                          .changeCart(selected!.id, 1, add: true);
                      if (context.mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(context.tr('added'))),
                        );
                    }),
              icon: const Icon(Icons.add_shopping_cart),
              label: Text(context.tr('add')),
            ),
            const SizedBox(height: 22),
            Text(
              context.tr('description'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(product.text(context.language)),
          ],
        );
      },
    ),
  );
}
