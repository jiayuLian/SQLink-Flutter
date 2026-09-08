import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 密码等敏感信息存安全存储：iOS -> Keychain，Android -> EncryptedSharedPreferences。
class SecureStorage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _prefix = 'sqlink_pw_';

  static Future<String?> getPassword(String id) => _storage.read(key: _prefix + id);

  static Future<void> setPassword(String id, String password) =>
      _storage.write(key: _prefix + id, value: password);

  static Future<void> deletePassword(String id) =>
      _storage.delete(key: _prefix + id);
}
