/**
 * 任务设置控件
 * 迁移自 Android: com.sjtu.runner.ui.components.Controls
 *
 * ArkUI 差异说明：
 * 1. StatusPill 的 16% 底色用 ColorMetrics 把 Resource 解析成 rgba() 字符串
 *    （ArkUI 中给 Row 设 opacity 会把文字一起变淡，故不用半透明图层叠加）；
 * 2. 需要跟随父组件状态刷新的成员统一声明为 Prop 状态变量并给出本地默认值：
 *    ArkUI V1 生成的 updateStateVars 只包含 Prop / ObjectLink 装饰的成员，
 *    无装饰器的普通成员仅在构造时赋值一次，父组件重渲染不会同步。
 *    回调函数保持普通成员（闭包捕获父组件 this，无需同步）。
 */
import { ColorMetrics } from '@kit.ArkUI';
import { toSelectOptions } from './CommonComponents';

/** 数字输入框统一高度与圆角 */
const FIELD_HEIGHT: number = 36;
const FIELD_RADIUS: number = 10;
/** 数字输入框边框 */
const FIELD_BORDER: number = 1;

/**
 * 数字输入框（等价 Android NumberField）
 * 仅接受数字，空输入按 0 处理。
 */
@Component
export struct NumberField {
  /** 当前数值 */
  @Prop value: number = 0;
  /** 字段上方标签（空字符串表示不渲染标签） */
  @Prop label: string = '';
  /** 最大输入长度 */
  @Prop maxLength: number = 3;
  /** 字段宽度（vp）；0 表示占满父容器可用宽度 */
  @Prop fieldWidth: number = 64;
  @Prop isEnabled: boolean = true;
  /** 数值变化回调（已过滤非数字） */
  onValueChange: (v: number) => void = (v: number) => {
  };

  build() {
    Column() {
      if (this.label.length > 0) {
        Text(this.label)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .margin({ bottom: 4 })
      }
      TextInput({ text: this.value.toString() })
        .type(InputType.Number)
        .maxLength(this.maxLength)
        .width(this.fieldWidth > 0 ? this.fieldWidth : '100%')
        .height(FIELD_HEIGHT)
        .borderRadius(FIELD_RADIUS)
        .border({ width: FIELD_BORDER, color: $r('app.color.outline_variant') })
        .backgroundColor($r('app.color.card_surface'))
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Center)
        .enabled(this.isEnabled)
        .opacity(this.isEnabled ? 1 : 0.5)
        .onChange((input: string) => {
          const digits: string = input.replace(/[^0-9]/g, '');
          const parsed: number = digits.length === 0 ? 0 : Number.parseInt(digits, 10);
          this.onValueChange(parsed);
        })
    }
    .alignItems(HorizontalAlign.Start)
  }
}

/**
 * 目标距离滑块（等价 Android DistanceSlider）
 * 范围由父组件给出（AppConfig.MIN_DISTANCE_KM / MAX_DISTANCE_KM），步进 0.1km。
 */
@Component
export struct DistanceSlider {
  /**
   * 单向值绑定。父组件是唯一数据源：滑杆只负责上报新值（onDistanceChange），
   * 由父组件改自己的 @State 后再流回这里，避免父子各持一份值而显示不一致。
   */
  @Prop distanceKm: number = 1;
  @Prop minDistanceKm: number = 1;
  @Prop maxDistanceKm: number = 5;
  @Prop isEnabled: boolean = true;
  /**
   * 显示「数值 + 上限」信息行：
   * - true（默认）：数值行画在滑杆上方（独立使用时的布局）
   * - false：与 SettingCard 的标签行并排使用，数值行缩进 valueIndent 后与标签左对齐
   */
  @Prop showValueRow: boolean = true;
  /** 数值行左缩进（vp）：SettingCard 布局下传「图标列 + 标签列」宽度，使数值与标签左对齐 */
  @Prop valueIndent: number = 0;
  onDistanceChange: (v: number) => void = (v: number) => {
  };

  build() {
    Column() {
      if (!this.showValueRow) {
        // SettingCard 布局：读数由该卡片的 @StorageProp('distanceKmText') 渲染在标签行；这里只画滑杆，
        // 上限提示单独占一行右对齐。
        Row() {
          Blank()
          Text(`上限 ${Math.trunc(this.maxDistanceKm)}km`)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .margin({ bottom: 2 })
      } else {
        Row() {
          Text(this.distanceKm.toFixed(1))
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.brand_primary'))
          Text(' km')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
          Blank()
          Text(`上限 ${Math.trunc(this.maxDistanceKm)}km`)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .alignItems(VerticalAlign.Bottom)
      }

      Slider({
        value: this.distanceKm,
        min: this.minDistanceKm,
        max: this.maxDistanceKm,
        step: 0.1,
        style: SliderStyle.OutSet
      })
        .width('100%')
        .blockColor($r('app.color.brand_primary'))
        .selectedColor($r('app.color.brand_primary'))
        .trackColor($r('app.color.outline_variant'))
        .enabled(this.isEnabled)
        .opacity(this.isEnabled ? 1 : 0.5)
        .onChange((value: number, mode: SliderChangeMode) => {
          this.onDistanceChange(Math.round(value * 10) / 10);
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

/** 分组分隔线（等价 Android SectionDivider） */@Component
export struct SectionDivider {
  build() {
    Divider()
      .color($r('app.color.outline_variant'))
      .margin({ top: 12, bottom: 12 })
  }
}

/** 下拉菜单项（等价 Android DropdownSelection 的 SelectOption） */
export class MenuOption {
  key: string;
  title: string;
  subtitle: string;
  selected: boolean;

  constructor(key: string, title: string, subtitle: string, selected: boolean) {
    this.key = key;
    this.title = title;
    this.subtitle = subtitle;
    this.selected = selected;
  }
}

/**
 * 下拉选择（等价 Android DropdownSelection）
 * 标签在 Select 上方；选中项由 options 中 selected 为 true 的项决定，无选中时为 -1。
 */
@Component
export struct MenuDropdown {
  @Prop label: string = '';
  @Prop value: string = '';
  /** 注意：Prop 状态变量会对 class 数组做深拷贝，MenuOption[] 会触发一次拷贝（父组件每帧重建，可接受） */
  @Prop options: MenuOption[] = [];
  @Prop isEnabled: boolean = true;
  onSelect: (key: string) => void = (key: string) => {
  };

  /** 选中项下标（无选中项返回 -1） */
  private selectedIndex(): number {
    for (let i = 0; i < this.options.length; i++) {
      if (this.options[i].selected) {
        return i;
      }
    }
    return -1;
  }

  build() {
    Column() {
      if (this.label.length > 0) {
        Text(this.label)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ bottom: 4 })
      }
      Select(toSelectOptions(this.options.map((option: MenuOption) => option.title)))
        .selected(this.selectedIndex())
        .value(this.value)
        .fontColor($r('app.color.text_primary'))
        .font({ size: 14 })
        .optionFont({ size: 14 })
        .selectedOptionFont({ size: 14 })
        .enabled(this.isEnabled)
        .width('100%')
        .onSelect((index: number, text?: string) => {
          if (index >= 0 && index < this.options.length) {
            this.onSelect(this.options[index].key);
          }
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

/**
 * 状态胶囊（等价 Android StatusPill）
 * 底色为 pillColor 的 16% 透明度，文字保持全强度 pillColor。
 */
@Component
export struct StatusPill {
  @Prop text: string = '';
  @Prop pillColor: Resource = $r('app.color.brand_primary');
  @Prop pillHeight: number = 24;
  @Prop fontSize: number = 12;

  /** 把 Resource 颜色解析为 16% 透明度的 rgba() 字符串 */
  private tintedBackground(): string {
    try {
      const metrics: ColorMetrics = ColorMetrics.resourceColor(this.pillColor);
      return `rgba(${Math.round(metrics.red)}, ${Math.round(metrics.green)}, ${Math.round(metrics.blue)}, 0.16)`;
    } catch (err) {
      return 'rgba(0, 0, 0, 0.16)';
    }
  }

  build() {
    Row() {
      Text(this.text)
        .fontSize(this.fontSize)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.pillColor)
    }
    .height(this.pillHeight)
    .padding({ left: 10, right: 10 })
    .borderRadius(8)
    .backgroundColor(this.tintedBackground())
    .alignItems(VerticalAlign.Center)
  }
}
