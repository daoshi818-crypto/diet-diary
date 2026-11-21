import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/partial_results_notice.dart';
import 'package:opennutritracker/generated/l10n.dart';

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: const [
    S.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: S.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  group('PartialResultsNotice', () {
    testWidgets('shows the notice text and a retry action', (tester) async {
      await tester.pumpWidget(_wrap(PartialResultsNotice(onRetry: () {})));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Some local food data could not be read. Showing available results. Please retry.',
        ),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('says the local library is unavailable when all are down', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(PartialResultsNotice(onRetry: () {}, allSourcesDown: true)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'The local food library could not be read. Showing saved foods only. Please retry.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Some local food data could not be read. Showing available results. Please retry.',
        ),
        findsNothing,
      );
    });

    testWidgets('fires onRetry when the retry action is tapped', (
      tester,
    ) async {
      var retries = 0;

      await tester.pumpWidget(
        _wrap(PartialResultsNotice(onRetry: () => retries++)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(retries, 1);
    });
  });
}
