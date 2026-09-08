# SQLink (Flutter)

远程 MySQL 客户端，使用 Flutter 重写，一套代码同时出 **Android (APK)** 与 **iOS (IPA)**。

> 与原 Swift 版 `jiayuLian/SQLink` 并存、互不干扰。Swift 版保留不动。
> 本 Flutter 版为**纯本地客户端**：连接密码仅存本机（iOS Keychain / Android 加密存储），不依赖任何后端服务。

## 功能

- 多连接管理（名称 / 主机 / 端口 / 用户 / 默认库 / 密码 / TLS / 自签信任）
- 密码安全存储：iOS Keychain、Android EncryptedSharedPreferences
- 库表浏览：数据库 → 表/视图 → 列（类型、键、NOT NULL）
- 表数据浏览：分页、排序、WHERE 筛选、行数统计、CSV 导出
- 查询控制台：任意 SQL、多语句结果集、SQL 历史、关键字自动补全、CSV 导出
- TLS 加密连接，支持自签名证书信任（`onBadCertificate`）
- 支持 `mysql_native_password` 与 `caching_sha2_password`（MySQL 8 默认）

## 从源码构建

```bash
flutter pub get
flutter run            # 调试
flutter build apk --release
flutter build ios --release --no-codesign   # 免签 IPA（需 macOS）
```

iOS 免签 IPA 打包：

```bash
cd build/ios/iphoneos
mkdir -p Payload
cp -r Runner.app Payload/
zip -r SQLink.ipa Payload
```

## GitHub Actions 自动构建

推送到 `main` 分支即自动：

- `ubuntu-latest` 构建 **APK**（`app-release.apk`）
- `macos-latest` 构建**免签名 IPA**（`SQLink.ipa`，对应 Swift 版 TrollStore 方案）
- 合并发布到 GitHub Release（标签 `v<run_number>`）

无需任何 Apple 证书 / secret；iOS IPA 通过 TrollStore 安装。

## 安装

- **Android**：下载 Release 中的 `app-release.apk`，允许「未知来源」后安装。
- **iOS**：iPhone 上用 Safari 打开 Release 页（私有仓库需登录 GitHub），点击 `SQLink.ipa` →
  用 **TrollStore** 打开安装（仅支持兼容 TrollStore 的 iOS 版本）。

## 与原 Swift 版的差异

- 不复制 Swift 版的账号 / 会员 / 后端激活体系（依赖私有后端 `sqlink-api`）。
- 暂未实现基于主键的「结果内行编辑」，后续可补。
