import 'dart:io';
import 'package:mysql_client_plus/mysql_client_plus.dart';
import '../models/connection.dart';

/// 单个查询结果集（结果集或 OK 包）。
class ResultSetData {
  final List<String> columns;
  final List<Map<String, String?>> rows;
  final int affectedRows;
  final bool isResultSet;

  ResultSetData.result(this.columns, this.rows)
      : affectedRows = 0,
        isResultSet = true;
  ResultSetData.ok(this.affectedRows)
      : columns = const [],
        rows = const [],
        isResultSet = false;
}

/// 对单个 MySQL 连接的封装（基于 mysql_client_plus）。
class MySQLService {
  final ConnectionProfile profile;
  MySQLConnection? _conn;

  MySQLService(this.profile);

  Future<void> connect(String password) async {
    // 若已有连接（理论上每个 ConnectionHomeScreen 只连一次），先关闭旧的，避免泄漏。
    if (_conn != null) {
      _conn!.close();
      _conn = null;
    }
    // TLS 始终开启、自动信任自签名证书，保持与 Swift 一致。
    final useTLS = true;
    final trustSelfSigned = true;
    // 若主机是 IPv4 字面量，强制使用 IPv4 地址对象连接，避免 Dart Socket.connect
    // 在部分 iOS 网络环境下解析到 IPv6 映射地址出现 errno 65 / No route to host。
    dynamic host;
    final ipv4 = _parseIpv4(profile.host);
    if (ipv4 != null) {
      host = InternetAddress(ipv4, type: InternetAddressType.IPv4);
    } else {
      host = profile.host;
    }
    _conn = await MySQLConnection.createConnection(
      host: host,
      port: profile.port,
      userName: profile.user,
      password: password,
      databaseName: profile.database,
      secure: useTLS,
      onBadCertificate: useTLS && trustSelfSigned ? (_) => true : null,
    );
    // 对齐 Swift：底层 socket 读写超时设为 30 秒。
    await _conn!.connect().timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _conn?.close();
        _conn = null;
        throw Exception('连接超时（30 秒），请检查主机 / 端口 / 网络');
      },
    );
  }

  /// 解析纯 IPv4 字面量地址；非 IPv4 返回 null，让 Socket 走域名解析。
  static String? _parseIpv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return null;
    final nums = <int>[];
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return null;
      // 不允许前导零（如 01）。
      if (p.length > 1 && p.startsWith('0')) return null;
      nums.add(n);
    }
    return nums.join('.');
  }

  /// 执行任意 SQL（支持多语句），返回全部结果集。
  Future<List<ResultSetData>> execute(String sql) async {
    final conn = _conn;
    if (conn == null) throw Exception('尚未连接');
    final List<ResultSetData> out = [];
    IResultSet? result = await conn.execute(sql);
    while (result != null) {
      if (result.cols.isNotEmpty) {
        final columns = result.cols.map((c) => c.name).toList();
        // assoc() 返回 Map<String, dynamic>，统一转成 String? 便于显示/CSV/计数。
        final rows = result.rows.map((r) {
          final m = r.assoc();
          return m.map((k, v) => MapEntry(k, v?.toString()));
        }).toList();
        out.add(ResultSetData.result(columns, rows));
      } else {
        // affectedRows 在 mysql_client_plus 中可能为 BigInt 或 int，
        // 用 toString+parse 兼容两种类型，避免编译期不确定性。
        out.add(ResultSetData.ok(int.parse(result.affectedRows.toString())));
      }
      result = result.next;
    }
    if (out.isEmpty) out.add(ResultSetData.ok(0));
    return out;
  }

  Future<List<String>> listDatabases() async {
    final r = await execute('SHOW DATABASES');
    if (r.isEmpty || !r.first.isResultSet) return [];
    // 对齐 Swift：返回全部数据库（含 information_schema/mysql 等系统库），不做过滤。
    return r.first.rows
        .map((m) => m.values.first ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// 返回建表语句（SHOW CREATE TABLE 的第 2 列）。对齐 Swift 的 `showCreateTable`。
  Future<String> showCreateTable(String db, String table) async {
    final r = await execute(
        'SHOW CREATE TABLE `${_esc(db)}`.`${_esc(table)}`');
    if (r.isEmpty || !r.first.isResultSet) return '';
    final row = r.first.rows.firstOrNull;
    if (row == null) return '';
    // 第 0 列为表名，第 1 列为建表语句（对齐 Swift：row.count > 1 ? row[1] : ""）。
    final vals = row.values.toList();
    return vals.length > 1 ? (vals[1] ?? '') : '';
  }

  Future<List<Map<String, String>>> listTables(String db) async {
    final r = await execute('SHOW FULL TABLES FROM `${_esc(db)}`');
    if (r.isEmpty || !r.first.isResultSet) return [];
    return r.first.rows.map((m) {
      final entries = m.entries.toList();
      final name = entries.isNotEmpty ? (entries[0].value ?? '') : '';
      final type = entries.length > 1 ? (entries[1].value ?? 'BASE TABLE') : 'BASE TABLE';
      return {'name': name, 'type': type};
    }).toList();
  }

  Future<List<ColumnInfo>> listColumns(String db, String table) async {
    final r = await execute(
        'SHOW FULL COLUMNS FROM `${_esc(db)}`.`${_esc(table)}`');
    if (r.isEmpty || !r.first.isResultSet) return [];
    return r.first.rows.map((m) {
      return ColumnInfo(
        field: m['Field'] ?? '',
        type: m['Type'] ?? '',
        nullAllowed: m['Null'] ?? '',
        key: m['Key'] ?? '',
        defaultValue: m['Default'],
        extra: m['Extra'] ?? '',
        comment: m['Comment'] ?? '',
      );
    }).toList();
  }

  Future<ResultSetData> fetchTable(
    String db,
    String table, {
    int limit = 100,
    int offset = 0,
    String? where,
    String? order,
  }) async {
    var sql = 'SELECT * FROM `${_esc(db)}`.`${_esc(table)}`';
    if (where != null && where.trim().isNotEmpty) sql += ' WHERE $where';
    if (order != null && order.trim().isNotEmpty) sql += ' ORDER BY $order';
    sql += ' LIMIT $limit OFFSET $offset';
    final r = await execute(sql);
    return r.isNotEmpty ? r.first : ResultSetData.ok(0);
  }

  Future<int> countTable(String db, String table, {String? where}) async {
    var sql = 'SELECT COUNT(*) FROM `${_esc(db)}`.`${_esc(table)}`';
    if (where != null && where.trim().isNotEmpty) sql += ' WHERE $where';
    final r = await execute(sql);
    if (r.isEmpty || !r.first.isResultSet) return 0;
    final v = r.first.rows.firstOrNull?.values.first;
    return int.tryParse(v ?? '0') ?? 0;
  }

  String _esc(String s) => s.replaceAll('`', '``');

  void close() {
    _conn?.close();
    _conn = null;
  }
}
