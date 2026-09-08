import { promptAction } from '@kit.ArkUI';
import { HdsNavDestination, HdsListItemCard, SuffixCustomBuilder, SuffixArrow } from '@kit.UIDesignKit';
import { hdsPrefixIcon, HdsCardOptions } from '../view/CommonComponents';
import { RouteInfo } from '../model/RouteInfo';
import { MainViewModel } from '../viewmodel/MainViewModel';

/**
 * 路线管理页（二级页，由“路线”页签的“路线管理”入口进入）
 * 提供以下设置项：
 * 1. 更换默认（启动时）路线：点“✓”将路线设为启动默认；
 * 2. 排序：上下箭头调整路线在下拉选项中的顺序；
 * 3. 删除路线：至少保留一条；删除启动默认路线时，顺位第一的路线自动成为新的默认；
 * 4. 还原到初始状态：恢复为仅包含“思源湖路线”。
 */
@Component
export struct RouteManagePage {
  viewModel: MainViewModel = MainViewModel.getInstance();

  /** 路线行卡片选项：名称/点数 + 设默认、上下移、删除控件 */
  private routeCardOptions(route: RouteInfo, index: number, total: number): HdsCardOptions {
    const options: HdsCardOptions = {
      prefixItem: hdsPrefixIcon($r('sys.symbol.map')),
      textItem: {
        primaryText: { text: route.name },
        secondaryText: { text: `${route.pointCount} 个点${route.isDefault ? ' · 启动默认' : ''}` }
      },
      suffixItem: new SuffixCustomBuilder((): void => {
        this.RouteControls(route, index, total);
      })
    };
    return options;
  }

  /** 行内控件：设为默认（当前默认以文本标记）、上移、下移、删除 */
  @Builder
  RouteControls(route: RouteInfo, index: number, total: number) {
    Row({ space: 4 }) {
      if (!route.isDefault) {
        Button() {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(14)
            .fontColor(['#FFFFFF'])
        }
        .width(32)
        .height(32)
        .borderRadius(8)
        .backgroundColor($r('app.color.brand_primary'))
        .onClick(() => {
          this.viewModel.setStartupRoute(route);
          promptAction.showToast({ message: `已设为启动默认路线: ${route.name}`, duration: 1500 });
        })
      } else {
        Text('默认')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.brand_primary'))
          .width(32)
          .textAlign(TextAlign.Center)
      }

      Button() {
        SymbolGlyph($r('sys.symbol.chevron_up'))
          .fontSize(14)
          .fontColor([$r('app.color.text_primary')])
      }
      .width(32)
      .height(32)
      .borderRadius(8)
      .backgroundColor($r('app.color.card_surface'))
      .enabled(index > 0)
      .opacity(index > 0 ? 1 : 0.4)
      .onClick(() => {
        this.viewModel.moveRoute(route, -1);
      })

      Button() {
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(14)
          .fontColor([$r('app.color.text_primary')])
      }
      .width(32)
      .height(32)
      .borderRadius(8)
      .backgroundColor($r('app.color.card_surface'))
      .enabled(index < total - 1)
      .opacity(index < total - 1 ? 1 : 0.4)
      .onClick(() => {
        this.viewModel.moveRoute(route, 1);
      })

      Button() {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(14)
          .fontColor([$r('app.color.error_color')])
      }
      .width(32)
      .height(32)
      .borderRadius(8)
      .backgroundColor(Color.Transparent)
      .enabled(total > 1)
      .opacity(total > 1 ? 1 : 0.4)
      .onClick(() => {
        this.confirmDeleteRoute(route);
      })
    }
    .alignItems(VerticalAlign.Center)
  }

  /** 还原初始状态卡片选项 */
  private restoreCardOptions(): HdsCardOptions {
    const options: HdsCardOptions = {
      prefixItem: hdsPrefixIcon($r('sys.symbol.arrow_counterclockwise')),
      textItem: {
        primaryText: { text: '还原到初始状态' },
        secondaryText: { text: '删除全部自定义路线，恢复为仅包含“思源湖路线”' }
      },
      suffixItem: new SuffixArrow(),
      onClick: (): void => {
        this.confirmRestore();
      }
    };
    return options;
  }

  /** 删除确认（等价 RunScreen 原删除对话框交互） */
  private confirmDeleteRoute(route: RouteInfo): void {
    AlertDialog.show({
      title: '删除路线',
      message: `确定要删除路线「${route.name}」吗？` +
        (this.viewModel.routes.length <= 1 ? '至少需要保留一条路线。' :
          '若删除的是启动默认路线，将自动改排序顺位第一的路线为默认。'),
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
          this.viewModel.deleteRoute(route);
        }
      }
    });
  }

  /** 还原确认 */
  private confirmRestore(): void {
    AlertDialog.show({
      title: '还原到初始状态',
      message: '将删除全部自定义路线，并恢复为仅包含“思源湖路线”。确定继续吗？',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '还原',
        fontColor: $r('app.color.error_color'),
        action: () => {
          this.viewModel.restoreRoutes();
          promptAction.showToast({ message: '已还原为初始路线状态', duration: 1500 });
        }
      }
    });
  }

  build() {
    HdsNavDestination() {
      Column() {
        Scroll() {
          Column({ space: 16 }) {
            Text('路线列表')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
              .margin({ left: 4 })

            // 官方结构：HdsListItemCard 置于 List>ListItem；key 含 index 保证排序变化后刷新
            List({ space: 8 }) {
              ForEach(this.viewModel.routes, (route: RouteInfo, index: number) => {
                ListItem() {
                  HdsListItemCard(this.routeCardOptions(route, index, this.viewModel.routes.length))
                    .width('100%')
                }
              }, (route: RouteInfo, index: number) => `${route.id}_${index}`)
            }
            .width('100%')

            Text('提示：对勾设为启动默认路线；上下箭头调整排序；删除至少保留一条路线。')
              .fontSize(12)
              .fontColor($r('app.color.outline'))
              .margin({ left: 4 })

            Text('其他')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
              .margin({ left: 4 })

            HdsListItemCard(this.restoreCardOptions())
              .width('100%')
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 16, bottom: 24 })
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
    .titleBar({
      content: {
        title: {
          mainTitle: '路线管理'
        }
      }
    })
  }
}
