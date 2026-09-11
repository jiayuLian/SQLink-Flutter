import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/connections_screen.dart';
import 'screens/profile_screen.dart';
import 'services/connection_store.dart';
import 'settings/app_settings.dart';

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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettings>(context);
    return MaterialApp(
      title: 'SQLink',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      themeMode: settings.themeMode,
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
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          ConnectionsScreen(),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dns_outlined),
            selectedIcon: Icon(Icons.dns),
            label: '数据库',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
