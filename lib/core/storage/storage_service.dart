import 'package:hive_flutter/hive_flutter.dart';

class StorageService {
  static const String _configBoxName = 'config_cache';
  static const String _configKey = 'last_known_config';

  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(_configBoxName);
  }

  static Future<void> saveConfig(Map<String, dynamic> config) async {
    final box = Hive.box(_configBoxName);
    await box.put(_configKey, config);
  }

  static Map<String, dynamic>? getLastKnownConfig() {
    final box = Hive.box(_configBoxName);
    final data = box.get(_configKey);
    if (data == null) return null;
    return Map<String, dynamic>.from(data as Map);
  }

  static Future<void> clearConfig() async {
    final box = Hive.box(_configBoxName);
    await box.delete(_configKey);
  }
}
