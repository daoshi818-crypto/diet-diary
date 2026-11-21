import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/domain/entity/nutrition_goal_plan.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
import 'package:opennutritracker/core/utils/calc/macro_calc.dart';

class GetMacroGoalUsecase {
  final ConfigRepository _configRepository;

  GetMacroGoalUsecase(this._configRepository);

  Future<MacroGoals> getGoals(double calories, {DateTime? day}) async {
    final config = await _configRepository.getConfig();
    final plan = config.nutritionGoalSchedule.onDay(
      day == null
          ? DayBoundaryCalc.currentLogicalDayMinutes(
              config.dayStartOffsetTotalMinutes,
            )
          : DayBoundaryCalc.dayLabelOf(day, config.dayStartOffsetTotalMinutes),
    );
    if (plan != null) return plan.macroGoals(calories);
    return MacroGoals(
      MacroCalc.getTotalCarbsGoal(
        calories,
        userCarbsGoal: config.userCarbGoalPct,
      ),
      MacroCalc.getTotalProteinsGoal(
        calories,
        userProteinsGoal: config.userProteinGoalPct,
      ),
      MacroCalc.getTotalFatsGoal(calories, userFatsGoal: config.userFatGoalPct),
    );
  }

  Future<double> getCarbsGoal(double calories, {DateTime? day}) async =>
      (await getGoals(calories, day: day)).carbs;

  Future<double> getFatsGoal(double calories, {DateTime? day}) async =>
      (await getGoals(calories, day: day)).fat;

  Future<double> getProteinsGoal(double calories, {DateTime? day}) async =>
      (await getGoals(calories, day: day)).protein;
}
