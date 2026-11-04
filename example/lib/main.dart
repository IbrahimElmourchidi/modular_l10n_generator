import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'generated/modular_l10n/l10n.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: const [
        ML.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: ML.supportedLocales,
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = ML.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.home.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.auth.welcomeBack('Sara')),
          Text(l10n.auth.unreadMessages(3)),
          Text(l10n.home.lastSeen(DateTime(2026, 11, 4))),
          Text(l10n.home.balance(1234.5)),
          Text(l10n.home.rank(2)),
          Text(l10n.home.greeting('female')),
          TextField(decoration: InputDecoration(labelText: l10n.auth.emailLabel)),
        ],
      ),
    );
  }
}
