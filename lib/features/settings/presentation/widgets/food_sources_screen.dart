import 'package:flutter/material.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/data/data_sources/chinese_food_data_source.dart';
import 'package:opennutritracker/generated/l10n.dart';

class FoodSourcesScreen extends StatefulWidget {
  const FoodSourcesScreen({super.key});
  @override
  State<FoodSourcesScreen> createState() => _FoodSourcesScreenState();
}

class _FoodSourcesScreenState extends State<FoodSourcesScreen> {
  late final Future<int> _count = locator<ChineseFoodDataSource>().count();
  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.localFoodSourcesTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(s.localFoodSourcesDescription),
          const SizedBox(height: 16),
          FutureBuilder<int>(
            future: _count,
            builder: (context, snapshot) {
              if (snapshot.hasError) return Text(s.localFoodLoadError);
              if (!snapshot.hasData) return const LinearProgressIndicator();
              return Text(
                s.localFoodCount(snapshot.data!),
                style: Theme.of(context).textTheme.titleMedium,
              );
            },
          ),
          const SizedBox(height: 16),
          const ListTile(
            leading: Icon(Icons.storage_outlined),
            title: Text('中国食物成分表'),
          ),
          const ListTile(
            leading: Icon(Icons.storage_outlined),
            title: Text('吃有数食物库'),
          ),
          const ListTile(
            leading: Icon(Icons.storage_outlined),
            title: Text('FatSecret 中文数据'),
          ),
          const Divider(),
          Text(s.localFoodNoBarcode),
        ],
      ),
    );
  }
}
