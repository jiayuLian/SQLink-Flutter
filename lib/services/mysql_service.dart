import 'dart:async';
import 'dart:convert';
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
  String? _password;

  MySQLService(this.profile);

  Future<void> connect(String password) async {
    _password = password;
    // 若已有连接（理论上每个 ConnectionHomeScreen 只连一次），先关闭旧的，避免泄漏。
    if (_conn != null) {
      _conn!.close();
      _conn = null;
    }
    final hostRaw = profile.host.trim();
    if (hostRaw.isEmpty) {
      throw Exception('主机 / IP 不能为空');
    }
    if (profile.port <= 0 || profile.port > 65535) {
      throw Exception('端口无效，请输入 1-65535 之间的数字');
    }
    final user = profile.user.trim();
    if (user.isEmpty) {
      throw Exception('用户名不能为空');
    }
    // 跟随连接编辑页的 SSL 开关：开 = TLS 加密，关 = 明文连接（与 Swift 一致）。
    final useTLS = profile.useTLS;
    // 直接传字符串 host 给底层 Socket.connect。mysql_client_plus 在 host 为字符串时走
    // InternetAddress.lookup，iOS 的 NAT64 / IPv6-only 网络下会自动把 IPv4 字面量合成 IPv6
    // 去连；若强制 InternetAddress(ip, type: IPv4) 反而绕过合成，在只有 IPv6 出口的 5G /
    // 部分 WiFi 上会报 errno 65 (No route to host)。这是此前“强制 IPv4”修复在 NAT64 下的回归。
    final host = hostRaw;
    try {
      _conn = await MySQLConnection.createConnection(
        host: host,
        port: profile.port,
        userName: user,
        password: password,
        databaseName: profile.database.trim(),
        secure: useTLS,
        onBadCertificate: (_) => true,
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
    } on SocketException catch (e) {
      _conn?.close();
      _conn = null;
      final msg = e.message.toLowerCase();
      final osErr = e.osError?.message.toLowerCase() ?? '';
      final combined = '$msg $osErr';
      if (combined.contains('refused') || combined.contains('connection refused')) {
        throw Exception('连接被拒绝，请检查 IP 是否正确、端口 ${profile.port} 是否开放');
      }
      if (combined.contains('no route to host') ||
          combined.contains('network is unreachable') ||
          combined.contains('errno = 65') ||
          combined.contains('errno = 51')) {
        throw Exception('无法到达服务器 ${profile.host}:${profile.port}，请检查 IP/端口、网络或防火墙');
      }
      if (combined.contains('timed out') || combined.contains('timeout')) {
        throw Exception('连接超时，请检查主机 / 端口 / 网络是否可达');
      }
      // 兜底：保留原始信息但标注为网络错误。
      throw Exception('网络连接失败：$e');
    } on HandshakeException catch (e) {
      _conn?.close();
      _conn = null;
      throw Exception('SSL/TLS 握手失败：${e.message}，请确认服务器已开启 SSL 或关闭"使用 SSL 连接"');
    } catch (e) {
      _conn?.close();
      _conn = null;
      final msg = e.toString().toLowerCase();
      if (msg.contains('access denied') ||
          msg.contains('authentication') ||
          msg.contains('password') ||
          msg.contains('user')) {
        throw Exception('账号或密码错误，请检查用户名 / 密码');
      }
      if (msg.contains('unknown database')) {
        throw Exception('默认数据库不存在，请检查"默认数据库"填写是否正确');
      }
      if (msg.contains('handshake') || msg.contains('certificate') || msg.contains('tls')) {
        throw Exception('SSL/TLS 握手失败，请确认服务器已开启 SSL 或关闭"使用 SSL 连接"');
      }
      rethrow;
    }
  }

  /// 把 mysql_client_plus 可能返回的 Uint8List（bytes）安全解码成字符串。
  /// 某些 MySQL 版本/配置下，SHOW FULL COLUMNS / SHOW CREATE TABLE 等元数据
  /// 字段会以 List<int> 形式返回，直接 toString() 会变成 `[98,105,100]` 这种乱码。
  static String? _decodeCell(dynamic v) {
    if (v == null) return null;
    if (v is String) return v;
    if (v is List<int>) {
      try {
        return utf8.decode(v, allowMalformed: true);
      } catch (_) {
        return String.fromCharCodes(v);
      }
    }
    return v.toString();
  }

  /// 执行任意 SQL（支持多语句），返回全部结果集。
  /// 连接被服务器关闭时自动重连一次再试（对齐 Swift 的 withReconnect）。
  ///
  /// 断连检测两层兜底：
  /// 1) 直接捕获 dart:io 的 [SocketException]（iOS/Android 后台挂起+锁屏回来后，
  ///    socket 被系统/对端回收，写数据抛 broken pipe / connection reset 即此类）。
  /// 2) 兜底按错误文案关键词判断，覆盖 mysql_client_plus 可能以普通 Exception 抛出的
  ///    各种断连措辞（关键词扩到常见 iOS/驱动写法，避免漏接导致"写入数据失败"）。
  Future<List<ResultSetData>> execute(String sql) async {
    try {
      return await _executeOnce(sql);
    } on SocketException {
      if (_password != null) {
        await reconnect();
        return await _executeOnce(sql);
      }
      rethrow;
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (_password != null && _isConnectionLost(msg)) {
        await reconnect();
        return await _executeOnce(sql);
      }
      rethrow;
    }
  }

  /// 判断错误文案是否为连接断开类（用于触发重连重试）。
  static bool _isConnectionLost(String msg) {
    return msg.contains('connection closed') ||
        msg.contains('socket') ||
        msg.contains('not connected') ||
        msg.contains('write failed') ||
        msg.contains('write error') ||
        msg.contains('broken pipe') ||
        msg.contains('pipe') ||
        msg.contains('reset by peer') ||
        msg.contains('connection reset') ||
        msg.contains('os error') ||
        msg.contains('econnreset') ||
        msg.contains('epipe') ||
        msg.contains('remote host closed') ||
        msg.contains('software caused') ||
        msg.contains('closed') ||
        msg.contains('eof') ||
        msg.contains('tcp');
  }

  Future<void> reconnect() async {
    if (_password == null) throw Exception('尚未连接');
    _conn?.close();
    _conn = null;
    await connect(_password!);
  }

  Future<List<ResultSetData>> _executeOnce(String sql) async {
    final conn = _conn;
    if (conn == null) throw Exception('尚未连接');
    final List<ResultSetData> out = [];
    IResultSet? result = await conn.execute(sql);
    while (result != null) {
      if (result.cols.isNotEmpty) {
        final columns = result.cols.map((c) => c.name).toList();
        // assoc() 返回 Map<String, dynamic>，统一转成 String? 便于显示/CSV/计数。
        // 关键：把 Uint8List(bytes) 按 UTF-8 解码，避免元数据字段显示成乱码。
        final rows = result.rows.map((r) {
          final m = r.assoc();
          return m.map((k, v) => MapEntry(k, _decodeCell(v)));
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

  /// 分块拉取**全部匹配行**（带 WHERE / ORDER），用于导出全量而非当前页。
  /// 对齐 Swift 的 `exportTableStreaming` / `fetchAllRows`：边拉边追加，
  /// 每块 chunk 行；块内行数不足 chunk 即认为取完，不会死循环。
  Future<ResultSetData> fetchAllRows(
    String db,
    String table, {
    String? where,
    String? order,
    int chunk = 500,
  }) async {
    int total = 0;
    try {
      total = await countTable(db, table, where: where);
    } catch (_) {
      // 计数失败不阻断导出：以「块未取满」为终止条件。
    }
    final all = <Map<String, String?>>[];
    var columns = const <String>[];
    var offset = 0;
    // 至少拉一次，保证空表也能拿到列名（导出表头）。
    while (true) {
      final r = await fetchTable(
        db,
        table,
        limit: chunk,
        offset: offset,
        where: where,
        order: order,
      );
      if (!r.isResultSet) break;
      if (columns.isEmpty) columns = r.columns;
      all.addAll(r.rows);
      offset += r.rows.length;
      if (r.rows.length < chunk) break;
      if (total > 0 && offset >= total) break;
    }
    return ResultSetData.result(columns, all);
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
