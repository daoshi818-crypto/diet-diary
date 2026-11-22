import 'package:flutter/material.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/data/data_sources/chinese_food_data_source.dart';
import 'package:opennutritracker/features/add_meal/data/food_catalog_updater.dart';
import 'package:opennutritracker/generated/l10n.dart';

class FoodSourcesScreen extends StatefulWidget {
  const FoodSourcesScreen({super.key});
  @override
  State<FoodSourcesScreen> createState() => _FoodSourcesScreenState();
}

class _FoodSourcesScreenState extends State<FoodSourcesScreen> {
  late Future<int> _count = locator<ChineseFoodDataSource>().count();
  FoodCatalogUpdater? _updater;
  @override
  void initState() {
    super.initState();
    if (locator.isRegistered<FoodCatalogUpdater>()) {
      _updater = locator<FoodCatalogUpdater>()..addListener(_refresh);
      _updater!.readInstalledCatalog().then((_) {
        if (mounted) _refresh();
      });
    }
  }

  void _refresh() {
    if (!mounted) return;
    setState(() => _count = locator<ChineseFoodDataSource>().count());
  }

  @override
  void dispose() {
    _updater?.removeListener(_refresh);
    super.dispose();
  }

  String _date(DateTime? date) =>
      date == null ? '尚无记录' : date.toLocal().toString().split('.').first;
  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final update = _updater;
    final busy =
        update?.phase == FoodCatalogUpdatePhase.checking ||
        update?.phase == FoodCatalogUpdatePhase.downloading;
    return Scaffold(
      appBar: AppBar(title: Text(s.localFoodSourcesTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('食物库保存在本机，可离线搜索和记餐。联网时自动检查新版本，更新无需重新安装应用。'),
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
          const SizedBox(height: 12),
          Text('当前版本：${update?.current?.version ?? '内置基础库'}'),
          Text('上次成功检查：${_date(update?.lastCheck)}'),
          Text('上次成功更新：${_date(update?.lastInstall)}'),
          const SizedBox(height: 12),
          if (busy) const LinearProgressIndicator(),
          if (update != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(switch (update.phase) {
                FoodCatalogUpdatePhase.checking => '正在检查食物库版本…',
                FoodCatalogUpdatePhase.downloading => '正在下载并校验食物库…',
                FoodCatalogUpdatePhase.current => '已是最新版本',
                FoodCatalogUpdatePhase.updated => '食物库已更新，可立即搜索',
                FoodCatalogUpdatePhase.failed =>
                  update.error ?? '更新失败，当前离线库仍可使用',
                FoodCatalogUpdatePhase.idle => '可手动检查食物库更新',
              }),
            ),
          Semantics(
            identifier: 'food-catalog-check-update',
            child: OutlinedButton.icon(
              onPressed: busy || update == null
                  ? null
                  : () => update.check(manual: true),
              icon: const Icon(Icons.sync_rounded),
              label: const Text('检查更新'),
            ),
          ),
          const Divider(height: 32),
          const ListTile(
            leading: Icon(Icons.storage_outlined),
            title: Text('中文营养食物库'),
            subtitle: Text('已合并同名食物并整理分量，保留品牌、生熟及烹调方式的区别。'),
          ),
          const Divider(),
          Text(s.localFoodNoBarcode),
        ],
      ),
    );
  }
}
