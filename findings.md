# 调研

## 私有仓库与活动入口（2026-11-20）
- 共享ActivityVerticalList中的PlaceholderCard是首页/日记活动独立加号来源；删除它即可统一入口，现有活动卡、导入/分享/复制菜单保持。
- Git Credential Manager已保存GitHub账号daoshi818-crypto，可在内存中供GitHub CLI调用，无需保存token到项目或重新登录。
- 私有仓库为daoshi818-crypto/diet-diary；Actions已关闭，防止上游main推送触发Android构建与发布。
- 原上游源码、许可证和历史保留；上传只推送本项目main，不推送全部上游分支或标签。
- 工作区 D:\食记 初始为空。
- 目标仓库 HEAD: 5048a9b57f4ab08b17699af556c280f7f058e07c。
- 本机有 Node/npm/Python；未检测到 Flutter 命令。
- 上游 `AGENTS.md` 确认项目为 Flutter，已有 `lib/l10n/intl_zh.arb` 且 `shipped_locales.dart` 已 ship `zh`。
- 上游运行时数据为本地 AES 加密 Hive；此预览的浏览器 localStorage 仅为 UI 演示，并非原生数据库迁移。
- 仓库 AI 调研文档指出正式集成应遵循 opt-in / BYO-key；网页按 OpenAI 兼容接口支持自有密钥，不内置代理或凭据。
- Vite build 通过：vite 6.4.6，4 modules，输出 23.56 kB CSS / 26.74 kB JS。
# 2026-11-20 用户方向修正
- 交付必须是官方 Flutter 源码编译的 Web；不得以 HTML/CSS 重写替代。
- 当前固定 SDK 为 Flutter 3.44.6；仓库无 web/ 平台目录。
- 重点兼容：启动的原生文件检测、dart:io 网络防护、原生插件以及演示图片存储。
- 官方页面和导航不修改；前面 src/ Vite 原型不是认可的交付。


## 最终交付基线（替代上文 Vite 结论）
- 真正 Flutter Web 产物运行于 http://localhost:4173/，入口为官方 lib/dev/main_dev.dart。
- 使用官方 Hive Web/IndexedDB 和官方演示种子；每次重载重播种，不是旧 localStorage 原型。
- 只做 Web 平台适配，官方主要页面、主题和导航无改动。
- 正式后端未配置；营养成分表 AI 新功能和本地食物库接入仍待在 Flutter 中实现。
- Flutter 构建不要来回切换中文目录和英文 Junction：SDK 的 trackSharedBuildDirectory 按字符串比较输出路径，会将同一物理文件当作旧输出删除。若遇到资源清单缺失，在同一路径补跑一次即可恢复；启动脚本已涵盖此恢复并检查 manifest/font。

## UI 改版定位
- 官方已有 BulkAddScreen 图片/文字 AI 流程，可以从中央入口直接复用，真实服务仍取决于用户配置。
- IntakeVerticalList 的 PlaceholderCard 是三餐/加餐独立加号来源。
- 官方详情页 MealDetailScreen + MealDetailBottomSheet 已有用量/单位/份量控制；优先复用，避免只支持克重的旧 EditDialog。
- 食物搜索加号在 AddMealScreen._onQuickAddToTray，原来直接 defaultLogTrayItem 100g；改为确认选择后加入待记录清单。

## UI 确认稿验证（2026-11-20）
- 最终8文件回归67项全部通过，flutter analyze无问题。
- 最新Flutter Web已reload，中央添加面板五张圆角卡片与底部关闭已截图；食物库入口正常。
- 演示数据食物名称沿用官方英文，不应误称本地中文食物库已接入。
- 浏览器食物库加号先弹用量卡，150g后热量123→185；确认才出现待记录1项（150g/185卡），与要求一致。
- 浏览器录入成功返回主页后触发SDK调度异常：Scaffold.geometryOf() must only be accessed during the paint phase，之后点击未响应；开始隔离是否与成功提示/BottomAppBar有关。
- 异常不仅录入后出现，编辑保存后的官方提示条也会触发；定位SDK RenderPhysicalShape.hitTest→BottomAppBar clipper→Scaffold geometry paint-only断言，鼠标更新后持续断言。预览改用profile编译（保留官方dev数据、主题和凹槽导航），不改UI或SDK。后续必须实测提示条结束后仍可点按。
- 紧凑版17项定向测试全部通过：360×640五入口和关闭无需滚动可点击，双列对齐，面板高度<480；375×667/812×375亮暗色与双倍字体/减少动画，详情和用量卡无布局异常。
- Profile预览三点菜单正常，午餐160g食物移至加餐后午餐变空，全天营养条未增加。
- 浏览器最新紧凑版360×640实拍：面板从约y213到628，五入口/四餐chips/活动食谱/关闭全部显示，无裁切；截图build/ui-hub-compact-360.jpg。
- 最新profile构建已实测小屏食物库150g选择→待记录150g/185卡→记录返回主页，总摄入由2898到3082（官方逐项取整规则）；后续核对中央加号仍响应。
- 最新profile录入后中央加号可重新打开，已确认恢复交互；横屏与小屏检查完成，浏览器viewport override已reset。

## 第二轮UI验证进展
- 10文件联合回归87项全部通过；flutter analyze无问题。
- 360×640浏览器添加卡片约y171–539，下方独立56px圆形关闭键完整可见。
- 官方表单创建临时自定义食物后返回食物库，无需刷新即出现在自定义标签，真实Hive监听路径有效。
- 自定义标签中的燕麦搜索未跳到全部；午餐快速加号选择150g后待记录显示570卡，最终记录成功，首页总摄入由2898变3468，提示后页面仍响应。
- 已核对首页活动出现在加餐食物之后、列表底部；保留官方活动添加入口。详情圆形关闭键与卡片有独立间隔，点击可关闭。
- 新版profile构建成功（136.5秒）；分析无问题；11文件联合回归101项全部通过。新增仪表盘普通字号总高低于280px、圆环高≤130px，双倍字号/亮暗色/千焦五位数/横屏无异常。
- 新网页已reload并核对实际视口360×640：摄入-圆环-消耗同排，首屏已显示早餐标题，主卡约150px高（原约324px）。
- 最终饮水胶囊为纯进度展示，去除home-water-edit以及直接打开水量对话框的行为；中央统一入口仍可打开记录饮水量。最终截图build/ui-round2-final-home-360.jpg。

## 饮食日记品牌资源
- 新名称同步16个语言资源的应用标题和通知标题；中文应用描述保留OpenNutriTracker来源。
- 首页、启动页、关于使用同一个SVG标记，浏览器favicon/PWA和Android/iOS启动图标由SVG派生，iOS/PWA maskable底色满幅无透明圆角。
- SVG主文件assets/icon/diet_diary_icon.svg；再生脚本tool/generate_diary_brand_assets.dart，无新增运行依赖。
- 品牌核对覆盖：首页SVG、应用信息、启动路由、网页title/favicon/manifest、原生桌面图标尺寸。技术包标识与Hive数据结构未改。

2026-11-23: 本地批量原来直接写日记，已改为加入共享 LogTray；个人食物映射延迟到真正写日记成功之后。UI 路由 CLI 因本机 esbuild EFTYPE 不可用，沿用项目实际 AppPalette/buildAppTheme。截图通过 Flutter 真实控件与本地食物库生成。
# 2026-11-23 分类接入
- 随包 19,546 条食物，81 个原分类值；14,900 条为 brand/generic，不能直接作为浏览分类。分类必须归一，并保留不确定项到其他，不能按品牌当作食物类别。
- 现有云端更新按固定提交下载完整 catalog，经 SHA256、字节数、条数与结构验证后切换，缓存当前/前一版本。分类扩展采用同文件可选 categories + 食物 category_id，旧客户端忽略附加字段。
- 当前分类 HTML 只是原型；用户已确认实现固定侧栏，无分类按钮。录入模式与营养计算复用现有 FoodQuantityDialog/MealDetailBottomSheet。

## 2026-11-23 食物库边缘
- 分类栏继承了整个内容列的 horizontal:16；改为只给顶部控件和无本地分类的结果保留边距。
- SafeArea 位于记录区 Material 外侧，导致底部手势安全区露出 canvas。将 SafeArea 放入 Material 内，背景延伸而操作按钮仍避开安全区；页面级 AnnotatedRegion 关闭导航栏对比度遮罩并设置透明背景及主题对应的图标亮度。
- 原始清单使用 AppModalSheet 后再开用量 sheet，会叠加关闭按钮；改为页面内清单后只保留单一用量面板。
