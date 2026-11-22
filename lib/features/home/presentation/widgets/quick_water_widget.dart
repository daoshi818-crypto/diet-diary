import 'package:opennutritracker/features/home/presentation/widgets/log_water_dialog.dart';
import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// #32: hydration chip that sits next to the weight chip on the home
/// screen. Reads `waterMlToday` and `waterGoalMl` from `HomeLoadedState`
/// so it stays consistent with whatever logical day the rest of the
/// home view is using.
class QuickWaterWidget extends StatelessWidget {
  final int waterMlToday;
  final int waterGoalMl;
  // #1306: water is a food volume, so it follows the food unit preference.
  final bool usesImperialUnits;

  const QuickWaterWidget({
    super.key,
    required this.waterMlToday,
    required this.waterGoalMl,
    this.usesImperialUnits = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final label = usesImperialUnits
        ? s.waterChipLabelFlOz(
            UnitCalc.mlToFlOz(waterMlToday.toDouble()).round(),
            UnitCalc.mlToFlOz(waterGoalMl.toDouble()).round(),
          )
        : s.waterChipLabel(waterMlToday, waterGoalMl);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      identifier: 'home-water-chip',
      child: InkWell(
        borderRadius: Dimens.borderRadiusM,
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => LogWaterDialog(usesImperialUnits: usesImperialUnits),
        ),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(
            horizontal: Dimens.spacing12,
            vertical: Dimens.spacing8,
          ),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: Dimens.borderRadiusM,
            border: Border.all(color: palette.border, width: Dimens.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.water_drop_rounded, size: 18, color: palette.protein),
              const SizedBox(width: Dimens.spacing8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelLarge?.copyWith(
                    color: palette.textStrong,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
