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
    final out = <ConnectionProfile>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final e in decoded) {
          // 逐条容错：单条记录损坏（如缺 id/字段类型不符）只跳过该条，
          // 不再让一条坏数据把整个连接列表清空。
          try {
            if (e is Map<String, dynamic>) {
              out.add(ConnectionProfile.fromJson(e));
            }
          } catch (_) {
            continue;
          }
        }
      }
    } catch (_) {
      // 整段 JSON 损坏时保持空列表。
    }
    _connections = out;
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
