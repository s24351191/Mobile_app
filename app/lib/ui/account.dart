import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/store_state.dart';
import '../core/strings.dart';
import 'staff.dart';
import 'widgets.dart';

class AccountPage extends StatelessWidget {
  const AccountPage({super.key});
  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.account_circle_outlined, size: 72),
        const SizedBox(height: 16),
        Text(
          store.role == 'customer' ? store.phone : context.tr('guest'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        if (store.role == 'customer') ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    '${store.points}',
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  Text(context.tr('points')),
                  const SizedBox(height: 12),
                  Text(context.tr('pointsHint')),
                  Text(context.tr('earnHint')),
                ],
              ),
            ),
          ),
          OutlinedButton(
            onPressed: store.busy ? null : () => act(context, store.logout),
            child: Text(context.tr('logout')),
          ),
        ] else ...[
          Text(context.tr('guestHint')),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LoginPage()),
            ),
            child: Text(context.tr('login')),
          ),
        ],
        const SizedBox(height: 24),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: store.languageOverride ?? 'system',
          decoration: InputDecoration(labelText: context.tr('language')),
          items: [
            DropdownMenuItem(
              value: 'system',
              child: Text(context.tr('system')),
            ),
            const DropdownMenuItem(value: 'ru', child: Text('Русский')),
            const DropdownMenuItem(value: 'en', child: Text('English')),
          ],
          onChanged: (value) => act(
            context,
            () => store.changeLanguage(value == 'system' ? null : value),
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          icon: const Icon(Icons.store_outlined),
          label: Text(context.tr('staffLogin')),
          onPressed: () async {
            if (store.api.staffToken == null) {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LoginPage(staff: true)),
              );
            }
            if (context.mounted && store.api.staffToken != null) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StaffPage()),
              );
            }
          },
        ),
        TextButton(
          onPressed: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(context.tr('legalText')),
              ),
            ),
          ),
          child: Text(context.tr('legal')),
        ),
      ],
    );
  }
}

class LoginPage extends StatefulWidget {
  final bool staff;
  const LoginPage({super.key, this.staff = false});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final form = GlobalKey<FormState>();
  final phone = TextEditingController(),
      login = TextEditingController(),
      password = TextEditingController(),
      code = TextEditingController();
  Json? challenge;
  @override
  void dispose() {
    for (final value in [phone, login, password, code]) {
      value.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(widget.staff ? 'staffLogin' : 'login')),
      ),
      body: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 20),
            const Icon(Icons.lock_outline, size: 64),
            const SizedBox(height: 24),
            if (challenge == null) ...[
              if (widget.staff) ...[
                Field(context.tr('username'), login),
                Field(context.tr('password'), password, secret: true),
              ] else
                Field(
                  context.tr('phone'),
                  phone,
                  keyboard: TextInputType.phone,
                ),
              FilledButton(
                onPressed: store.busy
                    ? null
                    : () async {
                        if (!form.currentState!.validate()) return;
                        final value = await act(
                          context,
                          () => widget.staff
                              ? store.beginStaff(
                                  login.text.trim(),
                                  password.text,
                                )
                              : store.beginPhone(phone.text),
                        );
                        if (value != null && mounted)
                          setState(() => challenge = value);
                      },
                child: Text(context.tr('next')),
              ),
            ] else ...[
              Text(challenge!['phone'], textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '${context.tr('demoSms')} ${challenge!['demo_code']}.',
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Field(context.tr('code'), code, keyboard: TextInputType.number),
              FilledButton(
                onPressed: store.busy
                    ? null
                    : () async {
                        if (!form.currentState!.validate()) return;
                        final success = await act(context, () async {
                          await store.verify(
                            challenge!,
                            code.text.trim(),
                            staff: widget.staff,
                          );
                          return true;
                        });
                        if (success == true && context.mounted)
                          Navigator.pop(context);
                      },
                child: Text(context.tr('verify')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
