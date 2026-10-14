# 常见问题与故障排除

## 通用

### 上传失败怎么办

此版本已兼容异地登录。若仍失败，按顺序排查：

1. **清除应用数据** —— 手机：**设置 → 应用管理 → 找到本应用 → 存储 → 清除数据 + 清除缓存**，然后重开应用重新登录；
2. **检查 Cookie 有效性** —— Cookie 通常只有几小时到几天的有效期，过期后需重新登录获取；手动粘贴时确认没有遗漏字符；
3. **检查网络** —— 换 WiFi / 移动数据试，确认没被校园网限制；
4. **等一会儿** —— 可能是交我办服务器维护或故障，稍后重试。

### 第一次跑该选多少

**选 1 次**，距离 2 km 以上，先验证账号与流程都通，再上量。

### 为什么不要选 1 km

路线补点算法在极短距离下容易凑不满，最终可能不足 1 km。推荐 **2 km 及以上**。

### 多设备登录

同一账号在多台设备同时登录可能导致 Cookie 失效。别在多个设备上同时挂着。

### Cookie 安全

Cookie 等同于登录凭证，**不要分享给任何人**，也不要贴进 issue、日志或截图里。详见 [SECURITY.md](../SECURITY.md)。

---

## 电脑版

### 启动被 SmartScreen / Gatekeeper 拦

- Windows：点「更多信息」→「仍要运行」；
- macOS：**系统设置 → 隐私与安全性** → 「仍要打开」。

### 预览路线打不开

- 预览 HTML 写入系统临时目录后交给默认浏览器打开。确认系统有默认浏览器；
- 若被安全软件拦截临时目录，换一个默认下载/临时目录或临时关闭拦截。

### 打包出来的 exe 没有图标

用了 `pyinstaller qtui.py` 而不是 `main.spec`。请按 [build.md](./build.md#打包) 用 spec 打包。

### 导入的路线重启后不见了

导入的路线会复制到**软件所在目录**的 `Routes/` 文件夹。如果软件装在只读目录（如 `Program Files`），写不进去。把程序放到有写权限的目录再导入。

### 下拉框选了「自定义...」没反应

需要先在文件对话框里选中一个 `.txt` 路线文件。若文件格式不对（不是每行 `经度,纬度`），会被拒绝。

---

## 安卓 / 鸿蒙

### 装不上 APK / HAP

- **安卓**：在安装提示里允许「未知来源应用」；
- **鸿蒙**：调试证书有效期很短，先完成**华为开发者认证**再装，否则装完很快失效。

### 鸿蒙拉不起「交我办」

鸿蒙端**不支持**快捷登录，只能走 JAccount 网页登录。这是平台限制，非缺陷。

### 应用一直停在登录页

1. 确认手机能正常访问 `pe.sjtu.edu.cn`；
2. 清除应用数据后重试；
3. 若 SJTU SSO 正在维护，等一段时间再试。

---

## iOS

| 现象 | 处理 |
| --- | --- |
| **「Failed to register bundle identifier」** | 把 Bundle ID 改成唯一的（见 [ios.md](./ios.md#设置-bundle-identifier可选)） |
| **装不上 / 「不受信任的开发者」** | iPhone：**设置 → 通用 → VPN 与设备管理** → 点你的开发者描述文件 → 信任 |
| **登录页打不开** | 确认 iPhone 有网。应用走 JAccount OAuth2，SJTU SSO 挂了就只能等 |
| **Cookie 过期** | 应用会检测并显示「重新登录」按钮，点它重新登录 |
| **签名报错** | 确认 Team ID 正确，且 Xcode → Settings → Accounts 里有有效的开发者证书 |
| **「No devices registered」（免费账号）** | 免费账号只能在 1–2 台设备上跑。连上 iPhone 构建运行一次，Xcode 会自动注册；但免费账号无法把应用分享给他人 |

---

## 验证下载的安装包

从 Releases 下载之后，可以核对两件事。

### 1. 完整性 —— 文件在传输中没被改动

Release 正文里有每个产物的 SHA256，也可以把 `SHA256SUMS.txt` 一起下下来核对：

```bash
# macOS / Linux：与 SHA256SUMS.txt 放在同一目录
sha256sum -c SHA256SUMS.txt
```

```powershell
# Windows PowerShell
Get-FileHash .\SJTURunningMan_<版本>_windows.exe -Algorithm SHA256
```

两边的值一致即为完整。

### 2. 构建来源 —— 是 CI 构建的，不是从某台本机传的

每个产物都带一份**来源证明**，由 GitHub OIDC 签发，绑定具体的提交与工作流运行：

```bash
# 需要 gh CLI 2.49 及以上：https://cli.github.com/
gh attestation verify SJTURunningMan_<版本>_windows.exe \
  --repo JackyTJie/SJTURunningMan_Advanced_Edition
```

通过时会打印签名证书与工作流信息。**这份证明在本机无法伪造** —— 它能证明这个文件是 GitHub Actions 按 `release.yml` 在对应提交上构建出来的。

> 说明：来源证明只能证明「怎么构建的」，不能证明「软件可信」—— 能触发该工作流的人同样能签出有效证明。安卓 APK 除来源证明外还有一层**自签名**，用于保证同一作者的版本可以覆盖升级，两者是不同层面的保证。

### 提示文件损坏 / 打不开

先按上面第 1 步核对 SHA256：

- **对得上** —— 文件是完整的，问题多半是系统拦截（Windows SmartScreen、macOS Gatekeeper，见下方对应条目）；
- **对不上** —— 下载过程中损坏了，重新下载即可。

## 还没解决？

- 先搜 [Issues](https://github.com/JackyTJie/SJTURunningMan_Advanced_Edition/issues) 有没有同样的问题；
- 没有的话按 [bug 模板](https://github.com/JackyTJie/SJTURunningMan_Advanced_Edition/issues/new/choose) 提一个，**记得脱敏**：不要贴 Cookie、密码、验证码、真实姓名学号；
- 安全问题走 [SECURITY.md](../SECURITY.md) 的私有通道，不要开公开 issue。
