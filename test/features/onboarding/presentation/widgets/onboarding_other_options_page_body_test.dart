import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/section_group.dart';
import 'package:opennutritracker/core/utils/theme_mode_provider.dart';
import 'package:opennutritracker/features/onboarding/presentation/widgets/onboarding_other_options_page_body.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../../../../helpers/test_l10n.dart';

/// The "Other options" page groups its settings the way Profile and Settings
/// do, and describes the bundled local library without remote switches.
void main() {
  Future<void> pumpPage(
    WidgetTester tester, {
    Map<String, bool> toggles = const {},
    void Function(Map<String, bool>)? onToggles,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeModeProvider>(
        create: (_) => ThemeModeProvider(appTheme: AppThemeEntity.system),
        child: MaterialApp(
          localizationsDelegates: const [S.delegate],
          supportedLocales: S.supportedLocales,
          home: Scaffold(
            body: OnboardingOtherOptionsPageBody(
              setPageContent: (_, sources, _, _, _) => onToggles?.call(sources),
              initialTheme: AppThemeEntity.system,
              initialFoodSourceToggles: toggles,
              initialDailyReminderEnabled: false,
              initialUseMaterialYou: true,
              initialAccentColor: null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sections are grouped the way the rest of the app groups them', (
    tester,
  ) async {
    await pumpPage(tester);

    // Theme (with accent), food databases, notifications.
    expect(find.byType(SectionHeader), findsNWidgets(3));
    expect(find.byType(SectionGroup), findsNWidgets(3));
  });

  testWidgets('shows the local library without remote source switches', (tester) async {
    await pumpPage(tester);
    expect(find.text(l10nEn.localFoodSourcesTitle), findsOneWidget);
    expect(find.text(l10nEn.localFoodSourcesDescription), findsOneWidget);
    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.text('Open Food Facts'), findsNothing);
    expect(find.text('FoodData Central (Foundation Foods)'), findsNothing);
  });

  testWidgets('legacy source preferences do not hide the Chinese library', (tester) async {
    await pumpPage(tester, toggles: const {'fdc_branded': false, 'bls': false});
    expect(find.text(l10nEn.localFoodSourcesTitle), findsOneWidget);
    expect(find.bySemanticsIdentifier('onboarding-food-source-bls'), findsNothing);
  });

  testWidgets('showing the local library leaves stored preferences intact', (tester) async {
    Map<String, bool>? reported;
    await pumpPage(tester,
      toggles: const {'bls': false},
      onToggles: (toggles) => reported = toggles,
    );
    expect(reported, isNull, reason: 'Informational library row does not rewrite config');
    expect(tester.takeException(), isNull);
  });
}
