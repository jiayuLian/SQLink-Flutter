import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/connections_screen.dart';
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
      home: const ConnectionsScreen(),
    );
  }
}
