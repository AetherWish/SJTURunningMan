# HarmonyOS NEXT 端使用指南

版本 **`4.5.0`**，Bundle Name `com.sjtu.runner`（`apps/harmonyos/AppScope/app.json5`）。工程路径 `apps/harmonyos/`。

> 功能与安卓端对齐：参数范围、任务流程、路线预览、状态统计、运行日志、检查更新均由鸿蒙原生 ArkTS/ArkUI 独立实现（HDS 组件 + 沉浸光感），不做代码共享；差异仅在安装方式、系统权限与登录入口。

![鸿蒙主界面](./images/harmonyos-main.webp)

## 目录

- [1. 安装 HAP 包](#1-安装-hap-包)
- [2. 登录](#2-登录)
- [3. 参数配置](#3-参数配置)
- [4. 开始上传](#4-开始上传)
- [5. 自定义路线](#5-自定义路线)
- [6. 权限说明](#6-权限说明)
- [7. 与其他端的差异](#7-与其他端的差异)
- [8. 已知的 ArkTS 工具链陷阱](#8-已知的-arkts-工具链陷阱)
- [9. 路线长度与预览限制](#9-路线长度与预览限制)

## 1. 安装 HAP 包

> ⚠️ **强烈建议提前完成华为账号的开发者认证**，以延长调试证书有效期。未认证时调试证书有效期很短，装完没多久就会失效需要重装。

1. 到 [Releases](https://github.com/JackyTJie/SJTURunningMan_Advanced_Edition/releases) 下载 HAP 文件；
2. 手机上：**设置 → 关于本机 → 连点「软件版本」7 次**，重启后启用开发者选项；
3. 进入 **设置 → 系统 → 开发者选项 → 无线调试**，打开并记录显示的 IP 与端口；
4. PC 与手机连同一网络，下载 [小白调试助手](https://github.com/likuai2010/auto-installer) 并运行，按软件内指引配置安装。

## 2. 登录

1. 首次进入会先显示**使用承诺书**，勾选后点「我承诺，进入软件」；点「退出」会直接结束应用。同意状态保存在 `app_prefs/commitment_accepted`，之后不再弹出；
2. 点击首页标题栏**右上角的账号图标**即可跳转到登录页（未登录时图标下方显示「登录」，已登录显示「账号」；已登录时点击会弹出「退出账号」确认）；
3. 页面加载与登录完成后自动返回，状态卡片显示「已登录」。失效时会自动重新登录。

> ⚠️ 鸿蒙端**无法拉起「交我办」快捷登录**，只能走 JAccount 网页登录。若系统已安装「交我办」，登录页会尝试唤起它；未安装时提示后留在网页登录。

## 3. 参数配置

首页**没有底部页签**：标题（「开润」）与右上角的**账号**、**关于**两个图标按钮在同一行（`HdsNavigation` 的 MINI 标题模式）。「开润」页面从上到下依次为状态卡片、路线卡片、任务设置卡片与运行日志区。

| 参数 | 范围 | 默认 | 说明 |
| --- | --- | --- | --- |
| 跑步次数 | 1–30 次 | 1 | 下拉框可选 1/3/5/7/10/15/30，或选「自定义…」手动输入（此时下拉框内显示「自定义」） |
| 开始时间 | 时 0–23 / 分 0–59 / 秒 0–59（即 00:00:00–23:59:59） | 08:00:00 | 点按弹出系统时间选择器（24 小时制、时分秒三列）；每条会加 **±10 分钟 / ±30 秒** 随机波动（说明折叠在标签旁的「圈 i」图标里，点按查看） |
| 结束日期 | 日期选择器 | 昨天 | 以此为最新一条向前生成；点按整行弹出 |
| 跑步距离 | 1–5 km | 4 km | 单条目标距离，滑杆步长 0.1 km；数值显示在「目标距离」标签下一行、与标签左对齐 |
| 跑步路线 | 见下 | 思源湖路线 | 下拉选择，可在新页面连点设置 |

参数范围来自 `apps/harmonyos/entry/src/main/ets/config/AppConfig.ets`。首页与「关于」页的滚动条均为 `BarState.Auto`（滚动时显示，静止后淡出）。

任务设置的每一行都是自绘的 `SettingCard`（`apps/harmonyos/entry/src/main/ets/view/CommonComponents.ets`）：左侧系统符号图标列 + 标签列宽度固定，因此各行的图标左边缘与标签左边缘严格对齐；控件列宽度由 ArkUI 正常测量。为什么不用 `HdsListItemCard` 承载这些交互控件，见第 8 节。

## 4. 开始上传

1. 点底部「开始任务」按钮；
2. 状态卡片显示当前阶段（准备中 / 获取认证 / 生成数据 / 上传中 / 正在停止 / 已完成 / 失败）与进度条；
3. 路线卡片可点「预览路线」按当前设置**离线生成**一条轨迹，显示距离 / 点数 / 跳段数与轨迹散点画布；
4. 完成后日志区给出「任务完成: 成功 N 条，失败 M 条」，可点「清空」清除日志（最多保留 400 条）。

若所选路线长度超过目标距离，会弹出「路线距离提醒」，可选择**削减路线**（自动截断至目标距离）或**取消任务**；点「完整路线」则按整条路线跑步并同步目标距离。

任务进行中可点「停止任务」中断。停止在下一轮循环边界生效；若此时正有一次上传在途，会等该请求返回（最长 20 秒读超时）后再结束，界面不会卡死。

## 5. 自定义路线

1. 进入路线设计页，在地图上**依次连点**选择坐标点；
2. 点越多越贴合，**注意点是有顺序的，且起始点与终止点越接近越好**；
3. 保存后回到主界面，在下拉列表中选中新路线即可开跑；非内置路线可点「删除路线」删除。

具体的坐标格式、坐标系差异，见 [routes.md](./routes.md)。

## 6. 权限说明

`apps/harmonyos/entry/src/main/module.json5` 申请：

| 权限 | 用途 |
| --- | --- |
| `ohos.permission.INTERNET` | 访问 pe.sjtu.edu.cn 上传数据、检查更新 |
| `ohos.permission.GET_NETWORK_INFO` | 判断网络可用性 |

鸿蒙端**不读取定位、不读取电话状态**：轨迹由所选路线离线插值生成，上传坐标由路线坐标加固定偏移得到，与安卓一致。

## 7. 与其他端的差异

| 项 | 安卓 | 鸿蒙 |
| --- | --- | --- |
| 安装方式 | 直接装 APK | 需 HAP + 调试证书（有效期有限） |
| 快捷登录 | 支持交我办 | 不支持，仅 JAccount 网页登录 |
| 权限 | INTERNET / ACCESS_NETWORK_STATE / READ_PHONE_STATE | INTERNET / GET_NETWORK_INFO |
| 参数范围 | 1–30 次 / 1–5 km | 同安卓 |
| 界面组件 | Material 3 (Compose) | HarmonyOS Design 组件 + 沉浸光感（带控件的参数行改为原生自绘卡片，见第 8 节） |
| 路线资源 | `route_design.html`（百度地图） | 同一份资源，另存一份（桥接对象仍名为 `AndroidInterface`） |
| 关于 / 更新 | 对话框 | 独立「关于」页 |
| 路线预览配色 | Material 主题色 | 与地图同源的固定蓝橙配色（`RoutePreviewCanvas.ets`） |
| 自动化测试 | JVM 单元测试 | 暂无 |

自行编译与打包见 [build.md](./build.md)；路线坐标系说明见 [routes.md](./routes.md)。

## 8. 已知的 ArkTS 工具链陷阱

以下问题能通过编译，只在真机运行时才暴露，改动界面时需要留意。

**自定义组件不能直接写在传给外部组件的箭头函数里。** ArkTS 编译器只会把处于声明式 UI 上下文中的
`Foo({...})` 重写成 `new Foo(this, {...})`。把自定义组件写在对象的箭头函数属性里（例如
`new SuffixCustomBuilder((): void => { DistanceSlider({...}) })`）时不会重写，运行到该闭包即抛
`TypeError: class constructor cannot called without 'new'`，应用直接闪退。正确写法是把组件放进 `@Builder`
方法，再由闭包调用该方法：

```typescript
@Builder
DistanceSliderBuilder() {
  DistanceSlider({ /* ... */ })
}

// suffixItem: new SuffixCustomBuilder((): void => { this.DistanceSliderBuilder() })
```

> 验证方法：构建后查看 `entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/` 下的
> 中间产物 `.ts` 文件，确认组件被重写成 `new Foo(this, {...})`；仍是裸调用 `Foo({...})` 就一定会崩。

**HDS 卡片的自定义后缀不参与尺寸测量。** `HdsListItemCard` 的 `suffixItem` 只接受
`SuffixCustomBuilder`，其后缀内容既不参与卡片的宽度分配、也不参与高度测量：实测把 8 个
选项胶囊放进后缀区时，卡片高度仍是按 `SuffixText` 固定行高算出的 64vp，后缀里的
`Flex` 却按“屏幕宽度”换行并向上溢出，胶囊被画到卡片外、与上一张卡片的按钮重叠。

因此**带交互控件的参数行不要放进 `HdsListItemCard` 的后缀**，改用原生 ArkUI 自绘卡片
（`apps/harmonyos/entry/src/main/ets/view/CommonComponents.ets` 的 `SettingCard`）：卡片外观
（`card_surface` 底色、16vp 圆角、16vp 内边距、系统符号 + 固定宽度的图标列与标签列）与
`HdsListItemCard` 对齐，控件列用 `layoutWeight(1)` / 100% 宽度交给 ArkUI 正常测量，尺寸自适应。
**任务设置的四行全部用 `SettingCard`**（含结束日期这类静态行，用 `valueText` 参数把值右对齐）：
一旦混用 `HdsListItemCard` 与 `SettingCard`，两者的图标列宽度不同（84px vs 78px），
行与行的标签左边缘就会差 21px 左右。

> 需要宽控件的行（目标距离滑杆）用 `SettingCard` 的 `fullWidth` 模式，把标签移到控件上方：
> ArkUI 的 `Text` 有 64vp 的最小宽度且不随内容收缩，并排布局下标签列会吃掉一截宽度。
> `SettingCard` 的标签列宽度也**不能小于 64vp**，否则「跑步次数」这类 4 字标签会折成两行
> （实测 43vp 时四行有三行折行）。

**滑杆的数值不要放在父组件里读。** 目标距离的数值由 `DistanceSlider` 组件自己读 `@Prop distanceKm`
渲染（`showValueRow: false` + `valueIndent: SETTING_CONTENT_INDENT`，缩进量就是「图标列 + 标签列」宽度，
因此数值与「目标距离」标签左对齐）。把同样的文本写在 `SettingCard` 的标签行里会读到陈旧值：
在 `@BuilderParam` 的内容里发出的 @State 写入不会让父组件重新构建（实测滑杆值已变为 `4.400000`，
父组件的 `headerTrailing` 仍是 `4.0`）。父组件持有唯一数据源、滑杆通过 `onDistanceChange` 回调上报，
这一组合是稳定的；把回调用「组件方法引用」（`onDistanceChange: this.onDistanceChange`）传过去会让
点按滑杆时应用直接退出，务必用调用处的箭头函数。

**相邻同类型参数的实参顺序写反，静态检查不会报错。** `generate()` 的前两个数字参数是
`targetDistanceM`（米）与 `startTimeMs`（毫秒时间戳），两者都是 `number`，把实参写反照样编译通过。
曾因此把 `Date.now()` 当成目标距离传给算法（约 `1.79e12` 米），凑距离的圈数涨到十亿级，
预览时直接把堆撑爆导致闪退。调用处请按形参顺序传参并加注释；算法内部对目标距离量纲有兜底自检
（见第 9 节），但根因应在调用处修正。

## 9. 路线长度与预览限制

轨迹是按所选路线离线插值生成的：先把相邻坐标点按目标步长加密，再整段复制若干圈凑到目标距离（`completeLoops = 目标距离 / 单圈长度`）。

因此**路线不能过短**：若在地图上几乎在同一点连点，或在两个挨得极近的点上结束，单圈长度可能只有几厘米，凑到 1–5 km 就需要几十万圈，轨迹点数会瞬间涨到百万级并撑爆内存。鸿蒙端在加密与扩增两个环节都设了上限（`apps/harmonyos/entry/src/main/ets/service/DataGenerator.ets` 的 `MAX_EXPANSION_POINTS`，10 万点），超过时不会闪退，而是在日志区提示：

- 日志区显示「预览失败: 路线过短（单圈仅 x.xx m）…请重新设计路线或选择其他路线」；
- 重新设计一条单圈长度接近目标距离的路线，或直接使用内置「思源湖路线」（单圈约 871 m）即可。

> 该缺陷在安卓端同样存在（同样的算法、同样的复制路径），鸿蒙端为保护运行时内存刻意提前拦截。

此外，进入轨迹生成前还会对**目标距离的量纲**做一次自检：`previewRoute()` 与 `DataGenerator.generate()` 都会拒绝小于 100 m 或大于 50 km（以及非有限数）的目标距离，并在日志区给出原因，例如：

```text
内部错误: 目标距离参数异常（原始值 1791910592.872），应为 1-5km；请重新设置目标距离后重试
```

> 预览曾一度稳定失败并报出「目标距离约为 1791910592.87km」这样的值：真因是
> `apps/harmonyos/entry/src/main/ets/viewmodel/MainViewModel.ets` 的预览调用把 `Date.now()` 与
> 目标距离两个实参写反（毫秒时间戳被当成米数），已按安卓端 `MainViewModel.kt:362-366` 的顺序修正为
> `(targetDistanceM, startTimeMs)`。
>
> 上面这道自检与第 9 节的 `MAX_EXPANSION_POINTS` 上限都是**兜底**：正常配置下永远不会触发，
> 只在未来又出现量纲或顺序错误时把「闪退」降级为「日志报错」。

