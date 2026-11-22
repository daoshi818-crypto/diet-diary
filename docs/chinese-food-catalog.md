# 本地中文食物库

饮食日记的生产依赖注入使用 `ProductsRepository.local`：食品搜索、配方选材、AI 餐食匹配、条码查询均读取 `assets/foods/catalog.json`，不查询 Open Food Facts 或 Supabase。旧的 OFF/FDC 数据源代码保留用于兼容测试，不在应用中注册或初始化。

## 生成

在项目根目录运行 Python 3.10 或更新版本（只使用标准库）：

```powershell
py -X utf8 tool/build_chinese_food_catalog.py --source-root 'D:\吃有数' `
  --fatsecret-update 'D:\吃有数\抓取_20261122_0214'
```

读取以下真实输入，原文件不作修改：

- `report/13_中国食物成分表_主表_营养.csv`
- `report/07_食物库_卡路里与三大营养素.csv`
- `report/08_食物库_常用份量明细.csv`
- `fatsecret/有效数据.csv`
- `抓取_20261122_0214/全量原始.csv`、`有效数据.csv`：同一抓取快照；新快照覆盖旧同 key，有效表未收录的原始行隔离，不回退旧值。`--fatsecret-update` 可重复传入，较新的快照放最后。

生成的文件：

- `assets/foods/catalog.json`：随 App 打包的可搜索目录。
- `data/private_food_catalog/food_library.sqlite`、`food_library.csv`：独立本地数据库及 CSV。
- `data/private_food_catalog/catalog_manifest.json`：输入文件 SHA-256、实际数量和规则。
- `data/private_food_catalog/food_rejected.json`：异常/缺少关键字段的隔离记录及原因。
- `data/private_food_catalog/food_conflicts.json`：同名营养冲突的选定来源与其他原始版本，仅用于审计，不重复显示在搜索中。
- `data/private_food_catalog/food_name_corrections.json`：原名称、清洗后的名称与来源ID。
- `data/private_food_catalog/food_energy_corrections.json`：源表 kcal/kJ 列反置的修正依据。

清洗后的 `assets/foods/catalog.json` 随代码提交到当前私有仓库，便于自动构建；原始CSV及审计产物保留本地，不上传。程序不会在读取失败时回退远程库。

2026-11-21 第二版本机快照：13,730 条食物、19,007 条份量，共合并 1,283 条重复；隔离 1,605 条无法安全导入的数据，333 条名称完成规范化，335 组营养冲突中的 448 条其他版本进入审计文件。相比第一版额外去掉 421 条默认展示记录。每次重新生成以 manifest 的实际统计为准。

## 去重与营养单位

先规范 Unicode、HTML 实体、空白与括号。去掉“代表值/平均值”等非品种后缀；明确同义名如“鸡蛋（整个）”归为“鸡蛋”，“鸡蛋（煮）/水煮鸡蛋”归为“煮鸡蛋”。不同品种、生熟、烹调方式和品牌仍分别保留。名称含乱码替代字符、括号截断或无法确认的 OCR 错字（如源文件的“鸡蛋（者）”）进入隔离文件，不猜测修复。

清洗后名称、品牌与营养单位共同构成唯一身份，不再因同名食物的营养数值不同就重复展示。优先选择中国食物成分表，其次吃有数导出库，再其次 FatSecret；同源优先代表值和营养字段更完整的记录，最后用稳定ID确定次序。营养值不取平均，所有不同版本可在审计文件追溯；选定记录有明确的 `nutrition_source`。只有能量差不超过 `max(1 kcal, 1%)` 且各宏量差不超过 `max(0.2 g, 1%)` 时，才允许补充选定记录缺少的微量字段，避免拼出互相冲突的营养表。

份量按实际克重去重，同重量优先保留“小个/一碗”等具名份量；界面不再重复追加相同重量的克重快捷项，也不重复标注标签已有的克重。手动输入克重仍可使用。“一份”对应不同重量时显式写出克重。稳定 ID 包含来源、原始 ID、原名称、品牌与营养指纹；被合并记录的原始来源 ID 仍可解析到选定食物。

每 100 克或每 100 毫升为营养基准；宏量营养用 g，钠及大多数矿物质用 mg，维生素 A 用 µg RAE。未知微量营养保留为空，不补成 0；不溶性纤维不冒充总膳食纤维。饮品源数据明确为每 100 克时不擅自换成每 100 毫升，也不猜测一碗、一杯的重量。明确每毫升的饮品保留 ml，不用克字段或假定密度换算；克重仅由热量反推的记录隔离。成分表同时提供 kcal/kJ 且两列反置时，按明确的 4.184 换算关系改用原 kcal 数值，保留修正审计，不以宏量供能估算覆盖热量。

## 旧数据与条码

中文目录独立于用户 Hive 数据，无需破坏性迁移。旧远程缓存不再参与搜索或条码优先级，也不会用于详情远程补全；历史饮食、收藏、自定义食物和配方保持原样。用户明确创建的英文自定义食物或旧饮食记录仍可查看，不作为外部食物库删除。

当前导出不包含可靠的条码映射，不把数据库 ID 当作商品条码。扫码优先命中用户已保存条码的自定义食物；中文库未命中则提示未找到，不发送到 OFF。

演示食物按原始来源 ID 从同一中文库取得名称、营养和份量，删除了原来的英文硬编码食物与估算营养；图片仍为原有离线演示素材。演示配方的名称及说明也为中文。

## 验证

```powershell
py -X utf8 tool/test_build_chinese_food_catalog.py
flutter test --no-pub test/unit_test/chinese_food_catalog_test.dart test/unit_test/demo_meal_photos_test.dart
flutter analyze --no-pub
```

可选的本地网页预览：

```powershell
flutter build web --profile --no-wasm-dry-run --no-pub --target lib/dev/main_dev.dart --dart-define=PREVIEW_LOCALE=zh
node tool/serve_web_preview.mjs 4183
```

网页演示会重新播种演示档案；个人正常使用应从 `lib/main.dart` 启动。

## 自动构建APK

推送 `main` 或 `codex/chinese-food-catalog` 分支会运行 `Android APK` 工作流，验证目录和份量后构建签名的 release APK。工作流使用仓库加密的 Android 签名 secrets，签名文件不进入Git。构建产物 `diet-diary-apk-<运行编号>` 包含 `diet-diary.apk`、SHA-256 校验文件和 `BUILD_INFO.json`，在Actions页面下载，保留30天；main成功构建后同步到GitHub Release。

首个成功构建：Actions运行 `44857934349`，产物 `diet-diary-apk-1`。APK的SHA-256为 `f00ea808c8140fbc35c286cb41edd8a0ca38f3fa09020836acabed0e2bf416b3`；下载后已核对包内目录与仓库资产相同，签名证书与release密钥一致。

也可直接渲染真实 Flutter 页面生成中文截图，不启动浏览器、不写个人历史：

```powershell
$env:FOOD_PREVIEW_ICON_FONT = '<Flutter SDK>/bin/cache/artifacts/material_fonts/materialicons-regular.otf'
$env:FOOD_PREVIEW_FONT = 'C:/Windows/Fonts/msyh.ttc' # 可换成自己的中文字体
flutter test --no-pub --dart-define=GENERATE_FOOD_PREVIEW=true test/widget_test/chinese_food_preview_test.dart
```

截图位于 `preview/`（已忽略，不上传），包括真实中文搜索结果、份量选择和本地库说明。该截图测试默认跳过，显式启用后读取本机私人目录。

2026-11-20 本机验证：Python 导入测试 3 项通过，静态分析无问题；完整 Flutter 测试 3,620 项通过、6 项跳过、5 项失败。5 项失败均已在原始 `e394b684` 独立复现，涉及旧搜索筛选测试、日记编辑测试、两项 IPv6 地址校验测试及商店更新说明长度测试。中文食物库与截图测试通过；没有修改上述原有功能来消除这些失败。

2026-11-21 清洗修正验证：Python 5 项通过；相关 Flutter 94 项通过，真实页面截图另行启用通过；补充生成后的真实目录与演示引用回归 10 项通过（与前述部分重叠）。静态分析无问题，Web profile 构建成功。全库归一名称/品牌/单位重复为0，普通无品牌鸡蛋恰好1条；坏名称不进入目录；原始四份CSV的SHA-256不变。

2026-11-21 份量整理：13,730条食物、17,868条份量，比上一版减少1,139条同重量份量；导入及界面快捷项均按重量去重，保留具名份量与手动输入。Python5项、Flutter97项相关测试通过，静态分析无问题。

## 2026-11-22 更新

本次抓取原始13,771条、有效表13,686条；与历史三源数据合并后为19,546条食物、23,638条分量，候选重复合并1,332条，隔离729条。包含18,067条克重食物、1,479条毫升食物；普通无品牌鸡蛋仅1条。源成分表90行kcal/kJ反列已修正。数量均以本次manifest为准。

本机完整Flutter回归3,755项通过、6项跳过、0失败；静态分析无问题。Python导入与APK校验回归14+1项通过；再次生成目录逐字节一致，归一食物身份与同重量分量重复均为0。构建及发布工作流的YAML和Shell语法检查通过。

构建流程采用 `gradle/actions/setup-gradle@v5` 去重保存Gradle依赖和构建状态，保留单ARM64、构建前腾出runner空间及缓存前清理中间产物。关闭公开Build Scan上传。`tool/verify_android_apk.py` 在上传前核对ARM64运行库和APK内食物目录的逐字节一致性，`BUILD_INFO.json` 随Actions产物保存。首次仍需建立Gradle缓存，不把首次构建时长当作热缓存结果。
