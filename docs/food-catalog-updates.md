# 本次修改

常驻搜索入口、独立描述页、固定数量编辑布局、单行三餐热量。食物库更新使用固定GitHub仓库、Pages通知和不可变提交CDN下载；保留内置库与上一有效版本，历史MealEntity快照不修改，沿用旧食物ID。

维护更新：独立数据仓库编辑source/foods.jsonl，保留id，运行build_catalog.py，再执行Publish food catalog。营养修正由revision标记。
