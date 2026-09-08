import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全局设置：主题、自动保存 SQL、每页条数、SQL 历史。
class AppSettings extends ChangeNotifier {
  ThemeMode themeMode;
  bool autoSaveSQL;
  int pageSize;
  List<String> history;

  AppSettings({
    this.themeMode = ThemeMode.system,
    this.autoSaveSQL = true,
    this.pageSize = 100,
    this.history = const [],
  }) {
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final t = p.getInt('themeMode');
    if (t != null && t < ThemeMode.values.length) themeMode = ThemeMode.values[t];
    autoSaveSQL = p.getBool('autoSaveSQL') ?? true;
    pageSize = p.getInt('pageSize') ?? 100;
    history = p.getStringList('sqlHistory') ?? [];
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode m) async {
    themeMode = m;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setInt('themeMode', m.index);
  }

  Future<void> setAutoSave(bool v) async {
    autoSaveSQL = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool('autoSaveSQL', v);
  }

  Future<void> setPageSize(int v) async {
    pageSize = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setInt('pageSize', v);
  }

  Future<void> addHistory(String sql) async {
    final s = sql.trim();
    if (s.isEmpty) return;
    final list = List<String>.from(history);
    list.remove(s);
    list.insert(0, s);
    if (list.length > 50) list.removeRange(50, list.length);
    history = list;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setStringList('sqlHistory', list);
  }
}
