import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modular_l10n_generator_example/generated/modular_l10n/l10n.dart';
import 'package:modular_l10n_generator_example/main.dart';

Widget _app(Locale locale) => MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        ML.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: ML.supportedLocales,
      home: const HomeScreen(),
    );

void main() {
  testWidgets('renders English', (tester) async {
    await tester.pumpWidget(_app(const Locale('en')));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back, Sara!'), findsOneWidget);
    expect(find.text('3 new messages'), findsOneWidget);
    expect(find.text('Last seen Nov 4, 2026'), findsOneWidget);
    expect(find.text(r'Balance: $1,234.50'), findsOneWidget);
    expect(find.text('You finished 2nd'), findsOneWidget);
    expect(find.text('She is online'), findsOneWidget);
    expect(ML.current.auth.unreadMessages(0), 'No new messages');
    expect(ML.current.auth.unreadMessages(1), 'One new message');
    expect(ML.current.home.rank(11), 'You finished 11th');
    expect(ML.current.home.rank(23), 'You finished 23rd');
  });

  testWidgets('renders Arabic, falling back per key', (tester) async {
    await tester.pumpWidget(_app(const Locale('ar')));
    await tester.pumpAndSettle();

    expect(find.text('الرئيسية'), findsOneWidget);
    expect(find.text('مرحبًا بعودتك يا Sara!'), findsOneWidget);
    expect(find.text('هي متصلة'), findsOneWidget);
    expect(ML.current.auth.unreadMessages(2), 'رسالتان جديدتان');
    expect(ML.current.auth.unreadMessages(5), '5 رسائل جديدة');
  });
}
