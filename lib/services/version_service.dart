import 'package:package_info_plus/package_info_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class VersionService {
  static Future<Map<String, dynamic>?> checkVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('version')
          .get();

      if (!doc.exists) return null;

      final latestVersion = doc['latestVersion'] ?? "1.0.0";
      final minRequiredVersion = doc['minRequiredVersion'] ?? "1.0.0";
      final updateUrl = doc['updateUrl'] ?? "https://play.google.com/store/apps";

      bool forceUpdate = _isLowerVersion(currentVersion, minRequiredVersion);
      bool optionalUpdate = _isLowerVersion(currentVersion, latestVersion);

      return {
        "forceUpdate": forceUpdate,
        "optionalUpdate": optionalUpdate,
        "currentVersion": currentVersion,
        "latestVersion": latestVersion,
        "updateUrl": updateUrl,
      };
    } catch (e) {
      print("Error checking version: $e");
      return null;
    }
  }

  static bool _isLowerVersion(String current, String required) {
    List<int> currentParts = current.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    List<int> requiredParts = required.split('.').map((s) => int.tryParse(s) ?? 0).toList();

    // Pad lists to equal length
    int maxLength = currentParts.length > requiredParts.length ? currentParts.length : requiredParts.length;
    while (currentParts.length < maxLength) currentParts.add(0);
    while (requiredParts.length < maxLength) requiredParts.add(0);

    for (int i = 0; i < maxLength; i++) {
      if (currentParts[i] < requiredParts[i]) return true;
      if (currentParts[i] > requiredParts[i]) return false;
    }
    return false;
  }
}
