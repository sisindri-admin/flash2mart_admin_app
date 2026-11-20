class ParseUtils {
  static double toDouble(dynamic val, [double defaultVal = 0.0]) {
    if (val == null) return defaultVal;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? defaultVal;
    return defaultVal;
  }

  static int toInt(dynamic val, [int defaultVal = 0]) {
    if (val == null) return defaultVal;
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val) ?? defaultVal;
    return defaultVal;
  }

  static bool toBool(dynamic val, [bool defaultVal = false]) {
    if (val == null) return defaultVal;
    if (val is bool) return val;
    if (val is String) {
      final s = val.trim().toLowerCase();
      return s == 'true' || s == '1' || s == 'yes';
    }
    if (val is num) return val == 1;
    return defaultVal;
  }

  static String toStr(dynamic val, [String defaultVal = '']) {
    if (val == null) return defaultVal;
    return val.toString();
  }
}
