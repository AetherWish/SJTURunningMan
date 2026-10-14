/**
 * 公共 UI 小组件
 * 迁移自 Android MainScreen.kt 中的 DropdownSelection @Composable
 * （SelectOption 为 ArkUI 组件全局类型，无需导入）
 *
 * HarmonyOS 系统应用风格适配：图标统一使用 HarmonyOS Symbol 系统符号
 * （SymbolGlyph / $r('sys.symbol.*')），不再使用 emoji 占位。
 * 静态信息行使用 HDS 原生组件 HdsListItemCard（见 RunScreen.ets）；
 * 带交互控件的参数行改用本文件的自绘 SettingCard —— HdsListItemCard 的自定义
 * 后缀构建器不参与尺寸测量，控件会溢出卡片（详见 HDS_CARD_RADIUS 处的说明）。
 */
import {
  PrefixIcon,
  PrefixIconOptions,
  SymbolGlyphOptions,
  TextOptions,
  IconSize,
  OnClickCallback,
  SuffixArrow,
  SuffixCustomBuilder,
  SuffixText
} from '@kit.UIDesignKit';

/**
 * HdsNavigation 在 MINI 标题模式下的标题栏高度（vp）。
 * 一级页使用 MINI 模式（标题与右上角菜单按钮同一行，见 Index.ets），
 * titleBar 是悬浮层、覆盖在内容区上方，内容首部必须预留等高空间避让，
 * 否则标题栏会遮挡卡片/按钮等控件（官方示例以 Blank().height(标题栏高度) 作为滚动内容首元素实现避让）。
 */
export const HDS_MINI_TITLE_BAR_HEIGHT: number = 56;

/**
 * 任务设置卡片（自绘，视觉对齐 HdsListItemCard）的几何常量，单位 vp。
 *
 * 为什么自绘：HdsListItemCard 的 suffixItem 只接受 Builder（SuffixCustomBuilder），
 * 该自定义构建器的内容不参与卡片的尺寸测量 —— 实测把 8 个 ChoiceChips 放进后缀区时，
 * 卡片高度仍是 64vp（按 SuffixText 的固定行高），内部 Flex 却按屏宽排版并溢出卡片
 * （胶囊画到了卡片外、与上一张卡片的按钮重叠）。给后缀内容显式设宽度只解决了横向溢出，
 * 纵向仍需给卡片写死高度。这里改用原生 Column 自绘卡片：内容由 ArkUI 正常测量，
 * 尺寸自适应，不再需要估算高度。
 */
export const HDS_CARD_RADIUS: number = 16;
export const HDS_CARD_PADDING: number = 16;
/** 前缀图标列宽度（HdsListItemCard 实测为 84px / 42vp） */
export const HDS_ICON_COLUMN: number = 42;
/** 前缀图标字号（HdsListItemCard 实测为 22vp） */
export const HDS_ICON_SIZE: number = 22;
/** 文本列到后缀列的间距 */
export const HDS_TEXT_SUFFIX_GAP: number = 8;

/**
 * HdsListItemCard 文本区的本地结构声明。
 * kit 未再导出 TextItemOptions（@kit.UIDesignKit 仅导出 TextOptions），
 * 故按结构兼容原则仅声明用到的字段。
 */
interface CardTextItemOptions {
  primaryText?: TextOptions;
  secondaryText?: TextOptions;
}

/**
 * HdsListItemCard 选项的本地结构声明（结构兼容 kit 的 HdsListItemCardOptions）。
 * kit 的 HdsListItemCardOptions 引用了未随 kit 导出的 TextItemOptions，
 * 编译器的字面量检查无法完整解析该接口，导致以它为上下文类型的对象字面量
 * 全部被判为 arkts-no-untyped-obj-literals；改用本声明后字面量可正常通过检查，
 * 传参时依赖 ArkTS 的结构类型兼容（各字段类型均为 kit 类型的子类型）。
 */
export interface HdsCardOptions {
  /** 左侧前缀图标（系统符号） */
  prefixItem?: PrefixIcon;
  /** 中部文本区 */
  textItem?: CardTextItemOptions;
  /** 右侧后缀控件（自定义构建器 / 文本 / 箭头） */
  suffixItem?: SuffixCustomBuilder | SuffixText | SuffixArrow;
  /** 整卡点击回调 */
  onClick?: OnClickCallback;
}

/**
 * 构造 HdsListItemCard 的前缀系统符号图标。
 * 以显式类型对象构造，规避 ArkTS 对联合类型上下文字面量的限制
 * （PrefixIconType = ImageOptions | SymbolGlyphOptions）。
 */
export function hdsPrefixIcon(res: Resource): PrefixIcon {
  const symbolOptions: SymbolGlyphOptions = { symbol: res };
  const iconOptions: PrefixIconOptions = {
    iconSize: IconSize.SYSTEM_ICON,
    iconValue: symbolOptions
  };
  return new PrefixIcon(iconOptions);
}

/** 构造 HdsListItemCard 的主标题文本（列表行标签）。 */
export function hdsLabelItem(label: string): CardTextItemOptions {
  return { primaryText: { text: label } };
}

/** 构造 Select 选项数组 */
export function toSelectOptions(values: string[]): SelectOption[] {
  const options: SelectOption[] = [];
  for (let i = 0; i < values.length; i++) {
    const option: SelectOption = { value: values[i] };
    options.push(option);
  }
  return options;
}

/**
 * 带交互控件的参数行卡片（视觉对齐 HdsListItemCard，尺寸由 ArkUI 正常测量）。
 *
 * 用途与理由见文件头与 HDS_CARD_RADIUS 的说明：HdsListItemCard 的自定义后缀
 * 不参与测量，控件会溢出卡片；本组件用原生 Row/Column 复刻其外观，
 * 左侧系统符号 + 标签文本，右侧 @BuilderParam 承载任意控件（胶囊组/时间输入/滑杆）。
 *
 * fullWidth：控件横向占满整张卡片（标签移到控件上方）。
 * 原因：ArkUI 的 Text 有 64vp 的最小宽度且不随内容收缩，并排布局下即便卡片很宽，
 * 标签列也会吃掉一截，胶囊组只能拿到约 280vp —— 实测 8 个胶囊被迫换到 3 行。
 * 需要宽控件的行（跑步次数/目标距离）用 fullWidth，控件拿满 ~500vp，胶囊一行放下。
 */
@Component
export struct SettingCard {
  /** 标签文本 */
  label: string = '';
  /** 左侧系统符号（不传则不渲染图标列） */
  symbol: Resource | undefined = undefined;
  /** 控件是否横向占满卡片（标签移到上方） */
  fullWidth: boolean = false;
  /** 卡片主体内容 */
  @BuilderParam control: () => void;

  build() {
    if (this.fullWidth) {
      Column() {
        Row() {
          if (this.symbol !== undefined) {
            SymbolGlyph(this.symbol)
              .fontSize(HDS_ICON_SIZE)
              .fontColor([$r('app.color.brand_primary')])
              .margin({ right: HDS_TEXT_SUFFIX_GAP })
          }
          Text(this.label)
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Column() {
          this.control()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ top: 12 })
      }
      .width('100%')
      .padding(HDS_CARD_PADDING)
      .borderRadius(HDS_CARD_RADIUS)
      .backgroundColor($r('app.color.card_surface'))
    } else {
      Row() {
        if (this.symbol !== undefined) {
          Column() {
            SymbolGlyph(this.symbol)
              .fontSize(HDS_ICON_SIZE)
              .fontColor([$r('app.color.brand_primary')])
          }
          .width(HDS_ICON_COLUMN)
          .alignItems(HorizontalAlign.Start)
        }

        Text(this.label)
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .margin({ right: HDS_TEXT_SUFFIX_GAP })

        Column() {
          this.control()
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding(HDS_CARD_PADDING)
      .borderRadius(HDS_CARD_RADIUS)
      .backgroundColor($r('app.color.card_surface'))
      .alignItems(VerticalAlign.Center)
    }
  }
}

/**
 * 下拉选择（等价 Android DropdownSelection）
 */
@Component
export struct DropdownSelection {
  options: string[] = [];
  selected: string = '';
  selectedIdx: number = 0;
  onSelect: (value: string) => void = (value: string) => {
  };

  build() {
    Select(toSelectOptions(this.options))
      .selected(this.selectedIdx)
      .value(this.selected)
      .fontColor($r('app.color.text_primary'))
      .font({ size: 14 })
      .optionFont({ size: 14 })
      .selectedOptionFont({ size: 14 })
      .onSelect((index: number, text?: string) => {
        if (text !== undefined) {
          this.onSelect(text);
        }
      })
  }
}
