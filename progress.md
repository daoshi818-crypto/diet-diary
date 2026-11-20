# 进度

## 当前任务：活动入口与私有仓库（2026-11-20）
- 用户明确授权创建私有仓库及上传，覆盖历史阶段的不提交/不推送限制。
- 已通过 Git Credential Manager 保存的凭据验证 GitHub 账号 daoshi818-crypto，无需重新登录；凭据仅在进程内使用，不写入项目。
- 首次批量补丁因进度文件锚点错误被拒绝，读回确认未写入后修正补丁。
- 本轮使用 planning-with-files 和 verification-before-completion，继续维护文件计划并以实际验证结果验收。
- 已移除共享活动列表的添加占位卡和专用跳转代码；首页/日记同时生效。新增空/非空列表回归及中央活动入口日期传递测试，4文件共23项通过；flutter analyze --no-pub 无问题。
- 上传前候选1281个文件的高置信密钥模式扫描无命中，无超过10MB文件；.env、env.g.dart、SDK、build和旧原型均被忽略。额外排除环境变体与签名私钥文件。
- 已创建 GitHub 私有仓库 daoshi818-crypto/diet-diary，API确认 isPrivate=true、Actions enabled=false。原上游remote改为upstream，新origin指向私有仓库；本仓库提交身份使用已验证账号的noreply地址。
- 第二次记录补丁因调研文件锚点错误被拒绝，读回确认后已按实际标题修正，未产生部分写入。
- 最终profile Web构建成功（84.8秒），分析无问题；静态服务与4项关键资源HTTP 200，Node/PowerShell预览脚本语法及git diff --check通过。
- 浏览器读回：首页和日记活动区均无独立添加卡片，原有有氧舞蹈记录正常；中央加号→活动打开官方活动列表。截图build/ui-activity-no-plus.jpg与build/ui-diary-activity-no-plus.jpg（不上传构建目录）。
- 首次暂存后的完整空白检查发现新增预览启动脚本末尾多一空行（先前未暂存检查不含新增文件）；提交尚未执行，已只删除该空行并重新检查。
- 代码提交e3a718f6（157文件）已推送origin/main，远端API确认完整SHA与本地一致、仓库private=true、默认分支main、Actions=false；1281个已提交文件路径均无被排除配置，许可证和上游基线历史保留，工作树干净。
- 仓库：https://github.com/daoshi818-crypto/diet-diary 。本地交互预览继续位于http://localhost:4173/；未打包APK。此后仅同步本段验收记录。

- 2026-11-20：开始克隆上游，读取 UI、文件计划与验证技能。
- 2026-11-20：确认上游已 ship 简体中文，创建独立 Vite 中文网页预览；`npm install` 和 `npm run build` 均通过。
- 2026-11-20：浏览器验证日记与 AI 标签识别示例；本地预览 HTTP 200，`node --check` 与生产构建通过。补充 `网页预览说明.md`。
# 2026-11-20 改用真正 Flutter Web
- 用户拒绝仿制 UI；停止 Vite 作为交付。
- SDK 已安装到 .tools/flutter，确认 3.44.6 / Dart 3.12.2。
- 使用 flutter create --platforms=web --no-pub 为原工程增加 Web 宿主，不重写 lib/ 页面。
- 正在安装 pub 依赖。兼容改动集中于 IndexedDB、健康服务的平台判定、平台 locale、网页缓存和不可用的购买插件。
- 采用官方 lib/dev/main_dev.dart 演示入口，使用官方 seedDemoData。

## 2026-11-20 官方 Flutter Web 验证完成
- 恢复上游 pubspec.lock；首页、日记、趋势、个人页、main_screen 和 app_palette 与 HEAD 无差异（逐文件检查共 6 个）。
- 新构建：flutter build web --debug --no-wasm-dry-run --target lib/dev/main_dev.dart --dart-define=PREVIEW_LOCALE=zh --no-pub，退出码 0，94.3 秒。
- flutter analyze --no-pub：No issues found。
- locale、user_image_storage、demo_meal_photos、products_repository_ranking 四个测试文件共 21 项测试全部通过。
- 浏览器 430×932 检查首页、日记日历、趋势图、个人页和官方添加菜单；未使用仿制页面。
- 静态服务 localhost:4173 提供 build/web，首页和 main.dart.js 返回 200，/.env 返回 404；node --check 与 git diff --check 通过。
- 网页预览说明.md 已重写；旧 Vite 原型已归档，不把其 AI 演示功能算作 Flutter 已实现。
- 最新构建复查发现路径别名切换时 Flutter 把新资源作为旧输出清理（trackSharedBuildDirectory 按路径字符串比较）；在相同路径重跑构建后 4.6 秒恢复，50 个资源文件齐全，AssetManifest.bin.json 返回 200。
- 启动脚本新增资源完整性检查，并针对该已确认的别名清理问题在缺失清单时补跑一次构建；PowerShell 语法检查通过。

## UI 改版实现
- 中央加号保留官方主题，统一五个圆角卡片入口；顶部餐次选择和日期，底部固定关闭。活动与食谱原有入口保留为次级按钮。
- 详情营养按 IntakeEntity.amount 计算，浮窗显示热量/三大营养素与调整用量/关闭。
- 用量确认弹窗直接嵌入官方 MealDetailBottomSheet，增加返回选择模式，不进行自动写入；支持多份量和50/100/150/200g预设。
- 编辑复用相同记录控件；食物库加号确认后加入待记录清单，最终点击记录才写入。
- 修改餐次原地更新 Hive 记录 type，不复制/删除，保持id/时间/用量及全天统计。
- 原中文零食3处按用户明确要求改为加餐；新文案添加英/中资源并由gen-l10n生成。
- 第一轮29项测试通过。扩大回归发现旧食物库测试仍假设点击加号立即添加，同时新选择弹窗不需要却初始化了记录Bloc；已去除选择模式对Bloc的依赖，并更新回归用例覆盖确认/取消/150g实际写入。
- 新布局回归第一次编译失败：误用tester.view.setSurfaceSize，已改为TestFlutterView.physicalSize/devicePixelRatio。
- 大字体中文布局测试补齐与生产一致的Material/Cupertino/Widgets中文delegate，首次测试壳漏配导致所有用例未能打开，不是应用布局失败。
- 按用户追加的小屏要求，把添加面板改为紧凑版：标题添加、日期同行、餐食主卡+四入口双列，去掉重复说明，内容整体可滚动、底部关闭固定。
- 最终9文件联合回归80项全部通过，flutter analyze无问题；profile Web构建成功79.8秒。
- 浏览器已实测360×640、375×667与812×375，横屏可滚到全部入口、关闭持续可见；亮暗色/双倍文字/减少动画用widget测试覆盖。
- 饮水和AI文字卡片均打开官方流程；没有调用实际AI服务。
- Profile版本实测录入后提示条动画结束，中央加号可再次打开，调试模式的点击失效未再发生。
- 预览与AssetManifest HTTP均200，启动脚本PowerShell语法检查、node --check、git diff --check及4个新增/关键widget的format检查通过。
- 最终确认图：build/ui-hub-compact-360.jpg、build/ui-hub-compact-375.jpg；浏览器恢复默认尺寸并保留交付。未打包APK、未提交或推送。

## 第二轮UI调整
- 已实现自定义库标签（直接读取CustomMealBox并监听改动），库页面四餐选择贯穿详情和录入；初始参数只读取一次，防止依赖重建重置餐次。
- 首页及日记活动列表移到四餐之后。添加及详情复用浮窗卡片容器，关闭为卡片外56px圆形按钮。
- 第一轮布局和日记22项通过；新增录入测试误写辅助函数名，已更正并补齐详情路由餐次断言。

- 本轮profile网页构建成功（88.1秒）。自定义库回归失败定位为AutoSizeText.rich尾部品牌文本使精确Text finder匹配不到，已改为现有富文本包含查找；正在运行10文件联合回归。
- 浏览器自定义筛选实测：官方表单新建预览测试燕麦，返回后列表即时更新；输入燕麦仍保持自定义标签且结果正确。已选午餐并打开150g用量确认，继续核对实际落餐。
- 已实测自定义食物150g/570卡记录到午餐，营养详情显示午餐、150g及碳水93g/脂肪10.5g/蛋白质19.5g；卡片外圆形关闭按钮可关闭。截图build/ui-round2-details-360.jpg。

## 追加：压缩卡路里区域
- 按用户最新要求改为摄入/124px圆环/消耗同排，卡片内边距12px。大字/极窄布局回退纵排，保留目标详情的语义及点击入口。
- 新增12组360/375/横屏、亮暗色、普通/双倍字、千焦五位数测试。首次紧凑高度测试测得整区291px超过280px验收上限（无溢出）；进一步压缩营养卡内边距和进度条上下间距后重测。

## 追加：饮水入口统一
- 删除QuickWaterWidget中的加号和点击录入，保留水量显示；记录饮水仍通过中央添加卡片。
- 饮水及中央入口9项回归全部通过。新版重新构建中。
- 上一轮11文件联合回归101项全部通过；压缩卡路里已在浏览器360×640和375×667核对，首页首屏能显示早餐标题。
- 最终饮水版profile构建成功86.8秒，flutter analyze无问题；等待最终浏览器读回与截图。
- 最终浏览器360×640已核对饮水旁加号消失、紧凑热量区正常、中央入口仍能打开记录饮水量；取消测试未新增水量。首页截图build/ui-round2-final-home-360.jpg。
- 375×667及812×375已检查，横屏卡片可滚到AI入口且圆形关闭持续可见；日记活动在加餐之后。
- 交付保持官方Flutter工程；未打包APK、未提交或推送。

## 饮食日记更名与图标
- 采用矢量SVG原创标记，绿色底、日记本、餐盘与叶子，使用现有Flutter SVG渲染器导出PNG，不引入依赖。
- 首次补丁因同一文件含delete/add两条操作被工具拒绝，检查确认未写入，已改为单个update补丁完成。
- 标题及通知应用名同步各语言资源，中文自称更新并在应用描述保留OpenNutriTracker来源；系统显示名、Web manifest和标签同步。
- 49项相关测试通过（品牌/仪表盘/语言24项，设置/引导25项）；最终flutter analyze无问题。
- 58个平台图标尺寸和16份应用标题资源校验通过；favicon源码和build产物SHA256一致，依赖锁文件未改。
- 最终profile网页构建成功98.8秒；浏览器标题饮食日记，应用信息显示新图标和名称，截图build/ui-diary-brand-about.jpg。
- Android/iOS只更新资源与显示名称，没有打包、提交或推送。
