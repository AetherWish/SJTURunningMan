/**
 * 公共 UI 小组件
 * 迁移自 Android MainScreen.kt 中的 DropdownSelection @Composable
 * （SelectOption 为 ArkUI 组件全局类型，无需导入）
 *
 * HarmonyOS 系统应用风格适配：图标统一使用 HarmonyOS Symbol 系统符号
 * （SymbolGlyph / $r('sys.symbol.*')），不再使用 emoji 占位。
 * 参数配置行已改用 HDS 原生组件 HdsListItemCard（见 RunScreen.ets / AccountScreen.ets）。
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
 * HdsNavigation 在 FULL 大标题模式（仅主标题）下的标题栏高度（vp，官方规格：
 * 仅主标题 112vp，主+副标题 138vp）。titleBar 是悬浮层、覆盖在内容区上方，
 * 一级页内容首部必须预留等高空间避让，否则大标题会遮挡卡片/按钮等控件
 * （官方示例以 Blank().height(标题栏高度) 作为滚动内容首元素实现避让）。
 */
export const HDS_FULL_TITLE_BAR_HEIGHT: number = 112;

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
