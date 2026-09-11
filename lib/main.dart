import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/connections_screen.dart';
import 'screens/profile_screen.dart';
import 'services/connection_store.dart';
import 'services/update_service.dart';
import 'settings/app_settings.dart';
import 'widgets/update_dialog.dart';

/// iOS 系统蓝，对齐 SwiftUI 默认 `.accentColor`（Swift 版 SQLink 的强调色来源）。
const _iosBlue = Color(0xFF007AFF);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = ConnectionStore();
  await store.load();
  final settings = AppSettings();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: store),
        ChangeNotifierProvider.value(value: settings),
      ],
      child: const MyApp(),
    ),
  );
}

/// 按亮度构造主题：配色与版式对齐 Swift 版
/// （系统蓝强调色 / iOS 分组列表底色 / 居中导航标题）。
ThemeData _buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _iosBlue,
      brightness: brightness,
    ),
    // SwiftUI 分组列表底色：浅色 systemGroupedBackground(#F2F2F7)，深色纯黑；
    // 卡片浮在其上，观感与 iOS insetGrouped 列表一致。
    scaffoldBackgroundColor:
        isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
    // Swift 的导航标题为居中 inline 样式。
    appBarTheme: const AppBarTheme(centerTitle: true),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static final ThemeData _light = _buildTheme(Brightness.light);
  static final ThemeData _dark = _buildTheme(Brightness.dark);

  @override
  Widget build(BuildContext context) {
    // 只订阅主题：SQL 历史 / 每页条数等设置变化不再触发整个 App 重建。
    final themeMode =
        context.select<AppSettings, ThemeMode>((s) => s.themeMode);
    return MaterialApp(
      title: 'SQLink',
      theme: _light,
      darkTheme: _dark,
      themeMode: themeMode,
      home: const RootTabs(),
    );
  }
}

/// 根容器：底部两个标签「数据库 / 我的」（对齐 Swift SQLinkApp 的 TabView）。
/// 「数据库」= 连接列表；「我的」= 外观 / 查询设置 / 关于（无账号体系）。
class RootTabs extends StatefulWidget {
  const RootTabs({super.key});

  @override
  State<RootTabs> createState() => _RootTabsState();
}

class _RootTabsState extends State<RootTabs> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // 启动后静默检查更新：放在首帧之后，不阻塞启动。
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoCheckUpdate());
  }

  /// 启动时的静默更新检查。
  /// 每天最多查一次；只在确实有新版本、且该版本还没提示过时才弹窗，
  /// 失败（没网 / GitHub 不通）完全不打扰用户，并且不记「已检查」日期，
  /// 这样下次启动会再试一次。
  Future<void> _autoCheckUpdate() async {
    if (!await UpdateService.shouldAutoCheck()) return;
    final result = await UpdateService.check();
    if (result.status == UpdateStatus.failed) return;
    await UpdateService.markChecked();
    final info = result.info;
    if (result.status != UpdateStatus.available || info == null) return;
    if (await UpdateService.alreadyNotified(info.latestLabel)) return;
    await UpdateService.markNotified(info.latestLabel);
    if (!mounted) return;
    await showUpdateDialog(context, info);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          ConnectionsScreen(),
          ProfileScreen(),
        ],
      ),
      // 用平铺标签栏（对齐 iOS UITabBar）：图标 + 文字、选中态为主题色，
      // 不使用 Material 3 NavigationBar 的圆角指示药丸。
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        type: BottomNavigationBarType.fixed,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dns_outlined),
            activeIcon: Icon(Icons.dns),
            label: '数据库',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
