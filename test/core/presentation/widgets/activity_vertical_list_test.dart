import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/physical_activity_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/activity_card.dart';
import 'package:opennutritracker/core/presentation/widgets/activity_vertial_list.dart';
import 'package:opennutritracker/core/presentation/widgets/placeholder_card.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

void main() {
  for (final hasActivity in [false, true]) {
    testWidgets('activity section has no add card: populated=$hasActivity', (
      tester,
    ) async {
      final activity = UserActivityEntity(
        'test-activity',
        30,
        150,
        DateTime(2026, 11, 20),
        PhysicalActivityEntity.customNamed('Evening walk'),
      );
      UserActivityEntity? tapped;
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => EnergyUnitProvider(),
          child: MaterialApp(
            localizationsDelegates: const [S.delegate],
            supportedLocales: S.supportedLocales,
            home: Scaffold(
              body: ActivityVerticalList(
                day: activity.date,
                title: 'Activity',
                userActivityList: hasActivity ? [activity] : [],
                onItemLongPressedCallback: (_, _) {},
                onItemTappedCallback: (_, value) => tapped = value,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PlaceholderCard), findsNothing);
      expect(find.byIcon(Icons.add), findsNothing);
      expect(
        find.byType(ActivityCard),
        hasActivity ? findsOneWidget : findsNothing,
      );
      if (hasActivity) {
        await tester.tap(find.byType(ActivityCard));
        expect(tapped, same(activity));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
