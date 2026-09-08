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
 *
 * 启动默认路线与排序（路线管理页引入）：
 * - startup_route_id：启动默认路线 id（预选与“默认”标记的依据），缺省为内置路线；
 * - route_order：路线展示顺序（id 数组），新保存的自定义路线追加到末尾；
 * - 删除约束：至少保留一条路线；删除启动默认路线时，顺位第一的路线自动成为新的启动默认；
 * - 内置思源湖路线也可被删除（坐标文件为 rawfile 只读资源，删除仅移出列表）。
 */
export class RouteManager {
  private static readonly PREF_NAME: string = 'route_prefs';
  private static readonly KEY_ROUTES: string = 'custom_routes';
  private static readonly KEY_STARTUP_ROUTE_ID: string = 'startup_route_id';
  private static readonly KEY_ROUTE_ORDER: string = 'route_order';
  /** 内置路线（思源湖）固定 id：坐标读取走 rawfile 的唯一判据（勿用 isDefault，其含义已是“启动默认”） */
  static readonly BUILTIN_ROUTE_ID: string = 'default';
  private static readonly BUILTIN_ROUTE_NAME: string = '思源湖路线';
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

  /** 获取内置路线（思源湖）定义；isDefault 仅为占位，实际以启动默认路线判定为准 */
  getDefaultRoute(): RouteInfo {
    const route: RouteInfo = {
      id: RouteManager.BUILTIN_ROUTE_ID,
      name: RouteManager.BUILTIN_ROUTE_NAME,
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

  /**
   * 获取全部路线（内置 + 自定义）。
   * 顺序按持久化的 route_order；isDefault 标记启动默认路线。
   */
  getAllRoutes(): RouteInfo[] {
    const order = this.getRouteOrder();
    const startupId = this.resolveStartupRouteId(order);
    const result: RouteInfo[] = [];
    for (let i = 0; i < order.length; i++) {
      const route = this.findById(this.getAllRoutesUnordered(), order[i]);
      if (route === null) {
        continue;
      }
      const item: RouteInfo = {
        id: route.id,
        name: route.name,
        filePath: route.filePath,
        isDefault: route.id === startupId,
        pointCount: route.pointCount,
        createdAt: route.createdAt
      };
      result.push(item);
    }
    return result;
  }

  private getAllRoutesUnordered(): RouteInfo[] {
    const result: RouteInfo[] = [this.getDefaultRoute()];
    const customRoutes = this.getCustomRoutes();
    for (let i = 0; i < customRoutes.length; i++) {
      result.push(customRoutes[i]);
    }
    return result;
  }

  private findById(routes: RouteInfo[], id: string): RouteInfo | null {
    for (let i = 0; i < routes.length; i++) {
      if (routes[i].id === id) {
        return routes[i];
      }
    }
    return null;
  }

  /**
   * 获取路线展示顺序（规范化后持久化）。
   * 兼容旧数据：首次读取时按“内置路线 + 自定义路线”的旧顺序生成并落盘；
   * 新保存的路线由 saveCustomRoute 追加到末尾。
   */
  private getRouteOrder(): string[] {
    let order: string[] = [];
    const prefs = this.getPrefs();
    if (prefs !== null) {
      try {
        const json = prefs.getSync(RouteManager.KEY_ROUTE_ORDER, '[]') as string;
        const parsed = JSON.parse(json) as string[];
        for (let i = 0; i < parsed.length; i++) {
          if (typeof parsed[i] === 'string') {
            order.push(parsed[i]);
          }
        }
      } catch (e) {
        order = [];
      }
    }
    // 规范化：剔除无效 id、去重，并把缺失的路线（内置/新增/旧数据）按序补到末尾
    const all = this.getAllRoutesUnordered();
    const validIds: string[] = [];
    for (let i = 0; i < all.length; i++) {
      validIds.push(all[i].id);
    }
    const normalized: string[] = [];
    for (let i = 0; i < order.length; i++) {
      const id = order[i];
      if (validIds.indexOf(id) >= 0 && normalized.indexOf(id) < 0) {
        normalized.push(id);
      }
    }
    for (let i = 0; i < validIds.length; i++) {
      if (normalized.indexOf(validIds[i]) < 0) {
        normalized.push(validIds[i]);
      }
    }
    if (normalized.length !== order.length) {
      this.saveRouteOrder(normalized);
    }
    return normalized;
  }

  /** 解析启动默认路线 id（无效时回退为排序顺位第一） */
  private resolveStartupRouteId(order: string[]): string {
    let saved = RouteManager.BUILTIN_ROUTE_ID;
    const prefs = this.getPrefs();
    if (prefs !== null) {
      try {
        saved = prefs.getSync(RouteManager.KEY_STARTUP_ROUTE_ID, RouteManager.BUILTIN_ROUTE_ID) as string;
      } catch (e) {
        saved = RouteManager.BUILTIN_ROUTE_ID;
      }
    }
    for (let i = 0; i < order.length; i++) {
      if (order[i] === saved) {
        return saved;
      }
    }
    return order.length > 0 ? order[0] : RouteManager.BUILTIN_ROUTE_ID;
  }

  /** 设置启动默认路线（id 须存在于当前路线中） */
  setStartupRoute(routeId: string): boolean {
    const order = this.getRouteOrder();
    if (order.indexOf(routeId) < 0) {
      return false;
    }
    const prefs = this.getPrefs();
    if (prefs === null) {
      return false;
    }
    try {
      prefs.putSync(RouteManager.KEY_STARTUP_ROUTE_ID, routeId);
      prefs.flushSync();
      return true;
    } catch (e) {
      return false;
    }
  }

  /** 保存自定义路线（等价 saveCustomRoute），新路线追加到排序末尾 */
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

    // 更新自定义路线列表与展示顺序
    const currentRoutes = this.getCustomRoutes();
    currentRoutes.push(newRoute);
    this.saveRouteList(currentRoutes);
    const order = this.getRouteOrder();
    if (order.indexOf(newRoute.id) < 0) {
      order.push(newRoute.id);
      this.saveRouteOrder(order);
    }

    return newRoute;
  }

  /**
   * 删除路线。
   * 约束：至少保留一条路线；删除启动默认路线时，顺位第一的路线自动成为新的启动默认。
   * 内置思源湖路线也可删除（仅移出列表，rawfile 资源保留）。
   */
  deleteRoute(routeId: string): boolean {
    const order = this.getRouteOrder();
    if (order.length <= 1) {
      return false; // 至少保留一条路线
    }
    const index = order.indexOf(routeId);
    if (index < 0) {
      return false;
    }
    const wasStartup = this.resolveStartupRouteId(order) === routeId;

    // 自定义路线需同步删除坐标文件
    if (routeId !== RouteManager.BUILTIN_ROUTE_ID) {
      const target = this.findById(this.getCustomRoutes(), routeId);
      if (target !== null) {
        try {
          if (fs.accessSync(target.filePath)) {
            fs.unlinkSync(target.filePath);
          }
        } catch (e) {
          // 文件不存在时忽略
        }
        const currentRoutes = this.getCustomRoutes();
        for (let i = 0; i < currentRoutes.length; i++) {
          if (currentRoutes[i].id === routeId) {
            currentRoutes.splice(i, 1);
            break;
          }
        }
        this.saveRouteList(currentRoutes);
      }
    }

    order.splice(index, 1);
    this.saveRouteOrder(order);
    if (wasStartup && order.length > 0) {
      this.saveStartupRouteId(order[0]);
    }
    return true;
  }

  /**
   * 按给定 id 顺序持久化路线排序（拖拽排序）。
   * 校验：id 集合须与当前路线完全一致（无缺失、无重复、无多余）。
   */
  setRouteOrder(orderedIds: string[]): boolean {
    const current = this.getRouteOrder();
    if (orderedIds.length !== current.length) {
      return false;
    }
    for (let i = 0; i < orderedIds.length; i++) {
      if (current.indexOf(orderedIds[i]) < 0 || orderedIds.indexOf(orderedIds[i]) !== i) {
        return false;
      }
    }
    this.saveRouteOrder(orderedIds);
    return true;
  }

  /** 还原到初始状态：删除全部自定义路线，仅保留内置思源湖路线并设为启动默认 */
  restoreInitial(): void {
    const customs = this.getCustomRoutes();
    for (let i = 0; i < customs.length; i++) {
      try {
        if (fs.accessSync(customs[i].filePath)) {
          fs.unlinkSync(customs[i].filePath);
        }
      } catch (e) {
        // 文件不存在时忽略
      }
    }
    this.saveRouteList([]);
    const initialOrder: string[] = [RouteManager.BUILTIN_ROUTE_ID];
    this.saveRouteOrder(initialOrder);
    this.saveStartupRouteId(RouteManager.BUILTIN_ROUTE_ID);
  }

  /** 获取路线的坐标点列表（等价 getRouteCoordinates） */
  async getRouteCoordinates(route: RouteInfo): Promise<GpsPoint[]> {
    if (route.id === RouteManager.BUILTIN_ROUTE_ID || this.context === null) {
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
    if (route.id === RouteManager.BUILTIN_ROUTE_ID) {
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

  private saveRouteOrder(order: string[]): void {
    const prefs = this.getPrefs();
    if (prefs === null) {
      return;
    }
    try {
      prefs.putSync(RouteManager.KEY_ROUTE_ORDER, JSON.stringify(order));
      prefs.flushSync();
    } catch (e) {
      // 保存失败
    }
  }

  private saveStartupRouteId(routeId: string): void {
    const prefs = this.getPrefs();
    if (prefs === null) {
      return;
    }
    try {
      prefs.putSync(RouteManager.KEY_STARTUP_ROUTE_ID, routeId);
      prefs.flushSync();
    } catch (e) {
      // 保存失败
    }
  }
}
