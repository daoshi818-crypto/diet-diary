import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/presentation/splash_screen.dart';
import 'package:opennutritracker/core/presentation/widgets/home_appbar.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/generated/l10n.dart';

Widget _app(Widget home, {bool dark = false, double scale = 1}) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: const [
    S.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: S.supportedLocales,
  theme: buildAppTheme(dark ? AppPalette.dark : AppPalette.light),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  routes: {NavigationOptions.mainRoute: (_) => const Text('Ready')},
  home: home,
);

void main() {
  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'diary name and icon fit small header dark=$dark scale=$scale',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(360, 640);
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            _app(
              const Scaffold(appBar: HomeAppbar()),
              dark: dark,
              scale: scale,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('饮食日记', findRichText: true), findsOneWidget);
          final image = tester.widget<SvgPicture>(find.byType(SvgPicture));
          expect(image.semanticsLabel, '饮食日记');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('new splash mark still routes to the app', (tester) async {
    await tester.pumpWidget(_app(const SplashScreen(userInitialized: true)));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 1700));
    await tester.pumpAndSettle();
    expect(find.text('Ready'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
