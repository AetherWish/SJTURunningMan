import { fileIo as fs } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { GpsPoint, RouteInfo } from '../model/RouteInfo';
import { GpsUtil } from './GpsUtil';

/**
 * 路线管理
 * 迁移自 Android: com.sjtu.runner.route.RouteManager
 * - SharedPreferences(route_prefs) -> Preferences(route_prefs)
 * - context.filesDir/routes -> 应用沙箱 filesDir/routes
 * - res/raw/route_coordinates.txt -> resources/rawfile/route_coordinates.txt
 */
export class RouteManager {
  private static readonly PREF_NAME: string = 'route_prefs';
  private static readonly KEY_ROUTES: string = 'custom_routes';
  private static readonly DEFAULT_ROUTE_ID: string = 'default';
  private static readonly DEFAULT_ROUTE_NAME: string = '思源湖路线';
  private static readonly ROUTES_DIR: string = 'routes';

  private context: common.Context | null = null;
  private routesDirPath: string = '';

  private static instance: RouteManager | null = null;

  static getInstance(): RouteManager {
    if (RouteManager.instance === null) {
      RouteManager.instance = new RouteManager();
    }
    return RouteManager.instance;
  }

  /** 首次使用前初始化（等价 Android 构造函数中完成的准备工作） */
  init(context: common.Context): void {
    if (this.context !== null) {
      return;
    }
    this.context = context;
    this.routesDirPath = `${context.filesDir}/${RouteManager.ROUTES_DIR}`;
    try {
      if (!fs.accessSync(this.routesDirPath)) {
        fs.mkdirSync(this.routesDirPath, true);
      }
    } catch (e) {
      // 目录可能已存在
    }
  }

  private getPrefs(): preferences.Preferences | null {
    if (this.context === null) {
      return null;
    }
    try {
      return preferences.getPreferencesSync(this.context, { name: RouteManager.PREF_NAME });
    } catch (e) {
      return null;
    }
  }

  /** 获取默认路线 */
  getDefaultRoute(): RouteInfo {
    const route: RouteInfo = {
      id: RouteManager.DEFAULT_ROUTE_ID,
      name: RouteManager.DEFAULT_ROUTE_NAME,
      filePath: '',
      isDefault: true,
      pointCount: this.getDefaultRoutePointCount(),
      createdAt: 0
    };
    return route;
  }

  /** 获取所有自定义路线 */
  getCustomRoutes(): RouteInfo[] {
    const prefs = this.getPrefs();
    if (prefs === null) {
      return [];
    }
    try {
      const json = prefs.getSync(RouteManager.KEY_ROUTES, '[]') as string;
      const routes = JSON.parse(json) as RouteInfo[];
      // 更新每个路线的点数量
      const result: RouteInfo[] = [];
      for (let i = 0; i < routes.length; i++) {
        const r: RouteInfo = {
          id: routes[i].id,
          name: routes[i].name,
          filePath: routes[i].filePath,
          isDefault: routes[i].isDefault,
          pointCount: this.getRoutePointCount(routes[i]),
          createdAt: routes[i].createdAt
        };
        result.push(r);
      }
      return result;
    } catch (e) {
      return [];
    }
  }

  /** 获取所有路线（默认+自定义） */
  getAllRoutes(): RouteInfo[] {
    const result: RouteInfo[] = [this.getDefaultRoute()];
    const customRoutes = this.getCustomRoutes();
    for (let i = 0; i < customRoutes.length; i++) {
      result.push(customRoutes[i]);
    }
    return result;
  }

  /** 保存自定义路线（等价 saveCustomRoute） */
  saveCustomRoute(name: string, coordinates: GpsPoint[]): RouteInfo | null {
    if (name.trim().length === 0 || coordinates.length === 0 || this.context === null) {
      return null;
    }

    // 生成唯一文件名
    const fileName = `${name}_${Date.now()}.txt`;
    const routeFilePath = `${this.routesDirPath}/${fileName}`;

    // 保存坐标到文件
    let content = '';
    for (let i = 0; i < coordinates.length; i++) {
      content += `${coordinates[i].lon},${coordinates[i].lat}\n`;
    }
    let success = false;
    try {
      const file = fs.openSync(routeFilePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, content);
      fs.closeSync(file.fd);
      success = true;
    } catch (e) {
      success = false;
    }
    if (!success) {
      return null;
    }

    const routeId = fileName.substring(0, fileName.length - 4);
    const newRoute: RouteInfo = {
      id: routeId,
      name: name,
      filePath: routeFilePath,
      isDefault: false,
      pointCount: coordinates.length,
      createdAt: Date.now()
    };

    // 更新自定义路线列表
    const currentRoutes = this.getCustomRoutes();
    currentRoutes.push(newRoute);
    this.saveRouteList(currentRoutes);

    return newRoute;
  }

  /** 删除自定义路线 */
  deleteRoute(routeId: string): boolean {
    const currentRoutes = this.getCustomRoutes();
    let routeToDelete: RouteInfo | null = null;
    let index = -1;
    for (let i = 0; i < currentRoutes.length; i++) {
      if (currentRoutes[i].id === routeId) {
        routeToDelete = currentRoutes[i];
        index = i;
        break;
      }
    }
    if (routeToDelete === null) {
      return false;
    }

    // 删除文件
    try {
      if (fs.accessSync(routeToDelete.filePath)) {
        fs.unlinkSync(routeToDelete.filePath);
      }
    } catch (e) {
      // 文件不存在时忽略
    }

    // 更新列表
    currentRoutes.splice(index, 1);
    this.saveRouteList(currentRoutes);
    return true;
  }

  /** 获取路线的坐标点列表（等价 getRouteCoordinates） */
  async getRouteCoordinates(route: RouteInfo): Promise<GpsPoint[]> {
    if (route.isDefault || this.context === null) {
      return this.readDefaultRouteCoordinates();
    }
    return GpsUtil.readCoordinatesFromFile(route.filePath);
  }

  /** 读取默认路线坐标（供 ViewModel 调用） */
  async readDefaultRouteCoordinates(): Promise<GpsPoint[]> {
    if (this.context === null) {
      return [];
    }
    return GpsUtil.readDefaultCoordinates(this.context);
  }

  /** 获取路线点数（用于显示） */
  private getRoutePointCount(route: RouteInfo): number {
    if (route.isDefault) {
      return this.getDefaultRoutePointCount();
    }
    try {
      if (!fs.accessSync(route.filePath)) {
        return 0;
      }
      const text = fs.readTextSync(route.filePath, { encoding: 'utf-8' });
      return GpsUtil.countCoordinateLines(text);
    } catch (e) {
      return 0;
    }
  }

  private getDefaultRoutePointCount(): number {
    if (this.context === null) {
      return 0;
    }
    try {
      const text = GpsUtil.readDefaultRouteTextSync(this.context);
      return GpsUtil.countCoordinateLines(text);
    } catch (e) {
      return 0;
    }
  }

  private saveRouteList(routes: RouteInfo[]): void {
    const prefs = this.getPrefs();
    if (prefs === null) {
      return;
    }
    try {
      prefs.putSync(RouteManager.KEY_ROUTES, JSON.stringify(routes));
      prefs.flushSync();
    } catch (e) {
      // 保存失败
    }
  }
}
