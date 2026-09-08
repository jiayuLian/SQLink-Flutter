import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/connection.dart';

/// 连接配置列表（不含密码）持久化到 SharedPreferences。
class ConnectionStore extends ChangeNotifier {
  List<ConnectionProfile> _connections = [];

  List<ConnectionProfile> get connections => List.unmodifiable(_connections);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('connections') ?? '[]';
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => ConnectionProfile.fromJson(e as Map<String, dynamic>))
          .toList();
      _connections = list;
    } catch (_) {
      _connections = [];
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'connections',
      jsonEncode(_connections.map((c) => c.toJson()).toList()),
    );
  }

  Future<void> upsert(ConnectionProfile c) async {
    final i = _connections.indexWhere((x) => x.id == c.id);
    if (i >= 0) {
      _connections[i] = c;
    } else {
      _connections.add(c);
    }
    await _persist();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _connections.removeWhere((x) => x.id == id);
    await _persist();
    notifyListeners();
  }
}
