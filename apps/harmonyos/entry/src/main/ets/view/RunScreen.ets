import { promptAction } from '@kit.ArkUI';
import { uiMaterial } from '@kit.ArkUI';
import { HdsListItemCard, SuffixText } from '@kit.UIDesignKit';
import { MainViewModel, RunConfig } from '../viewmodel/MainViewModel';
import { RouteConflict, RouteDecision, RoutePreview, TrackSample } from '../viewmodel/TaskModels';
import { RouteInfo } from '../model/RouteInfo';
import {
  hdsPrefixIcon,
  hdsLabelItem,
  HdsCardOptions,
  SettingCard,
  HDS_MINI_TITLE_BAR_HEIGHT
} from './CommonComponents';
import { ChoiceChips, DistanceSlider, MenuDropdown, MenuOption, NumberField, SectionDivider, TimeField } from './Controls';
import { StatusCard, StatItem } from './StatusCard';
import { ConsoleLog } from './ConsoleLog';
import { RoutePreviewCanvas } from './RoutePreviewCanvas';
import { parseDate, yesterday, formatDate } from '../utils/FormatUtil';
import { ImmersiveMaterialHelper } from '../common/ImmersiveMaterialHelper';
import { AppConfig } from '../config/AppConfig';

/**
 * 主运行界面（第一个页签“开润”）
 * 迁移自 Android: com.sjtu.runner.ui.MainScreen @Composable
 *
 * 布局与交互与安卓版保持一致（自上而下）：
 * 状态卡 -> 重新登录提示 -> 跑步路线（预设路线/预览画布/预览/删除）
 * -> 任务设置（跑步次数/开始时间/结束日期/目标距离）
 * -> 运行日志（等级着色 + 清空） -> 免责提示 -> 底部操作栏（预览/开始/停止）
 *
 * ArkUI 差异说明：
 * - 安卓 TopAppBar 的两个 action（关于/重新登录）改为页签容器的标题栏与“关于”二级页承载；
 * - 安卓的底部 bottomBar 在本页以底部固定操作栏实现；
 * - 承诺书弹窗由 Index 页面承载（应用级门禁），本页只管任务。
 */
@Component
export struct RunScreen {
  viewModel: MainViewModel = MainViewModel.getInstance();
  /** 主导航栈（由 Index 传入），用于跳转登录页/路线设计页 */
  navStack: NavPathStack = new NavPathStack();
  /** 沉浸光感材质：日志面板（小面积局部容器）；运行时不支持时为 undefined，组件自动降级为普通样式 */
  private logPanelMaterial: uiMaterial.Material | undefined = ImmersiveMaterialHelper.regular();

  // ===== 任务设置状态（等价 Android MainScreen 的 remember 变量） =====
  @State days: number = 1;
  @State distanceKm: number = AppConfig.DEFAULT_DISTANCE_KM;
  @State timeHour: number = AppConfig.DEFAULT_RUN_HOUR;
  @State timeMinute: number = AppConfig.DEFAULT_RUN_MINUTE;
  @State timeSecond: number = AppConfig.DEFAULT_RUN_SECOND;
  @State dateText: string = formatDate(yesterday());
  @State customDaysText: string = '';
  @State showCustomDays: boolean = false;
  /** 防止同一次路线冲突重复弹窗（等价 Android 的 routeConflict 一次性消费） */
  @State conflictShown: boolean = false;
  /** 路线距离提醒弹窗可见性（ArkUI AlertDialog 只有两个按钮，无法承载 Android 的三个选项） */
  @State conflictDialogVisible: boolean = false;
  /**
   * 使用承诺书门禁由 Index 页面以全屏遮罩实现（等价 Android CommitmentDialog）。
   * Android 把门禁渲染在 Scaffold 之外，因此必须由根页面承载；放在本组件内会只遮住 Tab 内容区，
   * 顶部标题栏与悬浮页签仍可点击，门禁形同虚设。
   */

  aboutToAppear(): void {
    this.viewModel.refreshLoginState();
    this.viewModel.updateConfig(this.buildConfig());
    // 路线冲突由 ViewModel 挂起任务时回调（等价 Compose 对 routeConflict 状态的响应）
    this.viewModel.onRouteConflict = (): void => {
      this.showConflictIfNeeded();
    };
    this.showConflictIfNeeded();
  }

  private showConflictIfNeeded(): void {
    const conflict = this.viewModel.routeConflict;
    if (conflict === undefined) {
      this.conflictShown = false;
      return;
    }
    if (this.conflictShown) {
      return;
    }
    this.conflictShown = true;
    this.conflictDialogVisible = true;
  }

  /** 关闭路线距离提醒并把用户选择交给 ViewModel */
  private resolveConflict(decision: RouteDecision): void {
    this.conflictDialogVisible = false;
    this.viewModel.resolveRouteConflict(decision);
  }

  // ==================== 配置 ====================

  /** 由界面状态构造任务配置（等价 Android MainScreen 的 config remember） */
  private buildConfig(): RunConfig {
    const parsed = parseDate(this.dateText);
    const startDate = parsed !== null ? parsed : yesterday();
    return new RunConfig(this.days, this.distanceKm, this.timeHour, this.timeMinute, this.timeSecond, startDate,
      undefined);
  }

  // ==================== 卡片选项 ====================

  /**
   * 结束日期（静态信息行，继续使用 HDS 原生 HdsListItemCard）。
   * 带交互控件的三行（跑步次数/开始时间/目标距离）改用自绘 SettingCard：
   * HdsListItemCard 的自定义后缀不参与尺寸测量，控件会溢出卡片。
   */
  private dateCardOptions(): HdsCardOptions {
    const options: HdsCardOptions = {
      prefixItem: hdsPrefixIcon($r('sys.symbol.calendar')),
      textItem: hdsLabelItem('结束日期'),
      suffixItem: new SuffixText({ text: this.dateText }),
      onClick: (): void => {
        if (!this.viewModel.running) {
          this.pickDate();
        }
      }
    };
    return options;
  }

  /**
   * 目标距离滑杆（SettingCard 控件列内容）。
   *
   * 必须在 @Builder 方法里调用自定义组件：直接把 `DistanceSlider({...})` 写在
   * 传给组件的箭头函数里，ArkTS 编译器不会把该调用重写成
   * `new DistanceSlider(this, {...})`，运行时会抛出
   * `TypeError: class constructor cannot called without 'new'`（真机 nova 12 Ultra 崩溃）。
   */
  @Builder
  DistanceSliderBuilder() {
    DistanceSlider({
      distanceKm: this.distanceKm,
      minDistanceKm: AppConfig.MIN_DISTANCE_KM,
      maxDistanceKm: AppConfig.MAX_DISTANCE_KM,
      isEnabled: !this.viewModel.running,
      onDistanceChange: (value: number): void => {
        this.distanceKm = value;
        this.viewModel.updateConfig(this.buildConfig());
      }
    })
  }

  private pickDate(): void {
    const selected = parseDate(this.dateText);
    DatePickerDialog.show({
      start: new Date(2000, 0, 1),
      end: new Date(2100, 0, 1),
      selected: selected !== null ? selected : yesterday(),
      onDateAccept: (value: Date): void => {
        this.dateText = formatDate(value);
        this.viewModel.updateConfig(this.buildConfig());
      }
    });
  }

  // ==================== 运行日志 ====================

  private stats(): StatItem[] {
    const result: StatItem[] = [];
    result.push(new StatItem('次数', `${this.days}`));
    result.push(new StatItem('距离', `${this.distanceKm.toFixed(1)} km`));
    result.push(new StatItem('时间',
      `${pad(this.timeHour)}:${pad(this.timeMinute)}:${pad(this.timeSecond)}`));
    return result;
  }

  // ==================== 预览 / 删除 ====================

  private routePreview(): RoutePreview | undefined {
    return this.viewModel.preview;
  }

  private previewSamples(): TrackSample[] {
    const preview = this.viewModel.preview;
    return preview !== undefined ? preview.samples : [];
  }

  private previewJumpCount(): number {
    const preview = this.viewModel.preview;
    return preview !== undefined ? preview.jumpCount : 0;
  }

  private deleteCurrentRoute(): void {
    const route = this.viewModel.selectedRoute;
    if (route === undefined || route.isDefault || this.viewModel.running) {
      return;
    }
    const target: RouteInfo = route;
    AlertDialog.show({
      title: '删除路线',
      message: `确定要删除路线「${target.name}」吗？该操作不可撤销。`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.error_color'),
        action: () => {
          this.viewModel.deleteRoute(target);
        }
      }
    });
  }

  // ==================== 路线距离提醒 ====================

  /** 路线长度超过目标距离时弹出三选一（等价 Android RouteConflictDialog） */
  @Builder
  RouteConflictDialog() {
    Column() {
      Column({ space: 12 }) {
        Text('路线距离提醒')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')

        Text(`当前路线「${this.viewModel.routeConflict?.routeName ?? ''}」长度为 `
          + `${((this.viewModel.routeConflict?.routeDistanceM ?? 0) / 1000.0).toFixed(2)}km，`
          + `超过了您选择的 ${((this.viewModel.routeConflict?.targetDistanceM ?? 0) / 1000.0).toFixed(2)}km。`)
          .fontSize(14)
          .lineHeight(22)
          .fontColor($r('app.color.text_primary'))
          .width('100%')

        Text('削减：自动截断路线至目标距离')
          .fontSize(13)
          .lineHeight(20)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')

        Text('完整路线：按整条路线跑步并同步目标距离')
          .fontSize(13)
          .lineHeight(20)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')

        Row({ space: 10 }) {
          Button('削减路线')
            .fontSize(14)
            .height(44)
            .layoutWeight(1)
            .borderRadius(22)
            .backgroundColor($r('app.color.brand_primary'))
            .fontColor($r('app.color.text_on_brand'))
            .onClick(() => {
              this.resolveConflict(RouteDecision.TRUNCATE);
            })
          Button('取消任务')
            .fontSize(14)
            .height(44)
            .layoutWeight(1)
            .borderRadius(22)
            .backgroundColor(Color.Transparent)
            .fontColor($r('app.color.text_secondary'))
            .onClick(() => {
              this.resolveConflict(RouteDecision.CANCEL);
            })
          Button('完整路线')
            .fontSize(14)
            .height(44)
            .layoutWeight(1)
            .borderRadius(22)
            .backgroundColor(Color.Transparent)
            .fontColor($r('app.color.brand_primary'))
            .border({ width: 1, color: $r('app.color.brand_primary') })
            .onClick(() => {
              this.resolveConflict(RouteDecision.FULL_ROUTE);
            })
        }
        .width('100%')
      }
      .width('90%')
      .padding(20)
      .borderRadius(24)
      .backgroundColor($r('app.color.card_surface'))
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#99000000')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // ==================== 子构件 ====================

  @Builder
  DaysSelector() {
    if (!this.showCustomDays) {
      ChoiceChips({
        options: ['1', '3', '5', '7', '10', '15', '30', '自定义'],
        selected: `${this.days}`,
        isEnabled: !this.viewModel.running,
        onSelect: (value: string): void => {
          if (value === '自定义') {
            this.showCustomDays = true;
            this.customDaysText = `${this.days}`;
          } else {
            this.days = parseInt(value);
            this.viewModel.updateConfig(this.buildConfig());
          }
        }
      })
    } else {
      Row({ space: 8 }) {
        NumberField({
          value: this.days,
          label: '次数 1-30',
          maxLength: 2,
          fieldWidth: 96,
          isEnabled: !this.viewModel.running,
          onValueChange: (value: number): void => {
            this.customDaysText = `${value}`;
          }
        })
        Button('确定')
          .fontSize(13)
          .height(34)
          .borderRadius(17)
          .backgroundColor($r('app.color.brand_primary'))
          .enabled(!this.viewModel.running)
          .onClick(() => {
            const n = parseInt(this.customDaysText);
            this.days = isNaN(n) ? 1 : Math.max(1, Math.min(AppConfig.MAX_RUN_TIMES, n));
            this.showCustomDays = false;
            this.viewModel.updateConfig(this.buildConfig());
          })
      }
      .alignItems(VerticalAlign.Bottom)
    }
  }

  @Builder
  TimeSelector() {
    Column({ space: 6 }) {
      TimeField({
        hour: this.timeHour,
        minute: this.timeMinute,
        second: this.timeSecond,
        isEnabled: !this.viewModel.running,
        onChange: (hour: number, minute: number, second: number): void => {
          this.timeHour = hour;
          this.timeMinute = minute;
          this.timeSecond = second;
          this.viewModel.updateConfig(this.buildConfig());
        }
      })
      Text('每次跑步自动加入 ±10 分钟 / ±30 秒随机波动')
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
    }
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  RouteSelector() {
    MenuDropdown({
      label: '预设路线',
      value: this.viewModel.selectedRoute !== undefined ? this.viewModel.selectedRoute.name : '请选择路线',
      options: this.routeMenuOptions(),
      isEnabled: !this.viewModel.running,
      onSelect: (key: string): void => {
        if (key === '__new__') {
          this.navStack.pushPathByName('RouteDesign', null);
          return;
        }
        const routes = this.viewModel.routes;
        for (let i = 0; i < routes.length; i++) {
          if (routes[i].id === key) {
            this.viewModel.selectRoute(routes[i]);
            return;
          }
        }
      }
    })
  }

  private routeMenuOptions(): MenuOption[] {
    const options: MenuOption[] = [];
    const routes = this.viewModel.routes;
    const selectedId = this.viewModel.selectedRoute !== undefined ? this.viewModel.selectedRoute.id : '';
    for (let i = 0; i < routes.length; i++) {
      const route = routes[i];
      const subtitle = `${route.pointCount} 个点${route.isDefault ? ' · 内置' : ''}`;
      options.push(new MenuOption(route.id, route.name, subtitle, route.id === selectedId));
    }
    options.push(new MenuOption('__new__', '设计新路线', '在地图上点击采集坐标点', false));
    return options;
  }

  @Builder
  ReloginBanner() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill'))
          .fontSize(18)
          .fontColor([$r('app.color.error_color')])
        Text('Cookie 已过期')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
      }
      .alignItems(VerticalAlign.Center)

      Text('登录状态失效，请重新登录后继续上传。')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      Button('登录')
        .fontSize(14)
        .height(36)
        .borderRadius(18)
        .backgroundColor($r('app.color.brand_primary_container'))
        .fontColor($r('app.color.brand_on_primary_container'))
        .alignSelf(ItemAlign.Start)
        .onClick(() => {
          this.viewModel.reloginRequired = false;
          this.navStack.pushPathByName('Login', null);
        })
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.error_container'))
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  RouteSection() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Text('跑步路线')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(18)
          .fontColor([$r('app.color.brand_primary')])
          .onClick(() => {
            this.navStack.pushPathByName('RouteDesign', null);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      this.RouteSelector()

      // 路线预览画布（原始路线 / 离线预览 / 待上传 / 已上传）
      RoutePreviewCanvas({
        samples: this.previewSamples(),
        jumpCount: this.previewJumpCount(),
        canvasHeight: 150
      })

      Row({ space: 8 }) {
        Text(this.routePreview() !== undefined ? (this.routePreview() as RoutePreview).title : '路线预览')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.previewJumpCount() > 0) {
          Text(`${this.previewJumpCount()} 处跳段`)
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.error_color'))
            .backgroundColor($r('app.color.error_container'))
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(8)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.routePreview() !== undefined ? (this.routePreview() as RoutePreview).summary
        : '点击「预览路线」按当前设置离线生成')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      SectionDivider()

      Row({ space: 10 }) {
        Button('预览路线')
          .fontSize(14)
          .height(40)
          .layoutWeight(1)
          .borderRadius(12)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.brand_primary'))
          .border({ width: 1, color: $r('app.color.brand_primary') })
          .enabled(!this.viewModel.running && this.viewModel.selectedRoute !== undefined)
          .onClick(() => {
            this.viewModel.previewRoute();
          })
        Button('删除路线')
          .fontSize(14)
          .height(40)
          .layoutWeight(1)
          .borderRadius(12)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.error_color'))
          .border({ width: 1, color: $r('app.color.error_color') })
          .enabled(!this.viewModel.running && this.viewModel.selectedRoute !== undefined
            && !(this.viewModel.selectedRoute as RouteInfo).isDefault)
          .onClick(() => {
            this.deleteCurrentRoute();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .borderRadius(20)
    .backgroundColor($r('app.color.card_surface'))
    .border({ width: 1, color: $r('app.color.outline_variant') })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  LogSection() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Text('运行日志')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(this.viewModel.running ? '任务运行中' : `共 ${this.viewModel.logs.length} 条记录`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
        if (!this.viewModel.running && this.viewModel.logs.length > 0) {
          Button('清空')
            .fontSize(13)
            .height(32)
            .borderRadius(16)
            .backgroundColor(Color.Transparent)
            .fontColor($r('app.color.brand_primary'))
            .onClick(() => {
              this.viewModel.clearLogs();
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Column() {
        ConsoleLog({
          entries: this.viewModel.logs,
          panelHeight: 210,
          placeholder: '就绪。点击「开始任务」启动。'
        })
      }
      .width('100%')
      .borderRadius(14)
      // 沉浸光感：为日志面板这个小面积局部容器开启沉浸式系统材质
      .systemMaterial(this.logPanelMaterial)
    }
    .width('100%')
    .padding(16)
    .borderRadius(20)
    .backgroundColor($r('app.color.card_surface'))
    .border({ width: 1, color: $r('app.color.outline_variant') })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  DisclaimerNotice() {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill'))
        .fontSize(18)
        .fontColor([$r('app.color.warning_color')])
      Text('本项目仅供学习、研究和技术测试，请勿用于伪造运动数据或规避体育锻炼要求。')
        .fontSize(12)
        .lineHeight(18)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .borderRadius(14)
    .backgroundColor($r('app.color.warning_container'))
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  BottomActionBar() {
    Row({ space: 10 }) {
      Button('预览')
        .fontSize(15)
        .height(52)
        .layoutWeight(9)
        .borderRadius(16)
        .backgroundColor($r('app.color.brand_primary_container'))
        .fontColor($r('app.color.brand_on_primary_container'))
        .enabled(!this.viewModel.running && this.viewModel.selectedRoute !== undefined)
        .onClick(() => {
          this.viewModel.previewRoute();
        })

      if (this.viewModel.running) {
        Button('停止任务')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .height(52)
          .layoutWeight(11)
          .borderRadius(16)
          .backgroundColor($r('app.color.error_color'))
          .fontColor($r('app.color.on_error_container'))
          .onClick(() => {
            this.viewModel.stopUpload();
          })
      } else {
        Button('开始任务')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .height(52)
          .layoutWeight(11)
          .borderRadius(16)
          .backgroundColor($r('app.color.brand_primary'))
          .fontColor($r('app.color.text_on_brand'))
          .enabled(this.viewModel.selectedRoute !== undefined)
          .onClick(() => {
            this.startTask();
          })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor($r('app.color.page_background'))
  }

  private startTask(): void {
    const config = this.buildConfig();
    this.viewModel.updateConfig(config);
    const error = this.viewModel.validate(config);
    if (error !== undefined) {
      promptAction.showToast({ message: error, duration: 2000 });
      return;
    }
    if (!this.viewModel.loginState) {
      promptAction.showToast({ message: '请先登录！', duration: 1500 });
      return;
    }
    this.viewModel.startUpload(config);
  }

  /**
   * 使用承诺书门禁由 Index 页面以全屏遮罩实现（等价 Android CommitmentDialog）。
   * Android 把门禁渲染在 Scaffold 之外，因此必须由根页面承载；放在本组件内会只遮住 Tab 内容区，
   * 顶部标题栏与悬浮页签仍可点击，门禁形同虚设。
   */

  build() {
    // 外层 Stack 只用于承载路线距离提醒的全屏遮罩（被打开时同时盖住底部操作栏）。
    Stack() {
      // 根容器用 Column 而非 Stack：底部操作栏必须是滚动区的“兄弟节点”并占据自身高度，
      // 这样 Scroll 只能分到剩余空间（layoutWeight(1)）。之前用 Stack 悬浮覆盖时，
      // Stack 会把 Scroll 撑满，滚动内容长期被操作栏遮住，用户以为“按钮没置底”。
      Column() {
        Scroll() {
          Column({ space: 14 }) {
            // ===== 状态卡 =====
            StatusCard({
              progress: this.viewModel.progress,
              headline: `${this.days} 次 · ${this.distanceKm.toFixed(1)} km`,
              stats: this.stats()
            })

            // ===== 重新登录提示 =====
            if (this.viewModel.reloginRequired) {
              this.ReloginBanner()
            }

            // ===== 跑步路线 =====
            this.RouteSection()

            // ===== 任务设置 =====
            Column({ space: 8 }) {
              Text('任务设置')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .margin({ left: 4, bottom: 4 })
              // 带交互控件的三行用自绘 SettingCard：控件列由 ArkUI 正常测量，
              // 胶囊组按真实可用宽度换行，不会溢出卡片（详见 CommonComponents.ets）。
              // 需要宽控件的行用 fullWidth（标签移到上方），否则 Text 的 64vp 最小宽度
              // 会把控件列挤到约 280vp，8 个胶囊只能排 3 行。
              SettingCard({
                label: '跑步次数',
                symbol: $r('sys.symbol.calendar'),
                fullWidth: true
              }) {
                this.DaysSelector()
              }
              SettingCard({ label: '开始时间', symbol: $r('sys.symbol.clock') }) {
                this.TimeSelector()
              }
              HdsListItemCard(this.dateCardOptions())
              SettingCard({
                label: '目标距离',
                symbol: $r('sys.symbol.figure_run'),
                fullWidth: true
              }) {
                this.DistanceSliderBuilder()
              }
            }
            .width('100%')

            // ===== 运行日志 =====
            this.LogSection()

            // ===== 免责提示 =====
            this.DisclaimerNotice()
          }
          .width('100%')
          // 三边内边距：top 额外叠加 HdsNavigation MINI 标题栏高度（56vp）——
          // titleBar 为悬浮层覆盖在内容上方，官方示例要求内容首部预留等高空间避让。
          // bottom 只留常规间距：底部操作栏现在是兄弟节点、已占走自身高度，不再需要预留 120vp。
          .padding({
            left: 16,
            right: 16,
            top: HDS_MINI_TITLE_BAR_HEIGHT + 16,
            bottom: 16
          })
        }
        .scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Off)
        .width('100%')
        .layoutWeight(1)

        // ===== 底部操作栏 =====
        // 紧贴窗口底部，只保留 8vp 与系统手势条的间距（Navigation 已把内容限制在安全区内）。
        // 之前这里 padding bottom 64 是给 HdsTabs 悬浮页签预留的，页签已删除，于是底部空出 90vp。
        Column() {
          this.BottomActionBar()
        }
        .width('100%')
        .padding({ bottom: 8 })
      }
      .width('100%')
      .height('100%')

      // ===== 路线距离提醒（三选一，全屏遮罩，覆盖底部操作栏） =====
      if (this.conflictDialogVisible) {
        this.RouteConflictDialog()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}

/** 两位补零（本地实现，避免与 FormatUtil.pad2 的 import 冲突） */
function pad(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}
