# SQLink (Flutter)

远程 MySQL 客户端，使用 Flutter 重写，一套代码同时出 **Android (APK)** 与 **iOS (IPA)**。

> 与原 Swift 版 `jiayuLian/SQLink` 并存、互不干扰。Swift 版保留不动。
> 本 Flutter 版为**纯本地客户端**：连接密码仅存本机（iOS Keychain / Android 加密存储），不依赖任何后端服务。
> 与 Swift 版不同，本版**不限制任何功能、无会员/激活体系**，所有能力全部开放。

## 功能

- 多连接管理（名称 / 主机 / 端口 / 用户 / 默认库 / 密码 / TLS / 自签信任）
- 密码安全存储：iOS Keychain、Android EncryptedSharedPreferences
- 库表浏览：数据库 → 表/视图 → 列（类型、键、NOT NULL）；数据库列表与表列表顶部均支持实时搜索名称
- 表数据浏览：分页、排序、WHERE 筛选、行数统计、CSV 导出
- 表数据内联编辑：设置筛选或排序后可就地修改单元格（未设置时隐藏编辑入口，避免误改全表数据）
- 查询控制台：任意 SQL、多语句结果集、SQL 历史、关键字/表名/字段名自动补全、CSV 导出
- 连接测试错误分类提示：账号错误 / 密码错误 / 网络不可达（拒绝连接、超时、DNS 失败）分别给出对应中文提示，而非笼统的 `Exception:`
- TLS 加密连接，支持自签名证书信任（`onBadCertificate`）
- 支持 `mysql_native_password` 与 `caching_sha2_password`（MySQL 8 默认）
- 连接列表左滑删除采用 iOS 风格窄条（确认弹窗），不再整行红底遮挡

## 网络兼容性

- 连接时直接传入字符串 `host`，由底层按 `InternetAddress.lookup` 解析，**兼容 NAT64 / IPv6-only 网络**（如纯 IPv6 蜂窝网络会合成 IPv6 地址），不会因强制 IPv4 而出现 `errno 65` 连接失败。
- Android 端在 CI 构建时自动注入 `INTERNET` 与 `ACCESS_NETWORK_STATE` 权限，避免 `errno 13 (Permission denied)` 连接失败。

## 应用标识

| 项 | 值 |
| --- | --- |
| 安装显示名（手机桌面） | `SQLink` |
| Android applicationId | `com.jiayu.sqlinkFlutter` |
| iOS Bundle Identifier | `com.jiayu.sqlinkFlutter` |

## 从源码构建

```bash
flutter pub get
flutter run            # 调试
flutter build apk --release
flutter build ios --release --no-codesign   # 未签名 IPA（需 macOS）
```

iOS 未签名 IPA 打包（本地需 macOS）：

```bash
cd build/ios/iphoneos
mkdir -p Payload
cp -r Runner.app Payload/
zip -r SQLink-Flutter.ipa Payload
```

> 产物为**未签名** IPA，不能直接装；用 **TrollStore** 打开安装时会在设备上完成签名（CoreTrust 漏洞，永久有效，无需 Apple ID）。

## GitHub Actions 自动构建

推送到 `main` 分支即自动构建并发布（始终只有单个 `latest` 标签，每次发布覆盖上一版；更新记录见下方「更新记录」章节）：

- `ubuntu-latest` 构建 **APK**：自动注入 Android 网络权限、设置 applicationId 为 `com.jiayu.sqlinkFlutter`、显示名 `SQLink`、minSdk 23
- `macos-latest` 构建**未签名 IPA**：用 `flutter build ios --release --no-codesign` 跳过 Xcode 签名步骤（CI 无需任何 Apple 证书），仅设置 Bundle Identifier 为 `com.jiayu.sqlinkFlutter`、显示名 `SQLink`、放开 ATS 网络限制（`NSAllowsArbitraryLoads` / `NSAllowsLocalNetworking`）

产物文件名：

- Android：`SQLink-Flutter.apk`
- iOS：`SQLink-Flutter.ipa`（构建时为**未签名**状态，安装时由 TrollStore 完成签名）

> **关于 iOS 签名**：iOS 不允许运行完全无签名的 App。本流程 CI 产出的是「未签名」IPA，安装时由 **TrollStore 借助设备上的 CoreTrust 漏洞在本地完成签名**，永久有效、**不依赖 Apple ID / 开发者账号 / Mac**。这与传统「自签」（AltStore / Sideloadly 用免费 Apple ID 签名、7 天过期需重签）不同。

## 安装

- **Android**：下载 Release 中的 `SQLink-Flutter.apk`，允许「未知来源」后安装。
- **iOS**：iPhone 上用 Safari 打开 Release 页（私有仓库需登录 GitHub），点击 `SQLink-Flutter.ipa` →
  用 **TrollStore** 打开安装（仅支持兼容 TrollStore 的 iOS 版本；安装时自动完成签名，无需 Apple ID）。

## 与原 Swift 版的差异

- 不复制 Swift 版的账号 / 会员 / 后端激活体系（依赖私有后端 `sqlink-api`），本版**全功能免费开放**。
- 表数据内联编辑基于「设置筛选或排序」后就地修改，未设置筛选时仅浏览、不直接改全表数据（与原 Swift 版基于主键的整行编辑略有不同）。

## 更新记录

> 仅记录真正的代码改动（新增功能 / 修复 bug）。文档与构建流程调整不在此列。

- **2026-09-11**
  - ✨ 新增：查询控制台 SQL 自动补全增强
    - 输入框开头打字（如 `SEL`）即提示，不再空白
    - 关键词支持多词短语：输入 `OR` 提示 `ORDER BY`，`SEL` 提示 `SELECT` / `SELECT *`
    - 表名前缀 / 模糊匹配库中表（如 `lvv_c` 匹配 `lvv_user_config`、`lvv_exchange_record`）
    - 表名出现在 SQL 中即加载其字段，便于表名后直接补全字段
  - ✨ 新增：表别名 / 表名前缀字段补全（`alias.` / `table.` / `db.table.`）
    - 解析 `FROM t a`、`JOIN t b`、`FROM t1 a, t2 b` 等别名写法
    - 输入 `a.` / `b.` 即补全各自表的字段，服务于关联查询
  - 🐞 修复：点击补全时误删别名前缀（`a.` 被删成 `id`，应为 `a.id`）

- **2026-09-09**
  - ✨ 新增：数据库列表 / 表列表顶部实时搜索（对齐 Swift 版 `.searchable`）
  - 🐞 修复：新建 / 编辑连接中密码「眼睛」图标方向反了（睁眼时显示明文、闭眼时显示密文）
  - 📄 文档：README 更新为技术说明（包名、产物名、错误分类、NAT64 兼容、权限、滑动样式等）
