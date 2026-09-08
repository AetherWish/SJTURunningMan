import { uiMaterial } from '@kit.ArkUI';

/**
 * 沉浸光感（uiMaterial.ImmersiveMaterial）运行时可用性守护。
 *
 * 背景：API 26 SDK 编译期可见 ImmersiveStyle / ImmersiveMaterial，但部分真机
 * （如实测 nova 12 Ultra，HarmonyOS 6.1.0.135 兼容运行时）运行时并未提供
 * ImmersiveStyle 枚举，在字段初始化中直接读取 uiMaterial.ImmersiveStyle.REGULAR
 * 会抛出 "Cannot read property REGULAR of undefined" 导致 jscrash 闪退。
 *
 * 方案：所有材质统一经本模块创建。先探测运行时能力（结果缓存，仅探测一次），
 * 不支持或构造失败时返回 undefined；ArkUI 官方签名
 * systemMaterial(material: SystemUiMaterial | undefined) 显式接受 undefined，
 * 传入后组件自动回退为普通样式，调用方无需分支处理。
 */
export class ImmersiveMaterialHelper {
  private static supported: boolean | null = null;

  /** 探测运行时是否支持沉浸光感（首次调用探测并缓存结果） */
  static isSupported(): boolean {
    if (ImmersiveMaterialHelper.supported === null) {
      try {
        // 设备缺失 ImmersiveStyle 时，读取其成员会抛 TypeError，由 catch 捕获
        const probe = new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR });
        ImmersiveMaterialHelper.supported = probe !== undefined && probe !== null;
      } catch (e) {
        ImmersiveMaterialHelper.supported = false;
      }
    }
    return ImmersiveMaterialHelper.supported;
  }

  /**
   * REGULAR 常规厚度材质（日志面板、Logo 卡片等小面积局部容器）。
   * 运行时不支持时返回 undefined，systemMaterial 自动降级为普通样式。
   */
  static regular(): uiMaterial.Material | undefined {
    return ImmersiveMaterialHelper.create(false);
  }

  /**
   * THIN 高透明 + 交互形变材质（可点击卡片）。
   * 运行时不支持时返回 undefined，systemMaterial 自动降级为普通样式。
   */
  static thinInteractive(): uiMaterial.Material | undefined {
    return ImmersiveMaterialHelper.create(true);
  }

  private static create(interactive: boolean): uiMaterial.Material | undefined {
    if (!ImmersiveMaterialHelper.isSupported()) {
      return undefined;
    }
    try {
      if (interactive) {
        return new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THIN,
          interactive: true
        });
      }
      return new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR });
    } catch (e) {
      return undefined;
    }
  }
}
