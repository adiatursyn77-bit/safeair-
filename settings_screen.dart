import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentLocale = context.locale;

    return Scaffold(
      appBar: AppBar(title: Text('settings.title'.tr())),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'settings.language'.tr(),
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          RadioListTile<Locale>(
            title: Text('settings.languageRu'.tr()),
            value: const Locale('ru'),
            groupValue: currentLocale,
            onChanged: (locale) {
              if (locale != null) context.setLocale(locale);
            },
          ),
          RadioListTile<Locale>(
            title: Text('settings.languageKk'.tr()),
            value: const Locale('kk'),
            groupValue: currentLocale,
            onChanged: (locale) {
              if (locale != null) context.setLocale(locale);
            },
          ),
          RadioListTile<Locale>(
            title: Text('settings.languageEn'.tr()),
            value: const Locale('en'),
            groupValue: currentLocale,
            onChanged: (locale) {
              if (locale != null) context.setLocale(locale);
            },
          ),
        ],
      ),
    );
  }
}
