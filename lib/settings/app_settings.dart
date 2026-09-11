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
    // 上限 30 条（对齐 Swift QueryHistory.add 的 prefix(30)）。
    if (list.length > 30) list.removeRange(30, list.length);
    history = list;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setStringList('sqlHistory', list);
  }

  /// 按「数据库 + 表」记忆上次输入的 SQL（对齐 Swift 的 sqlKey 记忆）。
  /// 仅当 autoSaveSQL 开启时由页面读取/写入；全局历史始终记录（见 addHistory）。
  Future<String?> getSavedSQL(String db, String table) async {
    final p = await SharedPreferences.getInstance();
    return p.getString('sqlink.sql.${db}_${table}');
  }

  Future<void> saveSQL(String db, String table, String sql) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('sqlink.sql.${db}_${table}', sql);
  }

  /// 清空全局 SQL 历史（对齐 Swift QueryHistory.clear）。
  Future<void> clearHistory() async {
    history = [];
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.remove('sqlHistory');
  }
}
