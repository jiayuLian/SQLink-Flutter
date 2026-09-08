import 'dart:convert';

/// 连接配置（密码不在此处，单独存安全存储）。
class ConnectionProfile {
  final String id;
  String name;
  String host;
  int port;
  String user;
  String database;
  bool useTLS;
  bool trustSelfSigned;

  ConnectionProfile({
    String? id,
    this.name = '',
    this.host = '',
    this.port = 3306,
    this.user = 'root',
    this.database = '',
    this.useTLS = true,
    this.trustSelfSigned = true,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'user': user,
        'database': database,
        'useTLS': useTLS,
        'trustSelfSigned': trustSelfSigned,
      };

  factory ConnectionProfile.fromJson(Map<String, dynamic> j) => ConnectionProfile(
        id: j['id'] as String,
        name: j['name'] ?? '',
        host: j['host'] ?? '',
        port: j['port'] ?? 3306,
        user: j['user'] ?? 'root',
        database: j['database'] ?? '',
        useTLS: j['useTLS'] ?? true,
        trustSelfSigned: j['trustSelfSigned'] ?? true,
      );
}

/// 表列信息（SHOW FULL COLUMNS）。
class ColumnInfo {
  final String field;
  final String type;
  final String nullAllowed;
  final String key;
  final String? defaultValue;
  final String extra;
  final String comment;

  ColumnInfo({
    required this.field,
    required this.type,
    required this.nullAllowed,
    required this.key,
    this.defaultValue,
    required this.extra,
    required this.comment,
  });
}
