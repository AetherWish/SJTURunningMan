# SJTU 一键校园跑工具 — Android → HarmonyOS NEXT 迁移报告

> 本项目仅用于学习、研究和技术测试。请遵守 SJTU 及相关平台的要求，不要用于伪造运动数据或规避体育锻炼要求。

## 一、迁移评估与总览

| Android 原始组件 | HarmonyOS 目标实现 | 状态 |
| --- | --- | --- |
| `MainActivity`（免责声明、根界面装配、重登录/路线回调） | `EntryAbility.ets` + `pages/Index.ets` | ✅ 完成 |
| `MainScreen.kt#RootScreen`（底部双页签） | `Index.ets` 中 `HdsTabs` 悬浮页签 | ✅ 完成 |
| `MainScreen.kt#MainScreen`（任务参数/按钮/日志） | `view/RunScreen.ets` | ✅ 完成 |
| `MainScreen.kt#AccountScreen`（登录状态/关于入口/登出） | `view/AccountScreen.ets` | ✅ 完成 |
| `LoginActivity`（jAccount OAuth WebView 登录） | `pages/Login.ets`（Web 组件） | ✅ 完成 |
| `RouteDesignActivity`（百度地图路线设计 + JS 桥） | `pages/RouteDesign.ets`（javaScriptProxy 同名桥 `AndroidInterface`） | ✅ 完成 |
| `AboutActivity` | `pages/About.ets` | ✅ 完成 |
| `MainViewModel`（StateFlow + 协程） | `viewmodel/MainViewModel.ets`（@ObservedV2 + @Trace + @Monitor + async/await） | ✅ 完成 |
| `ApiService`（OkHttp + WebViewCookieJar） | `service/ApiService.ets`（@ohos.net.http + webview.WebCookieManager 读取 Cookie） | ✅ 完成 |
| `DataGenerator`（坐标校正/路径调整/轨迹生成/分段） | `service/DataGenerator.ets` | ✅ 完成（算法逐行对齐） |
| `GpsUtil`（haversine/坐标读取） | `service/GpsUtil.ets` | ✅ 完成 |
| `RouteManager`（SharedPreferences + filesDir/routes） | `service/RouteManager.ets`（Preferences + 沙箱 filesDir/routes） | ✅ 完成 |
| `RouteInfo`（Parcelable data class） | `model/RouteInfo.ets`（interface，无需序列化器） | ✅ 完成 |
| `res/raw/route_coordinates.txt` | `resources/rawfile/route_coordinates.txt` | ✅ 已复制 |
| `assets/route_design.html` | `resources/rawfile/route_design.html`（原样复用，桥名不变） | ✅ 已复制 |
| `values/colors.xml` | `resources/base/element/color.json` + `resources/dark/element/color.json`（深浅色） | ✅ 完成 |
| 免责声明 AlertDialog（SharedPreferences 持久化） | `Index.ets` AlertDialog + Preferences(app_prefs/disclaimer_accepted) | ✅ 完成 |

### API 映射表

| Android API | HarmonyOS API |
| --- | --- |
| Activity | UIAbility / @Entry 页面（router 跳转） |
| Fragment / @Composable | @Component 自定义组件 |
| SharedPreferences | @ohos.data.preferences（同步 API） |
| WebView + WebViewClient | Web 组件 + onLoadIntercept / onPageEnd |
| CookieManager（WebView 同步） | webview.WebCookieManager（fetchCookieSync / deleteEntireCookieSync） |
| OkHttp | @ohos.net.http |
| Toast | promptAction.showToast |
| AlertDialog | AlertDialog.show |
| DatePicker (Material3) | DatePickerDialog.show |
| DropdownMenu | Select 组件 |
| Slider (Material3) | Slider 组件 |
| Gson | JSON.parse / JSON.stringify |
| kotlin.coroutines Job.cancel | 停止标记 taskStopped + running 状态 |
| UUID.randomUUID | 自实现 uuidV4()（utils/FormatUtil.ets） |
| String.format("%.Nf") | toFixed(N)（utils/FormatUtil.ets） |
| res/raw 资源 | resources/rawfile |
| INTERNET / ACCESS_NETWORK_STATE 权限 | ohos.permission.INTERNET / ohos.permission.GET_NETWORK_INFO |

## 二、代码交付结构

```
HarmonyOS/
├── AppScope/
│   ├── app.json5                          # bundleName com.sjtu.runner, versionName 4.2.0
│   └── resources/base/{element/string.json, media/app_icon.png}
├── build-profile.json5                    # compileSdkVersion/targetSdkVersion = 26.0.0
├── hvigorfile.ts
├── hvigor/hvigor-config.json5
├── oh-package.json5
├── MIGRATION_REPORT.md                    # 本报告
└── entry/
    ├── build-profile.json5 / hvigorfile.ts / oh-package.json5 / obfuscation-rules.txt
    └── src/main/
        ├── module.json5                   # UIMaterial.state=enable、权限、ability
        ├── ets/
        │   ├── entryability/EntryAbility.ets      # 窗口全屏沉浸 + 系统栏高度记录
        │   ├── pages/
        │   │   ├── Index.ets                      # 根页面（HdsNavigation + HdsTabs + 免责声明）
        │   │   ├── Login.ets                      # jAccount 登录（Web）
        │   │   ├── RouteDesign.ets                # 路线设计（Web + JS 桥）
        │   │   └── About.ets                      # 关于
        │   ├── view/
        │   │   ├── RunScreen.ets                  # 开润页（参数/按钮/日志）
        │   │   ├── AccountScreen.ets              # 账号页
        │   │   └── CommonComponents.ets           # SettingItem / DropdownSelection
        │   ├── viewmodel/MainViewModel.ets        # 业务状态 + 上传流程
        │   ├── service/
        │   │   ├── ApiService.ets                 # getUid / upload
        │   │   ├── DataGenerator.ets              # payload 生成
        │   │   ├── GpsUtil.ets                    # haversine / 坐标读取
        │   │   ├── RouteManager.ets               # 路线持久化
        │   │   └── CookieService.ets              # Cookie 统一读写/清理
        │   ├── model/{RouteInfo.ets, PayloadModels.ets}
        │   ├── utils/FormatUtil.ets               # 日期/UUID/定点小数等工具
        │   └── common/AppStorageUtil.ets          # 页面结果传递（等价 setResult）
        └── resources/
            ├── base/{element/{string.json,color.json}, media/*.png, profile/main_pages.json}
            ├── dark/element/color.json            # 深色模式配色
            └── rawfile/{route_coordinates.txt, route_design.html}
```

## 三、沉浸光感（Immersive Light）适配报告

工程配置：`compileSdkVersion` / `targetSdkVersion` = **26.0.0**（不低于 26.0.0，满足沉浸光感开启条件），`compatibleSdkVersion = 6.0.0(20)`，`runtimeOS = HarmonyOS`。

| 适配点 | 实现 | 材质档位与理由 |
| --- | --- | --- |
| 应用级开关 | module.json5 metadata `ohos.arkui.UIMaterial.state = enable` | 系统默认规则，跟随设备算力自适应 |
| 导航框架 | `HdsNavigation`（titleBar.mainTitle 交我润） | `titleBar.style.systemMaterialEffect`，MaterialType.ADAPTIVE / MaterialLevel.ADAPTIVE（推荐自适应档，系统按设备算力选择） |
| 底部页签 | `HdsTabs`（barOverlap 悬浮 + barFloatingStyle） | `systemMaterialEffect` ADAPTIVE/ADAPTIVE，barBottomMargin 24 |
| 日志面板 | `.systemMaterial(ImmersiveMaterial(REGULAR))` | 小面积局部容器，REGULAR 常规厚度；不与不透明背景色叠加，避免功耗浪费 |
| 账号卡片 | `.systemMaterial(ImmersiveMaterial(THIN, interactive: true))` | THIN 高透明 + 交互形变/点光源，增强可点击反馈 |
| 关于页 Logo 卡片 | `.systemMaterial(ImmersiveMaterial(REGULAR))` | 小面积容器 |
| 设备能力查询 | `hdsMaterial.getSystemMaterialTypes()`（Index.aboutToAppear） | 不支持 IMMERSIVE 时自动降级为 MaterialLevel.SMOOTH，避免低端设备卡顿发热（官方 FAQ 推荐做法） |
| 沉浸式窗口 | EntryAbility 中 `setWindowLayoutFullScreen(true)` + 透明系统栏 | 官方"方案一：窗口全屏模式"，一次性配置全局生效；HdsNavigation 通过 `ignoreLayoutSafeArea(SYSTEM)` 自行避让；轻量子页面（Login/RouteDesign/About）读取系统栏高度手动避让 |

约束遵守情况：
- 材质仅在局部小面积容器上使用，未整页大面积铺满、未嵌套叠加；
- 未在 systemMaterial 节点上再叠 `backgroundBlurStyle` 等模糊属性；
- 深浅色资源已分别提供（resources/base 与 resources/dark）；
- 弹窗（免责声明/删除确认/退出登录）保持系统默认样式，未自定义材质，保证低风险。

## 四、业务行为一致性说明

- 免责声明：首次启动弹窗，确认后进入主界面、拒绝则退出应用，持久化键 `app_prefs/disclaimer_accepted` 与 Android 相同。
- 登录：与 Android 相同的 OAuth URL / 移动端 UA / jaccount:// 外跳交我办逻辑；登录完成判定三条件（oauth2Login 回调页、JSESSIONID Cookie、pe.sjtu.edu.cn 主站页）逐条保留；进入登录页先清空 Cookie。
- Cookie：HarmonyOS 端 Cookie 统一存于 WebCookieManager；ApiService 每次请求读取该 Cookie 放入请求头，等价 Android 的 WebViewCookieJar 双向同步（差异：HTTP 响应中的新增 Set-Cookie 不再回写，Android 端该路径实际也不依赖）。
- 上传流程：步骤日志（步骤1 获取坐标路线 / 步骤2 获取 UID）、配速 4-6 分钟/公里随机、时间 ±10 分钟随机偏移、多天循环生成-上传、needRelogin 中断重登、"全部任务完成/任务已手动停止"日志文案均与 Android 一致。
- 路线：默认"思源湖路线"（rawfile 34 点）、自定义路线保存至沙箱 `filesDir/routes/{name}_{timestamp}.txt`、列表点数实时统计、默认路线不可删除、删除后回退默认路线，全部对齐。
- 参数：天数下拉+自定义、时间 6:00-22:00 下拉+自定义、日期选择器（默认昨天）、距离 1-5km 滑杆，与 Android 一致。

## 五、编译验证记录（DevEco CLI 实机构建）

构建环境：DevEco Studio 26.0.0 自带工具链（hvigor 6.26.4、ohpm、Node 24、SDK 26.0.0.105 / API 26），
`DEVECO_SDK_HOME` 指向 DevEco 安装目录下 `sdk/default`。构建命令：

```
node "<DevEco Studio>/tools/hvigor/bin/hvigorw.js" --mode module -p product=default assembleHap
```

首次构建暴露 21 处 ArkTS 编译错误，全部修复后 **BUILD SUCCESSFUL（0 错误）**，并已通过 clean 后全量重建验证。

修复清单：

| 文件 | 问题 | 修复方式 |
| --- | --- | --- |
| GpsUtil.ets / RouteManager.ets | `import { fs } from '@kit.CoreFileKit'` 报"fs is not exported"——本 SDK（API 26）中该 Kit 以 `fileIo` 名导出文件 IO 模块，并连带产生 5 处 any 类型推断错误 | 改为 `import { fileIo as fs } from '@kit.CoreFileKit'` |
| FormatUtil.ets（uuidV4） | 字符串下标访问 `hex[i]`（arkts-no-props-by-index） | 改为 `hex.charAt(i)` |
| CookieService.ets（clearAll） | 本 SDK 无 `deleteEntireCookieSync`，仅有异步 `deleteEntireCookie()` | `clearAll` 改为 async，先 `await deleteEntireCookie()` 再 `saveCookieSync()`，保持"清除→落盘"顺序；两处调用方（Login 页初始化、重新登录触发）无需变更 |
| Login.ets（onLoadIntercept） | `WebResourceRequest` 无 `getRequestURL`（大小写错误） | 改为 `getRequestUrl()` |
| Login.ets（onPageEnd） | API 12 起 `OnPageEndEvent` 已无 `data` 字段，直接提供 `url: string` | 改为 `event.url` |
| RunScreen.ets（×3） | `InputType.NUMBER` 不存在 | 改为 `InputType.Number` |
| RunScreen.ets（DatePickerDialog） | `start`/`end`/`selected` 参数类型为 `Date` 而非毫秒时间戳 | 直接传入 `Date` 对象 |

剩余告警（约 50 条，均不阻断构建）：
- **API 26 沉浸光感系提示**（`uiMaterial`/`systemMaterial`/`ImmersiveMaterial`/`ImmersiveStyle`/`REGULAR` 等"supported since SDK 26.0.0"）：属预期设计——本项目按需求以 `targetSdkVersion=26.0.0` 启用沉浸光感，`compatibleSdkVersion=6.0.0(20)` 下旧设备由系统降级处理（见"三、沉浸光感适配"及 TODO 2）。
- **废弃 API 提示**（`showToast`/`pushUrl`/`back`/`getContext` 等 deprecated）：均为当前版本仍可用的过渡 API，功能不受影响，后续可按官方指引迁移至 UIContext 系列新接口。
- 构建产物：`entry/build/default/outputs/default/entry-default-unsigned.hap`（未签名，签名配置见 TODO 1）。

## 六、真机兼容性修复记录（沉浸光感运行时守护）

**现象**：nova 12 Ultra（HarmonyOS 6.1.0.135，兼容运行时 apiCompatibleVersion=6.0.0(20)）真机运行，点击"我已同意，进入应用"后立即 jscrash：
`TypeError: Cannot read property REGULAR of undefined`，崩溃点 `RunScreen.ets:22`（日志面板材质字段初始化）。

**根因**：`uiMaterial.ImmersiveStyle` / `ImmersiveMaterial` 为 API 26 新增 API，SDK 26 编译期可见，
但该设备运行时的 ArkUI 兼容层未提供 TS 侧 `ImmersiveStyle` 枚举（字段初始化即求值，读取 `REGULAR` 抛 TypeError）。
对照日志：HDS 原生侧材质（`HDS_EFFECT MaterialModel::CreateMaterial`）工作正常，仅 TS 侧 `uiMaterial` 缺失，
说明设备差异只影响纯 ArkUI 声明式材质 API。

**修复**：新增运行时守护模块 `entry/src/main/ets/common/ImmersiveMaterialHelper.ets`：
- 首次调用时以 try/catch 探测 `new uiMaterial.ImmersiveMaterial({ style: ImmersiveStyle.REGULAR })` 是否可行（结果缓存）；
- 不支持或构造失败时返回 `undefined`；
- ArkUI 官方签名 `systemMaterial(material: SystemUiMaterial | undefined)` 显式接受 `undefined`，
  传入后组件自动回退为普通样式，无需调用方分支处理。

改造的 3 处调用点（字段初始化改为经守护工厂创建）：
| 文件 | 材质 |
| --- | --- |
| view/RunScreen.ets（日志面板） | `ImmersiveMaterialHelper.regular()`（REGULAR） |
| view/AccountScreen.ets（账号卡片） | `ImmersiveMaterialHelper.thinInteractive()`（THIN + interactive） |
| pages/About.ets（Logo 卡片） | `ImmersiveMaterialHelper.regular()`（REGULAR） |

**效果**：支持沉浸光感的设备（系统提供 ImmersiveStyle）效果不变；不支持的设备自动降级为普通不透明样式，不再闪退。
修复后已重新编译通过（0 错误）。Index.ets 中 HDS 原生侧能力查询（`hdsMaterial.getSystemMaterialTypes()`）原本即有
try/catch + SMOOTH 降级，且实测该设备原生侧正常，维持不变。

## 七、系统级 UI 重构与原生图标（第二轮迭代）

本轮对齐 HarmonyOS 系统应用的界面观感，三项变更均已通过 DevEco CLI 全量构建（0 错误）。

### 7.1 原生应用图标
- 移除程序生成的占位图标，将 Android 原版启动图标
  （`Android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.webp`，192px）直接应用于
  `AppScope/resources/base/media/app_icon.webp` 与 `entry/.../media/app_icon.webp`；
  HarmonyOS 资源目录原生支持 WebP，`$media:app_icon` 引用无需变更。

### 7.2 原生导航与二级页重构（对齐系统应用交互）
- 二级页从"独立 router 页面 + 手绘顶栏（'‹' 返回符）"重构为
  **HdsNavigation(NavPathStack) + HdsNavDestination** 体系：
  | 旧实现 | 新实现 |
  | --- | --- |
  | `router.pushUrl('pages/Login')` | `pathStack.pushPathByName('Login', null)` |
  | 自绘顶栏 Row + '‹' 返回 | `HdsNavDestination` 原生标题栏 + 系统返回控件（含侧滑返回） |
  | `AppStorage('loginResult'/'routeSaved')` 跨页传值 | 页面内直接回调 `MainViewModel`（logMsg/refreshLoginState/refreshRoutes） |
  | main_pages.json 4 个页面 | 仅注册 `pages/Index`，二级页走 navDestination 路由表 |
- Index 通过 `@Builder PageMap(name)` 注册 Login / RouteDesign / About 三个目的地；
  RunScreen / AccountScreen / LoginPage / RouteDesignPage 通过成员注入共享同一 `NavPathStack`。
- 登录成功 / 路线保存后的返回改为 `navStack.pop()`，业务回调直接驱动 ViewModel，等效原
  `startActivityForResult` 的结果回传语义。

### 7.3 HarmonyOS Symbol 系统图标替换 emoji/自绘图标
所有展示类图标统一替换为系统符号（`SymbolGlyph` / `sys.symbol.*`）：
| 位置 | 旧 | 新（sys.symbol.*） |
| --- | --- | --- |
| 页签"开润" | 自绘 ic_run.png | `figure_running`（BottomTabBarStyle + TabBarSymbol） |
| 页签"账号" | 自绘 ic_account.png | `person_crop_circle_fill_1` |
| 参数-跑步天数 | 📅 | `calendar` |
| 参数-开始时间 | ⏰ | `clock` |
| 参数-起始日期 | 🗓 | `calendar`（日期选择行同步替换） |
| 参数-跑步路线 | 🗺 | `map` |
| 参数-目标距离 | 🏃 | `figure_run` |
| 删除路线按钮 | 🗑 | `trash` |
| 自定义天数/时间确认 | ✓ | `checkmark` |
| 开始任务 | ▶ | `play_fill` |
| 停止任务 | ■ | `square_fill` |
| cookie 过期横幅 | ⚠️ | `exclamationmark_triangle_fill` |
| 账号页-关于入口 | ℹ️ / '›' | `info_circle` / `chevron_right` |
已删除不再使用的 ic_run.png / ic_account.png 与 AppStorageUtil.ets。
注：系统 `sys.symbol` 库无独立 `stop` 实心方块符号，以 `square_fill`（实心方块）等价替代原 ■ 图标。

### 7.4 主界面 HDS 列表卡片重构（第三轮迭代）
将主屏残余的 Material3 阴影卡片重构为 HDS 原生列表卡片，对齐系统"设置"类应用的列表观感：

| 位置 | 重构前 | 重构后 |
| --- | --- | --- |
| RunScreen 任务参数区 | 单个阴影大卡片（shadow + 自绘 Divider） | 分节标题 + 5 张 `HdsListItemCard` 卡片组（`Column({space:8})`） |
| 参数行结构 | SettingItem（自绘 Row：符号+标签+右侧控件） | `prefixItem`(PrefixIcon 系统符号) + `textItem`(主标题) + `suffixItem` |
| 起始日期 | 行内日期胶囊点击 | 整卡 `onClick` 弹出 `DatePickerDialog`，`SuffixText` 显示当前值 |
| 目标距离 | 全宽 Slider 行 | 卡片行内紧凑滑杆（`SuffixCustomBuilder` 承载 Slider+数值） |
| 开始/停止按钮 | 圆角 12 | 胶囊形（borderRadius 28，56 高） |
| AccountScreen 账号卡 | 阴影薄材质卡（systemMaterial） | `HdsListItemCard`（person_crop_circle_fill_1 + 主/副文本 + `SuffixArrow`） |
| AccountScreen 关于行 | 阴影 Row + chevron_right | `HdsListItemCard`（info_circle + `SuffixArrow`） |

配套改动：
- `CommonComponents.ets`：移除不再使用的 `SettingItem`；新增 `hdsPrefixIcon()`（显式类型构造
  `PrefixIconOptions`，规避 `PrefixIconType = ImageOptions | SymbolGlyphOptions` 联合类型的
  字面量限制）、`hdsLabelItem()`、以及结构兼容接口 `HdsCardOptions`。
- 后缀交互控件（天数/时间下拉、路线 Select+删除、距离滑杆）经 `SuffixCustomBuilder` 注入
  HDS 卡片，保持原交互与响应式更新。

**编译适配记录（重要经验）**：`@kit.UIDesignKit` 的 `HdsListItemCardOptions` 引用了未随
kit 导出的 `TextItemOptions`（kit 仅导出 `TextOptions`），ArkTS 严格检查器解析该接口失败，
导致所有以其为上下文类型的对象字面量均报 `arkts-no-untyped-obj-literals`（实测：const
声明、return 字面量、函数实参字面量均不通过；构造器 `new X({...})` 实参、项目内接口
注解的字面量可通过）。解法：在项目内声明结构兼容接口 `HdsCardOptions`（字段类型均为
kit 可见类型的子类型），字面量标注本地接口后传参，依赖 ArkTS 结构类型兼容完成赋值。
最终 `assembleHap` 构建通过（BUILD SUCCESSFUL）。

### 7.5 实机 Bug 修复轮次（第四轮迭代）
针对真机运行暴露的 4 个问题修复（`assembleHap` 构建通过）：

**Bug 1 — 内容贴顶/贴边（状态栏空间未预留）**，两个叠加根因：
- 窗口级：`EntryAbility.onWindowStageCreate` 中 `setWindowLayoutFullScreen(true)` 使窗口
  全屏布局，页面从物理屏幕 (0,0) 排布，叠加 Index.ets 原有的
  `ignoreLayoutSafeArea([SYSTEM],[TOP,BOTTOM])`，内容整体顶入状态栏，二级页返回键贴顶
  无法点击。修复：删除 Index.ets 的 `ignoreLayoutSafeArea`，EntryAbility 恢复
  `setWindowLayoutFullScreen(false)` 系统默认避让（显式设置以覆盖残留配置），同时移除
  透明系统栏配色（非全屏窗口下透明栏会透出壁纸，视觉异常）。
- 组件级：RunScreen 根布局 `.padding(16)` 后链式 `.padding({ bottom: 96 })`——ArkUI 同属性
  链式调用后者整体覆盖前者，导致左/右/上边距归零，运行日志与任务控制按钮贴边。
  修复：合并为单次调用 `.padding({ left: 16, right: 16, top: 16, bottom: 96 })`
  （bottom 96 仍为 HdsTabs 悬浮页签预留空间）。

**Bug 2 — 一级页返回按钮冗余 + 大标题**：
- 一级页（开润/账号）的 HdsNavigation NavBar 默认显示返回键，点击触发系统返回即退出
  应用，无存在意义。修复：`.hideBackButton(true)`（@since 5.1.0(18)，仅隐藏 NavBar 返回键，
  二级页 HdsNavDestination 自带返回键不受影响，已核对 d.ets 定义）。
- 新增贴左大标题：`.titleMode(HdsNavigationTitleMode.FULL)`，`mainTitle` 随页签动态切换
  （`selectedTab === 0 ? '开润' : '账号'`），对齐系统应用一级页交互。

**Bug 3 — 应用图标替换**：
- 工作目录根 `assets/SJTURM.png`（172,414 字节）同时落位 `AppScope/resources/base/media/`
  与 `entry/src/main/resources/base/media/` 的 `app_icon.png`；删除两处旧 `app_icon.webp`
  （`$media:name` 按基名解析，同名不同扩展名会资源冲突）；`app.json5`/`module.json5` 的
  `$media:app_icon` 引用无需变更。

**Bug 4 — FULL 大标题遮挡内容控件**：
- 根因：HdsNavigation 的 titleBar 是**悬浮层**，覆盖在内容区上方（官方文档所有示例均在
  内容首部放置与标题栏等高的 `Blank()` 占位符手动避让，内容滚动时从标题栏下方穿过呈现
  动态模糊）。FULL 模式仅主标题时标题栏高度为 **112vp**（主+副标题 138vp），而开润/账号页
  内容从 HdsNavigation 内容区顶部开始布局，直接被大标题覆盖。HdsNavigation 无内容区起始
  偏移属性（不存在 navBarContentStartOffset）。
- 修复：CommonComponents.ets 新增共享常量 `HDS_FULL_TITLE_BAR_HEIGHT = 112`；
  RunScreen 滚动内容与 AccountScreen 根布局的 top padding 由 16 调整为
  `HDS_FULL_TITLE_BAR_HEIGHT + 16`，控件置于大标题下方，滚动时内容穿过悬浮标题栏
  呈现 HDS 标准的动态模糊效果。

**经验记录**：沉浸式"窗口全屏 + 组件自行避让"方案需窗口、页面、组件三层协同，任一层
残留都会导致避让失效；排查此类问题应先查 `setWindowLayoutFullScreen`，再查
`ignoreLayoutSafeArea`/`expandSafeArea`，最后查组件级 padding。另注意：HdsNavigation
titleBar 为悬浮层，内容区不会自动让出标题栏空间，一级页内容首部必须预留等高避让空间。

## 八、待人工处理 TODO

1. **签名**：应用图标已替换为项目根 `assets/SJTURM.png`（落位 `AppScope`/`entry` 的 `app_icon.png`）；正式发布前请配置签名证书（build-profile.json5 的 signingConfigs，当前为调试签名）。
2. **真机回归**：HdsNavigation/HdsTabs 与沉浸光感为 HarmonyOS 6+ 特性，需在 DevEco Studio 6+（API 26 SDK）真机/模拟器验证；`compatibleSdkVersion=6.0.0(20)` 下，API 20~22 设备上 HDS 沉浸光感可能自动降级为系统默认样式。
3. **hvigor modelVersion**：按 DevEco 版本提示升级 `hvigor-config.json5` / `oh-package.json5` 的 modelVersion（当前 5.0.0，新 IDE 首次 Sync 会自动迁移）。
4. **后台连续任务（可选增强）**：Android 版上传在前台进行，HarmonyOS 版一致；若需退后台续传，可接入 `@kit.BackgroundTaskKit` 的 continuousTask。
5. **READ_PHONE_STATE**：Android 声明了该权限但未使用，迁移时未保留；如后续需要请按 HarmonyOS 权限规范另行申请。

## 九、测试建议

- **设备**：HarmonyOS 6.0.0+ 真机（高/中/低档各一），重点验证 HdsTabs 悬浮页签材质与日志面板材质在亮/暗色模式下的表现。
- **功能重点**：
  1. 首启免责声明（确认/退出/二次启动不再弹出）；
  2. jAccount 登录 → 回主界面登录态刷新 → 登出；
  3. 选 1 天 + 默认路线跑通"生成 → 风险日志 → 上传"全流程；
  4. 路线设计器：地图取点 → 保存 → 返回主界面列表刷新 → 删除自定义路线；
  5. 上传中途"停止任务"；cookie 过期场景自动跳转登录页。
- **兼容性**：低端设备确认材质降级为 SMOOTH 后无卡顿、无异常发热。
