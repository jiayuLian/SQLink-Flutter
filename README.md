# SQLink（Flutter 版）

**一个装在你手机上的 MySQL 客户端**——随时随地在 Android / iPhone 上连数据库、看表、跑 SQL、改数据。

SQLink 最初是 iOS 上的 Swift 独立 App。为了让安卓也能用、并且**不限制任何功能**，我们用 Flutter 重写了它：一套代码同时出 Android（APK）和 iOS（IPA），所有能力全部开放，**没有会员、没有激活、没有后端账号体系**。

---

## 这软件能帮你干什么？

- **出门在外也能管数据库**：不用开电脑、不用连堡垒机，手机点开就连上你的 MySQL，查数据、排错、应急改一条配置都行。
- **手机上直接写 SQL**：完整的查询控制台，支持多语句、结果集、历史记录，还能自动补全关键字 / 表名 / 字段名。
- **像看 Excel 一样看表**：表数据分页浏览、排序、按条件筛选、统计行数，一键导出 CSV 带走。
- **当场改数据**：设置筛选或排序后，直接在单元格上就地修改，不用导出再导回。
- **库表再多也不慌**：数据库列表、表列表顶部都支持实时搜索，几百张表一输就定位。

---

## 为什么选它（好处）

| 好处 | 说明 |
| --- | --- |
| **全功能免费** | 不复制原 Swift 版的会员 / 激活体系，所有功能直接开放，零门槛。 |
| **双端通用** | 同一套 Flutter 代码，Android 和 iOS 都能装，体验一致。 |
| **纯本地、更安全** | 连接密码只存在你手机里（iOS Keychain / Android 加密存储），不依赖任何后端服务，账号密码不出本机。 |
| **连得稳** | 兼容 NAT64 / IPv6-only 网络（纯 IPv6 蜂窝网也能连）；Android 已内置联网权限，不会出现「连不上」的权限坑。 |
| **iOS 免开发者账号安装** | 未签名 IPA 经 TrollStore 安装时自动完成签名，**永久有效、不依赖 Apple ID / 开发者账号 / Mac**，比传统 7 天自签省心。 |
| **报错看得懂** | 连接失败时区分「账号错 / 密码错 / 网络不可达」，直接给中文原因，不再甩一句 `Exception:`。 |

---

## 功能一览

- **多连接管理**：保存多个数据库连接（名称 / 主机 / 端口 / 用户 / 默认库 / 密码 / TLS / 自签信任），一台手机管所有库。
- **密码安全存储**：iOS Keychain、Android EncryptedSharedPreferences，明文不落盘。
- **库表浏览**：数据库 → 表 / 视图 → 列（类型、键、NOT NULL）；列表顶部支持实时搜索名称。
- **表数据浏览**：分页、排序、WHERE 筛选、行数统计、CSV 导出。
- **表数据内联编辑**：设置筛选或排序后可就地改单元格；未设置时隐藏编辑入口，避免误改全表数据。
- **查询控制台**：任意 SQL、多语句结果集、SQL 历史、关键字 / 表名 / 字段名自动补全、CSV 导出。
- **连接错误分类提示**：账号错误 / 密码错误 / 网络不可达（拒绝连接、超时、DNS 失败）分别给出对应中文提示。
- **TLS 加密连接**：支持自签名证书信任（`onBadCertificate`）。
- **认证兼容**：支持 `mysql_native_password` 与 `caching_sha2_password`（MySQL 8 默认认证方式）。
- **iOS 风格交互**：连接列表左滑删除为窄条 + 确认弹窗，不再整行红底遮挡内容。

---

## 安装（极简）

- **Android**：下载 Release 里的 `SQLink-Flutter.apk`，允许「未知来源」后安装即可。
- **iOS**：iPhone 用 Safari 打开 Release 页（私有仓库需登录 GitHub），点 `SQLink-Flutter.ipa` → 用 **TrollStore** 打开安装。需设备兼容 TrollStore；安装时自动完成签名，**无需 Apple ID**。

> 手机桌面上显示的名字就是 **`SQLink`**。

---

## 从源码构建（开发者向）

```bash
flutter pub get
flutter run                          # 本地调试
flutter build apk --release          # Android
flutter build ios --release --no-codesign   # iOS 未签名 IPA（需 macOS）
```

iOS 未签名 IPA 本地打包（macOS）：

```bash
cd build/ios/iphoneos
mkdir -p Payload
cp -r Runner.app Payload/
zip -r SQLink-Flutter.ipa Payload
```

> 产物为**未签名** IPA，不能直接装；用 **TrollStore** 打开安装时会在设备上完成签名（CoreTrust 漏洞，永久有效，无需 Apple ID）。这与传统「自签」（AltStore / Sideloadly 用免费 Apple ID 签名、7 天过期需重签）不同。

推送 `main` 分支即由 GitHub Actions 自动构建并发布（Android `SQLink-Flutter.apk` / iOS `SQLink-Flutter.ipa`）。

---

## 与原 Swift 版的差异

- 不复制 Swift 版的账号 / 会员 / 后端激活体系（原版依赖私有后端 `sqlink-api`），本版**全功能免费开放**。
- 表数据内联编辑基于「设置筛选或排序」后就地修改，未设置筛选时仅浏览、不直接改全表数据（与原 Swift 版基于主键的整行编辑略有不同）。
- 多端一致：同一套 Flutter 代码同时覆盖 Android 与 iOS，原 Swift 版仅限 iOS。
