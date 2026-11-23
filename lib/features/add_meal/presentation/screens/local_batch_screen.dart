import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/food_quantity_dialog.dart';
import 'package:opennutritracker/core/presentation/widgets/meal_type_selector.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/core/utils/serving_label_localizer.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/local_batch_matcher.dart';
import 'package:opennutritracker/features/add_meal/presentation/log_tray.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/features/add_meal/util/portion_unit.dart';
import 'package:opennutritracker/features/edit_meal/presentation/edit_meal_screen.dart';
import 'package:opennutritracker/features/meal_detail/util/food_entry_preferences.dart';
import 'package:opennutritracker/features/meal_detail/util/meal_quantity_converter.dart';
import 'package:opennutritracker/features/meal_detail/util/portion_display.dart';
import 'package:opennutritracker/generated/l10n.dart';

class LocalBatchScreen extends StatefulWidget {
  final DateTime day;
  final IntakeTypeEntity type;
  final bool usesImperialUnits;
  final LogTray logTray;

  const LocalBatchScreen({
    super.key,
    required this.day,
    required this.type,
    required this.usesImperialUnits,
    required this.logTray,
  });

  @override
  State<LocalBatchScreen> createState() => _LocalBatchScreenState();
}

class _BatchRow {
  final ParsedMealItem item;
  final List<MealEntity> choices;
  MealEntity? food;
  LogTrayItem? selection;
  IntakeTypeEntity type;
  bool added = false;

  _BatchRow(this.item, LocalBatchMatch match, this.type)
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

  LogTrayItem? _initialSelection(_BatchRow row) {
    final food = row.food;
    if (food == null) return null;
    final prefs = FoodEntryPreferences.current;
    final meal = prefs?.withCustomPortions(food) ?? food;
    final nutrients = meal.nutriments;
    if ([
      nutrients.energyKcal100,
      nutrients.carbohydrates100,
      nutrients.fat100,
      nutrients.proteins100,
    ].any((value) => value == null)) {
      return null;
    }
    final quantity = localBatchInitialQuantity(
      row.item,
      meal,
      preferences: prefs,
    );
    if (quantity == null ||
        !quantity.$1.isFinite ||
        quantity.$1 <= 0 ||
        quantity.$1 > 10000) {
      return null;
    }
    final amount = convertQuantityToBaseUnit(quantity.$1, quantity.$2, meal);
    if (!amount.isFinite || amount <= 0) return null;
    return LogTrayItem(
      meal: meal,
      unit: storedUnit(quantity.$2),
      selectionUnit: quantity.$2,
      amount: amount,
      amountLabel: logTrayAmountLabel(context, quantity.$1, quantity.$2, meal),
      intakeType: row.type,
    );
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
            _reuseRow(prior, parsed[i]) ?? _newRow(parsed[i], matches[i]),
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

  _BatchRow _newRow(ParsedMealItem item, LocalBatchMatch match) {
    final row = _BatchRow(item, match, widget.type);
    row.selection = _initialSelection(row);
    return row;
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
                  row.type,
                  widget.usesImperialUnits,
                  templateName: row.item.query,
                ),
              );
        if (!mounted || food == null) return;
        setState(() {
          row.food = food;
          row.selection = _initialSelection(row);
        });
        return;
      }

      final selection = await showFoodQuantitySheet(
        context: context,
        meal: row.selection?.meal ?? row.food!,
        day: widget.day,
        type: row.type,
        usesImperialUnits: widget.usesImperialUnits,
        initialItem: row.selection,
        requireQuantity: true,
        confirmLabel: S.of(context).loggingSaveAmount,
      );
      if (!mounted || selection == null) return;
      setState(() {
        row.selection = selection;
        row.type = selection.intakeType ?? row.type;
      });
    } catch (error, stack) {
      _log.warning('Could not review a local batch row', error, stack);
      if (mounted) _notice(S.of(context).logTrayLogFailedLabel);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _addReady() {
    if (_busy || _inputChanged) return;
    final ready = _rows
        .where((row) => !row.added && row.selection != null)
        .toList();
    if (ready.isEmpty) return;
    setState(() => _busy = true);
    widget.logTray.addAll([
      for (final row in ready)
        row.selection!.withBatchMatchQuery(row.item.query),
    ]);
    setState(() {
      for (final row in ready) {
        row.added = true;
      }
      _busy = false;
    });
    if (_rows.every((row) => row.added)) {
      Navigator.of(context).pop();
    } else {
      _notice(S.of(context).logTrayAddedLabel);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final ready = _rows
        .where((row) => !row.added && row.selection != null)
        .length;
    final pending = _rows
        .where((row) => !row.added && row.selection == null)
        .length;
    return Scaffold(
      appBar: AppBar(title: Text(s.localBatchTitle)),
      bottomNavigationBar: _rows.isEmpty
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (pending > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(s.localBatchPending(pending)),
                      ),
                    Semantics(
                      identifier: 'local-batch-add-ready',
                      child: FilledButton.icon(
                        onPressed: _busy || _inputChanged || ready == 0
                            ? null
                            : _addReady,
                        icon: const Icon(Icons.playlist_add),
                        label: Text(s.localBatchAddReady(ready)),
                      ),
                    ),
                    if (_rows.any((row) => row.added))
                      Semantics(
                        identifier: 'local-batch-view-tray',
                        child: TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.pop(context),
                          child: Text(s.localBatchViewList),
                        ),
                      ),
                  ],
                ),
              ),
            ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Semantics(
              identifier: 'local-batch-input',
              child: TextField(
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
            ),
            const SizedBox(height: 8),
            Semantics(
              identifier: 'local-batch-match',
              child: FilledButton.icon(
                onPressed: _busy || !_inputChanged ? null : _match,
                icon: const Icon(Icons.search),
                label: Text(s.localBatchMatch),
              ),
            ),
            if (_matching) const LinearProgressIndicator(),
            if (_rows.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                s.bulkAddReviewTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Semantics(
                identifier: 'local-batch-results',
                child: Column(
                  children: [
                    for (var i = 0; i < _rows.length; i++) _row(s, _rows[i], i),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(S s, _BatchRow row, int index) {
    final selection = row.selection;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    row.food?.name ?? row.item.query,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (row.added)
                  const Icon(Icons.check_circle_outline)
                else
                  Semantics(
                    identifier: 'local-batch-change-food-$index',
                    child: IconButton(
                      tooltip: row.food == null
                          ? s.localBatchChoose
                          : s.localBatchChange,
                      onPressed: _busy
                          ? null
                          : () => _review(row, choose: true),
                      icon: const Icon(Icons.swap_horiz),
                    ),
                  ),
              ],
            ),
            if (selection != null) ...[
              Text(
                _quantityLabel(s, selection),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (isPortionUnit(selection.selectionUnit ?? selection.unit))
                    '= ${_number(selection.amount)} ${selection.meal.isLiquid ? s.milliliterUnit : s.gramUnit}',
                  logTrayKcalLabel(context, selection.kcal),
                ].join(' · '),
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ] else
              Text(
                row.food != null
                    ? s.localBatchAmountNeeded
                    : row.choices.isEmpty
                    ? s.bulkAddNoMatchLabel
                    : s.localBatchChoose,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                SizedBox(
                  width: 112,
                  child: MealTypeSelector(
                    identifier: 'local-batch-meal-type-$index',
                    value: row.type,
                    onChanged: _busy || row.added
                        ? null
                        : (type) => setState(() {
                            row.type = type;
                            row.selection = row.selection?.withIntakeType(type);
                          }),
                  ),
                ),
                if (row.added)
                  Text(s.localBatchAdded)
                else if (row.food != null)
                  Semantics(
                    identifier: 'local-batch-edit-amount-$index',
                    child: TextButton.icon(
                      onPressed: _busy ? null : () => _review(row),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: Text(s.loggingEditAmount),
                    ),
                  )
                else
                  TextButton(
                    onPressed: _busy ? null : () => _review(row, choose: true),
                    child: Text(s.localBatchChoose),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _quantityLabel(S s, LogTrayItem selection) {
    final unit = selection.selectionUnit ?? selection.unit;
    if (!isPortionUnit(unit)) return selection.amountLabel;
    final food = selection.meal;
    final index = effectivePortionIndex(unit);
    final label = index < food.portions.length
        ? portionDisplayLabel(
            food.portions[index],
            food.isLiquid ? s.milliliterUnit : s.gramUnit,
            localizedLabel: localizeServingLabel(s, food.portions[index].label),
          )
        : food.servingSize ?? s.servingLabel;
    final quantity =
        selection.amount / convertQuantityToBaseUnit(1, unit, food);
    return '${_number(quantity)} × $label';
  }

  String _number(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);
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
