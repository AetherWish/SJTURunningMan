import { promptAction } from '@kit.ArkUI';
import { MainViewModel } from '../viewmodel/MainViewModel';
import {
  DropdownSelection,
  toSelectOptions,
  hdsPrefixIcon,
  hdsLabelItem,
  HdsCardOptions,
  HDS_FULL_TITLE_BAR_HEIGHT
} from './CommonComponents';
import { digitsOnly, yesterday, formatDate, parseDate } from '../utils/FormatUtil';
import { uiMaterial } from '@kit.ArkUI';
import { ImmersiveMaterialHelper } from '../common/ImmersiveMaterialHelper';
import { HdsListItemCard, SuffixCustomBuilder, SuffixText } from '@kit.UIDesignKit';

/**
 * 主运行界面（第一个页签 "开润"）
 * 迁移自 Android: com.sjtu.runner.ui.MainScreen @Composable
 *
 * 布局与交互保持一致：
 * 任务参数卡片（跑步天数/开始时间/起始日期/跑步路线/目标距离）
 * -> 重新登录提示 -> 开始/停止按钮 -> 运行日志面板
 */
@Component
export struct RunScreen {
  viewModel: MainViewModel = MainViewModel.getInstance();
  /** 主导航栈（由 Index 传入），用于跳转登录页/路线设计页 */
  navStack: NavPathStack = new NavPathStack();
  /** 沉浸光感材质：日志面板（小面积局部容器）；运行时不支持时为 undefined，组件自动降级为普通样式 */
  private logPanelMaterial: uiMaterial.Material | undefined = ImmersiveMaterialHelper.regular();
  private scroller: Scroller = new Scroller();

  // 天数状态
  @State days: number = 1;
  @State showCustomDays: boolean = false;
  @State customDaysText: string = '';
  // 时间状态
  @State timeHour: number = 8;
  @State timeMinute: number = 0;
  @State showCustomTime: boolean = false;
  // 日期状态
  @State dateText: string = formatDate(yesterday());
  // 距离锁定为 1-5km
  @State distanceKm: number = 5;

  aboutToAppear(): void {
    this.viewModel.refreshLoginState();
    this.viewModel.onLogAppended = () => {
      this.scroller.scrollEdge(Edge.Bottom);
    };
  }

  private daysSelectedIdx(): number {
    const opts: number[] = [1, 3, 5, 7, 10, 15, 30];
    const i = opts.indexOf(this.days);
    return i >= 0 ? i : 0;
  }

  private timeSelectedIdx(): number {
    if (this.timeMinute !== 0) {
      return 17; // 自定义
    }
    const idx = this.timeHour - 6;
    if (idx >= 0 && idx <= 16) {
      return idx;
    }
    return 17;
  }

  @Builder
  DaysSelector() {
    if (!this.showCustomDays) {
      DropdownSelection({
        options: ['1 天', '3 天', '5 天', '7 天', '10 天', '15 天', '30 天', '自定义'],
        selected: `${this.days} 天`,
        selectedIdx: this.daysSelectedIdx(),
        onSelect: (value: string) => {
          if (value === '自定义') {
            this.showCustomDays = true;
          } else {
            this.days = parseInt(value.replace(' 天', ''));
          }
        }
      })
    } else {
      Row({ space: 6 }) {
        TextInput({ text: this.customDaysText, placeholder: '天数' })
          .type(InputType.Number)
          .width(110)
          .height(38)
          .borderRadius(8)
          .onChange((value: string) => {
            this.customDaysText = digitsOnly(value);
          })
        Button() {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(16)
            .fontColor([$r('app.color.brand_primary')])
        }
        .width(38)
        .height(38)
        .borderRadius(8)
        .backgroundColor($r('app.color.brand_primary'))
        .onClick(() => {
          const n = parseInt(this.customDaysText);
          this.days = isNaN(n) || n <= 0 ? 1 : n;
          this.showCustomDays = false;
        })
      }
    }
  }

  @Builder
  TimeSelector() {
    if (!this.showCustomTime) {
      DropdownSelection({
        options: ['06:00', '07:00', '08:00', '09:00', '10:00', '11:00', '12:00', '13:00', '14:00',
          '15:00', '16:00', '17:00', '18:00', '19:00', '20:00', '21:00', '22:00', '自定义'],
        selected: `${this.timeHour < 10 ? '0' + this.timeHour : this.timeHour}:${this.timeMinute < 10 ? '0' + this.timeMinute : this.timeMinute}`,
        selectedIdx: this.timeSelectedIdx(),
        onSelect: (value: string) => {
          if (value === '自定义') {
            this.showCustomTime = true;
          } else {
            const parts = value.split(':');
            this.timeHour = parseInt(parts[0]);
            this.timeMinute = parseInt(parts[1]);
          }
        }
      })
    } else {
      Row({ space: 4 }) {
        TextInput({ text: `${this.timeHour < 10 ? '0' + this.timeHour : this.timeHour}` })
          .type(InputType.Number)
          .width(60)
          .height(38)
          .borderRadius(8)
          .onChange((value: string) => {
            const n = parseInt(value);
            this.timeHour = isNaN(n) ? this.timeHour : Math.max(0, Math.min(23, n));
          })
        Text(' : ')
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        TextInput({ text: `${this.timeMinute < 10 ? '0' + this.timeMinute : this.timeMinute}` })
          .type(InputType.Number)
          .width(60)
          .height(38)
          .borderRadius(8)
          .onChange((value: string) => {
            const n = parseInt(value);
            this.timeMinute = isNaN(n) ? this.timeMinute : Math.max(0, Math.min(59, n));
          })
        Button() {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(16)
            .fontColor([$r('app.color.brand_primary')])
        }
        .width(38)
        .height(38)
        .borderRadius(8)
        .backgroundColor($r('app.color.brand_primary'))
        .onClick(() => {
          this.showCustomTime = false;
        })
      }
      .alignItems(VerticalAlign.Center)
    }
  }

  /** 目标距离滑杆（HdsListItemCard 后缀自定义控件） */
  @Builder
  DistanceSlider() {
    Row({ space: 8 }) {
      Slider({ value: this.distanceKm, min: 1, max: 5, step: 1, style: SliderStyle.OutSet })
        .selectedColor($r('app.color.brand_primary'))
        .width(150)
        .onChange((value: number) => {
          this.distanceKm = Math.round(value);
        })
      Text(`${this.distanceKm} km`)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.brand_primary'))
        .width(46)
        .textAlign(TextAlign.End)
    }
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  RouteSelector() {
    Row({ space: 6 }) {
      Select(toSelectOptions(this.buildRouteOptionLabels()))
        .selected(this.currentRouteIndex())
        .value(this.viewModel.selectedRoute !== undefined ? this.viewModel.selectedRoute.name : '请选择路线')
        .fontColor($r('app.color.text_primary'))
        .font({ size: 14 })
        .optionFont({ size: 14 })
        .selectedOptionFont({ size: 14 })
        .width(170)
        .onSelect((index: number, text?: string) => {
          // 下拉仅保留已保存路线的选择；删除/排序/设默认已统一迁至“路线管理”
          const routes = this.viewModel.routes;
          if (index < routes.length) {
            this.viewModel.selectRoute(routes[index]);
          }
        })
    }
    .alignItems(VerticalAlign.Center)
  }

  private buildRouteOptionLabels(): string[] {
    const labels: string[] = [];
    const routes = this.viewModel.routes;
    for (let i = 0; i < routes.length; i++) {
      labels.push(`${routes[i].name}（${routes[i].pointCount} 个点${routes[i].isDefault ? ' · 启动默认' : ''}）`);
    }
    // "设定新路线"入口已迁移至一级页"路线"页签（RouteScreen），下拉仅保留路线选择
    return labels;
  }

  private currentRouteIndex(): number {
    if (this.viewModel.selectedRoute === undefined) {
      return 0;
    }
    const routes = this.viewModel.routes;
    for (let i = 0; i < routes.length; i++) {
      if (routes[i].id === this.viewModel.selectedRoute.id) {
        return i;
      }
    }
    return 0;
  }

  // ===== HDS 列表卡片选项（本地结构兼容接口 HdsCardOptions，
  // 规避 kit 的 HdsListItemCardOptions 因引用未导出类型而无法通过字面量检查） =====

  /** 1. 跑步天数卡片选项 */
  private daysCardOptions(): HdsCardOptions {
    const options: HdsCardOptions = {
      prefixItem: hdsPrefixIcon($r('sys.symbol.calendar')),
      textItem: hdsLabelItem('跑步天数'),
      suffixItem: new SuffixCustomBuilder((): void => {
        this.DaysSelector()
      })
    };
    return options;
  }

  /** 2. 开始时间卡片选项 */
  private timeCardOptions(): HdsCardOptions {
    const options: HdsCardOptions = {
      prefixItem: hdsPrefixIcon($r('sys.symbol.clock')),
      textItem: hdsLabelItem('开始时间'),
      suffixItem: new SuffixCustomBuilder((): void => {
        this.TimeSelector()
      })
    };
    return options;
  }

  /** 3. 起始日期卡片选项（整行点击弹出日历选择） */
  private dateCardOptions(): HdsCardOptions {
    const options: HdsCardOptions = {
      prefixItem: hdsPrefixIcon($r('sys.symbol.calendar')),
      textItem: hdsLabelItem('起始日期'),
      suffixItem: new SuffixText({ text: this.dateText }),
      onClick: (): void => {
        if (!this.viewModel.running) {
          const selectedDate = parseDate(this.dateText);
          DatePickerDialog.show({
            start: new Date(2000, 0, 1),
            end: new Date(2100, 0, 1),
            selected: (selectedDate !== null ? selectedDate : yesterday()),
            onDateAccept: (value: Date) => {
              this.dateText = formatDate(value);
            }
          });
        }
      }
    };
    return options;
  }

  /** 4. 跑步路线卡片选项 */
  private routeCardOptions(): HdsCardOptions {
    const options: HdsCardOptions = {
      prefixItem: hdsPrefixIcon($r('sys.symbol.map')),
      textItem: hdsLabelItem('跑步路线'),
      suffixItem: new SuffixCustomBuilder((): void => {
        this.RouteSelector()
      })
    };
    return options;
  }

  /** 5. 目标距离卡片选项（滑杆 + 数值） */
  private distanceCardOptions(): HdsCardOptions {
    const options: HdsCardOptions = {
      prefixItem: hdsPrefixIcon($r('sys.symbol.figure_run')),
      textItem: hdsLabelItem('目标距离'),
      suffixItem: new SuffixCustomBuilder((): void => {
        this.DistanceSlider()
      })
    };
    return options;
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: 16 }) {
          // ===== 参数配置区（HDS 原生列表卡片，系统应用风格） =====
          Text('任务参数')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 4 })

          // 官方《设置列表卡片样式》：HdsListItemCard 置于 List>ListItem 中，
          // 由 List（width '100%'）经 ListItem 提供满宽，与下方"开始/停止任务"
          // 按钮组（Row.width('100%')）等宽；卡片仍显式 .width('100%') 兜底。
          List({ space: 8 }) {
            ListItem() {
              // 1. 跑步天数（下拉选择 + 自定义）
              HdsListItemCard(this.daysCardOptions())
                .width('100%')
            }

            ListItem() {
              // 2. 开始时间（下拉选择 + 自定义）
              HdsListItemCard(this.timeCardOptions())
                .width('100%')
            }

            ListItem() {
              // 3. 起始日期（整行点击弹出日历选择）
              HdsListItemCard(this.dateCardOptions())
                .width('100%')
            }

            ListItem() {
              // 4. 跑步路线（下拉选择 + 新增/删除）
              HdsListItemCard(this.routeCardOptions())
                .width('100%')
            }

            ListItem() {
              // 5. 目标距离：锁定 1-5km（滑杆 + 数值）
              HdsListItemCard(this.distanceCardOptions())
                .width('100%')
            }
          }
          .width('100%')

          // ===== 重新登录提示 =====
          if (this.viewModel.reloginRequired) {
            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill'))
                .fontSize(20)
                .fontColor([$r('app.color.on_error_container')])
              Column({ space: 2 }) {
                Text('检测到cookie过期')
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.on_error_container'))
                Text('请重新登录以继续上传')
                  .fontSize(12)
                  .fontColor($r('app.color.on_error_container'))
              }
              .alignItems(HorizontalAlign.Start)

              Blank()
              Button('重新登录')
                .fontSize(14)
                .height(36)
                .borderRadius(8)
                .backgroundColor($r('app.color.error_color'))
                .onClick(() => {
                  this.viewModel.reloginRequired = false;
                  this.navStack.pushPathByName('Login', null);
                })
            }
            .width('100%')
            .padding(16)
            .borderRadius(12)
            .backgroundColor($r('app.color.error_container'))
            .alignItems(VerticalAlign.Center)
          }

          // ===== 控制按钮组 =====
          Row({ space: 12 }) {
            Button() {
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.play_fill'))
                  .fontSize(15)
                  .fontColor(['#FFFFFF'])
                Text('开始任务').fontSize(16)
              }
            }
              .layoutWeight(1)
              .height(56)
              .borderRadius(28)
              .backgroundColor(this.viewModel.running || !this.viewModel.loginState
              ? '#1F6650A4' : $r('app.color.brand_primary'))
              .onClick(() => {
                if (!this.viewModel.loginState) {
                  promptAction.showToast({ message: '请先登录！', duration: 1500 });
                } else if (!this.viewModel.running) {
                  this.viewModel.startUpload(this.days, this.distanceKm, this.timeHour, this.timeMinute, this.dateText);
                }
              })

            Button() {
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.square_fill'))
                  .fontSize(13)
                  .fontColor(['#FFFFFF'])
                Text('停止任务').fontSize(16)
              }
            }
              .layoutWeight(1)
              .height(56)
              .borderRadius(28)
              .backgroundColor(this.viewModel.running
                ? $r('app.color.error_color') : '#4DB3261E')
              .enabled(this.viewModel.running)
              .onClick(() => {
                this.viewModel.stopUpload();
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          // ===== 日志面板 =====
          Column({ space: 8 }) {
            Text('运行日志')
              .fontSize(13)
              .fontColor($r('app.color.outline'))
              .margin({ left: 4 })

            Column() {
              Scroll(this.scroller) {
                Text(this.viewModel.log.length > 0 ? this.viewModel.log : '就绪。点击“开始任务”启动。')
                  .fontFamily('monospace')
                  .fontSize(12)
                  .lineHeight(18)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
              }
              .scrollable(ScrollDirection.Vertical)
              .scrollBar(BarState.Auto)
              .width('100%')
              .height('100%')
            }
            .width('100%')
            .height(300)
            .padding(12)
            .borderRadius(12)
            .border({ width: 0.5, color: $r('app.color.outline_variant') })
            // 沉浸光感：为日志面板这个小面积局部容器开启沉浸式系统材质
            // （材质接管背景/边框/阴影，避免在同一节点叠加不透明背景色）
            .systemMaterial(this.logPanelMaterial)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        // 四边统一内边距：top 额外叠加 HdsNavigation FULL 大标题栏高度（112vp）——
        // titleBar 为悬浮层覆盖在内容上方，官方示例要求内容首部预留等高空间避让；
        // bottom 为悬浮页签预留空间。
        // 注意 ArkUI 同属性链式调用后者覆盖前者，不可拆成两次 .padding()
        .padding({
          left: 16,
          right: 16,
          top: HDS_FULL_TITLE_BAR_HEIGHT + 16,
          bottom: 96
        })
      }
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Off)
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
