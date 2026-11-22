import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/food_quantity_dialog.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/local_batch_matcher.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/edit_meal/presentation/edit_meal_screen.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/features/meal_detail/util/food_entry_preferences.dart';
import 'package:opennutritracker/generated/l10n.dart';

class LocalBatchScreen extends StatefulWidget {
  final DateTime day;
  final IntakeTypeEntity type;
  final bool usesImperialUnits;

  const LocalBatchScreen({
    super.key,
    required this.day,
    required this.type,
    required this.usesImperialUnits,
  });

  @override
  State<LocalBatchScreen> createState() => _LocalBatchScreenState();
}

class _BatchRow {
  final ParsedMealItem item;
  final List<MealEntity> choices;
  MealEntity? food;
  bool added = false;

  _BatchRow(this.item, LocalBatchMatch match)
    : choices = match.choices,
      food = match.selected;
}

class _LocalBatchScreenState extends State<LocalBatchScreen> {
  static final _log = Logger('LocalBatchScreen');
  final _input = TextEditingController();
  late final _matcher = LocalBatchMatcher(
    locator(),
    locator(),
    locator(),
    FoodEntryPreferences.current,
  );
  List<_BatchRow> _rows = [];
  bool _busy = false;
  bool _matching = false;
  bool _saving = false;
  bool _inputChanged = true;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _notice(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _match() async {
    if (_busy || !_inputChanged) return;
    final parsed = parseLocalMealBatch(_input.text);
    if (parsed.isEmpty) {
      _notice(S.of(context).localBatchNamesNeeded);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = _matching = true);
    try {
      final matches = await _matcher.match(parsed);
      if (!mounted) return;
      setState(() {
        final prior = [..._rows];
        _rows = [
          for (var i = 0; i < parsed.length; i++)
            _reuseRow(prior, parsed[i]) ?? _BatchRow(parsed[i], matches[i]),
        ];
        _inputChanged = false;
      });
    } catch (error, stack) {
      _log.warning('Local food matching failed', error, stack);
      if (mounted) _notice(S.of(context).bulkAddSearchFailedLabel);
    } finally {
      if (mounted) setState(() => _busy = _matching = false);
    }
  }

  _BatchRow? _reuseRow(List<_BatchRow> prior, ParsedMealItem item) {
    final index = prior.indexWhere(
      (row) =>
          row.item.query == item.query &&
          row.item.rawInput == item.rawInput &&
          row.item.quantity == item.quantity &&
          row.item.unit == item.unit &&
          row.item.portion == item.portion,
    );
    return index < 0 ? null : prior.removeAt(index);
  }

  Future<void> _review(_BatchRow row, {bool choose = false}) async {
    if (_busy || row.added) return;
    setState(() => _busy = true);
    try {
      if (choose || row.food == null) {
        final selection = await Navigator.of(context).push<Object>(
          MaterialPageRoute(
            builder: (_) =>
                _LocalBatchPicker(row: row, search: _matcher.search),
          ),
        );
        if (!mounted || selection == null) return;
        final food = selection is MealEntity
            ? selection
            : await Navigator.of(context).pushNamed<MealEntity>(
                NavigationOptions.editMealRoute,
                arguments: EditMealScreenArguments(
                  widget.day,
                  MealEntity.empty(),
                  widget.type,
                  widget.usesImperialUnits,
                  templateName: row.item.query,
                ),
              );
        if (!mounted || food == null) return;
        setState(() => row.food = food);
      }

      final food = row.food!;
      final selection = await showFoodQuantitySheet(
        context: context,
        meal: food,
        day: widget.day,
        type: widget.type,
        usesImperialUnits: widget.usesImperialUnits,
        initialQuantity: localBatchInitialQuantity(
          row.item,
          food,
          preferences: FoodEntryPreferences.current,
        ),
        requireQuantity: true,
      );
      if (!mounted || selection == null) return;

      setState(() => _saving = true);
      final bloc = locator<MealDetailBloc>();
      try {
        await bloc.addLocalIntake(
          selection.unit,
          selection.amount,
          selection.intakeType ?? widget.type,
          selection.meal,
          widget.day,
        );
      } finally {
        await bloc.close();
      }
      row.added = true;
      locator<HomeBloc>().add(const LoadItemsEvent());
      locator<DiaryBloc>().add(const LoadDiaryYearEvent());
      locator<CalendarDayBloc>().add(const RefreshCalendarDayEvent());
      try {
        await _matcher.remember(row.item.query, food);
      } catch (error, stack) {
        _log.warning('Could not remember food choice', error, stack);
      }
    } catch (error, stack) {
      _log.warning('Could not add a local batch row', error, stack);
      if (mounted) _notice(S.of(context).logTrayLogFailedLabel);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: Text(s.localBatchTitle)),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              TextField(
                controller: _input,
                enabled: !_busy,
                minLines: 2,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: s.localBatchHint,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() => _inputChanged = true),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _busy || !_inputChanged ? null : _match,
                icon: const Icon(Icons.search),
                label: Text(s.localBatchMatch),
              ),
              if (_matching || _saving) const LinearProgressIndicator(),
              for (final row in _rows) ...[
                const Divider(height: 1),
                _row(s, row),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(S s, _BatchRow row) {
    final item = row.item;
    final food = row.food;
    final typed = item.rawInput ?? item.query;
    final summary = food == null
        ? (row.choices.isEmpty ? s.bulkAddNoMatchLabel : s.localBatchChoose)
        : food.name ?? item.query;
    final needsAmount =
        food != null &&
        localBatchInitialQuantity(
              item,
              food,
              preferences: FoodEntryPreferences.current,
            ) ==
            null;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(typed),
      subtitle: Text(
        [
          summary,
          if (row.added)
            s.localBatchAdded
          else if (needsAmount)
            s.localBatchAmountNeeded,
        ].join(' · '),
      ),
      onTap: _busy || row.added ? null : () => _review(row),
      trailing: row.added
          ? const Icon(Icons.check_circle_outline)
          : food != null
          ? IconButton(
              tooltip: s.localBatchChange,
              onPressed: _busy ? null : () => _review(row, choose: true),
              icon: const Icon(Icons.swap_horiz),
            )
          : const Icon(Icons.chevron_right),
    );
  }
}

enum _PickerAction { create }

class _LocalBatchPicker extends StatefulWidget {
  final _BatchRow row;
  final Future<List<MealEntity>> Function(String) search;

  const _LocalBatchPicker({required this.row, required this.search});

  @override
  State<_LocalBatchPicker> createState() => _LocalBatchPickerState();
}

class _LocalBatchPickerState extends State<_LocalBatchPicker> {
  Future<List<MealEntity>>? _results;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.localBatchChoose)),
      body: SafeArea(
        child: FutureBuilder<List<MealEntity>>(
          future: _results,
          builder: (context, snapshot) {
            final foods = _results == null
                ? widget.row.choices
                : snapshot.data ?? const <MealEntity>[];
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                TextField(
                  decoration: InputDecoration(
                    labelText: s.localBatchSearch,
                    hintText: widget.row.item.query,
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (query) => setState(
                    () => _results = query.trim().isEmpty
                        ? null
                        : widget.search(query),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.pop(context, _PickerAction.create),
                  icon: const Icon(Icons.add),
                  label: Text(s.localBatchCreate),
                ),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const LinearProgressIndicator()
                else if (snapshot.hasError)
                  ListTile(title: Text(s.bulkAddSearchFailedLabel))
                else if (foods.isEmpty)
                  ListTile(title: Text(s.bulkAddNoMatchLabel))
                else
                  for (final food in foods)
                    ListTile(
                      title: Text(food.name ?? ''),
                      subtitle: Text(
                        [
                          if (food.brands?.isNotEmpty == true) food.brands!,
                          if (food.nutriments.energyKcal100 case final kcal?)
                            '${kcal.round()} kcal / 100 ${food.isLiquid ? 'ml' : 'g'}',
                        ].join(' · '),
                      ),
                      onTap: () => Navigator.pop(context, food),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}
