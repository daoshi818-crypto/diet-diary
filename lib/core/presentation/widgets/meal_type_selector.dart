import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';

class MealTypeSelector extends StatelessWidget {
  final IntakeTypeEntity value;
  final ValueChanged<IntakeTypeEntity>? onChanged;
  final String identifier;

  const MealTypeSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.identifier = 'meal-type-selector',
  });

  @override
  Widget build(BuildContext context) => Semantics(
    identifier: identifier,
    child: DropdownButtonHideUnderline(
      child: DropdownButton<IntakeTypeEntity>(
        value: value,
        isDense: true,
        isExpanded: true,
        borderRadius: BorderRadius.circular(16),
        onChanged: onChanged == null
            ? null
            : (type) {
                if (type != null) onChanged!(type);
              },
        items: [
          for (final type in AddMealType.values)
            DropdownMenuItem(
              value: type.getIntakeType(),
              child: Text(
                type.getTypeName(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    ),
  );
}
