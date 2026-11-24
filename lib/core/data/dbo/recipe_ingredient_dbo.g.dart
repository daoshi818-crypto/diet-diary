// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recipe_ingredient_dbo.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class RecipeIngredientDBOAdapter extends TypeAdapter<RecipeIngredientDBO> {
  @override
  final typeId = 17;

  @override
  RecipeIngredientDBO read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return RecipeIngredientDBO(
      snapshotMeal: fields[0] as MealDBO,
      amount: (fields[1] as num).toDouble(),
      unit: fields[2] as String,
      convertedAmountG: (fields[3] as num).toDouble(),
      portions: (fields[4] as List?)
          ?.map((e) => (e as Map).cast<String, dynamic>())
          .toList(),
    );
  }

  @override
  void write(BinaryWriter writer, RecipeIngredientDBO obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.snapshotMeal)
      ..writeByte(1)
      ..write(obj.amount)
      ..writeByte(2)
      ..write(obj.unit)
      ..writeByte(3)
      ..write(obj.convertedAmountG)
      ..writeByte(4)
      ..write(obj.portions);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecipeIngredientDBOAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RecipeIngredientDBO _$RecipeIngredientDBOFromJson(Map<String, dynamic> json) =>
    RecipeIngredientDBO(
      snapshotMeal: MealDBO.fromJson(
        json['snapshotMeal'] as Map<String, dynamic>,
      ),
      amount: (json['amount'] as num).toDouble(),
      unit: json['unit'] as String,
      convertedAmountG: (json['convertedAmountG'] as num).toDouble(),
      portions: (json['portions'] as List<dynamic>?)
          ?.map((e) => e as Map<String, dynamic>)
          .toList(),
    );

Map<String, dynamic> _$RecipeIngredientDBOToJson(
  RecipeIngredientDBO instance,
) => <String, dynamic>{
  'snapshotMeal': instance.snapshotMeal,
  'amount': instance.amount,
  'unit': instance.unit,
  'convertedAmountG': instance.convertedAmountG,
  'portions': instance.portions,
};
