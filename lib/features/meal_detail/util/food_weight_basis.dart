import 'package:opennutritracker/generated/l10n.dart';

enum FoodWeightBasis { raw, cooked, dry, wet, fresh, rehydrated }

FoodWeightBasis? foodWeightBasis(String? name) {
  final text = name ?? '';
  if (RegExp(r'泡发|水发|复水|[（(,，]浸(?:泡)?[）),，]').hasMatch(text)) {
    return FoodWeightBasis.rehydrated;
  }
  if (RegExp(
    r'[（(,，]干(?:重|品)?[）),，]|^干(?:面|米粉|意大利面|木耳|银耳|香菇|海带)',
  ).hasMatch(text)) {
    return FoodWeightBasis.dry;
  }
  if (RegExp(r'[（(,，]生(?:重)?[）),，]').hasMatch(text)) {
    return FoodWeightBasis.raw;
  }
  if (RegExp(r'[（(,，]湿(?:重)?[）),，]').hasMatch(text)) {
    return FoodWeightBasis.wet;
  }
  if (RegExp(r'[（(,，]鲜(?:重)?[）),，]').hasMatch(text)) {
    return FoodWeightBasis.fresh;
  }
  if (RegExp(
    r'熟|米饭|粥|[（(,，](?:煮|蒸|炒|煎|炸|烤)[）),，]|^(?:水煮|清蒸|煮|蒸|炒|煎|炸|烤)',
  ).hasMatch(text)) {
    return FoodWeightBasis.cooked;
  }
  return null;
}

String? foodWeightBasisLabel(S s, String? name) =>
    switch (foodWeightBasis(name)) {
      FoodWeightBasis.raw => s.foodWeightBasisRaw,
      FoodWeightBasis.cooked => s.foodWeightBasisCooked,
      FoodWeightBasis.dry => s.foodWeightBasisDry,
      FoodWeightBasis.wet => s.foodWeightBasisWet,
      FoodWeightBasis.fresh => s.foodWeightBasisFresh,
      FoodWeightBasis.rehydrated => s.foodWeightBasisRehydrated,
      null => null,
    };
