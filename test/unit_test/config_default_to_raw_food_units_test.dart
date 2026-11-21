import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/dbo/app_theme_dbo.dart';
import 'package:opennutritracker/core/data/dbo/config_dbo.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';

void main() {
  group('ConfigEntity.fromConfigDBO defaultToRawFoodUnits', () {
    test('defaults to raw units when the stored DBO field is null', () {
      final dbo = ConfigDBO(false, false, false, AppThemeDBO.system);
      // Sanity: the DBO's own field is nullable and starts absent.
      expect(dbo.defaultToRawFoodUnits, isNull);

      final entity = ConfigEntity.fromConfigDBO(dbo);
      expect(entity.defaultToRawFoodUnits, isTrue);
    });

    test('carries a stored true value into the entity', () {
      final dbo = ConfigDBO(false, false, false, AppThemeDBO.system)
        ..defaultToRawFoodUnits = true;

      final entity = ConfigEntity.fromConfigDBO(dbo);
      expect(entity.defaultToRawFoodUnits, isTrue);
    });

    test('carries a stored false value through unchanged', () {
      final dbo = ConfigDBO(false, false, false, AppThemeDBO.system)
        ..defaultToRawFoodUnits = false;

      final entity = ConfigEntity.fromConfigDBO(dbo);
      expect(entity.defaultToRawFoodUnits, isFalse);
    });
  });
}
