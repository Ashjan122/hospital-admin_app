import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppUpdateService {
  static const String _configCollection = 'appConfig';
  static const String _updateKey = 'appUpdate';
  static const String _lastUpdateCheckKey = 'lastUpdateCheck';

  /// التحقق من وجود تحديث جديد
  static Future<Map<String, dynamic>?> checkForUpdate() async {
    try {
      // الحصول على معلومات التطبيق الحالي
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String currentVersion = packageInfo.version;
      
      // الحصول على آخر فحص للتحديث
      final prefs = await SharedPreferences.getInstance();
      final lastCheck = prefs.getString(_lastUpdateCheckKey);
      final now = DateTime.now().toIso8601String();
      
      // التحقق من Firestore
      final doc = await FirebaseFirestore.instance
          .collection(_configCollection)
          .doc(_updateKey)
          .get();
      
      if (!doc.exists) {
        // حفظ وقت الفحص
        await prefs.setString(_lastUpdateCheckKey, now);
        return null;
      }
      
             final updateData = doc.data()!;
      print('بيانات التحديث من Firebase: $updateData');
      
      // استخدام الأسماء الموجودة في Firestore
      final latestVersion = updateData['lastVersion'] as String?;
      final updateUrl = updateData['updatrUrl'] as String?;
      final isForceUpdate = updateData['forceUpdate'] as bool? ?? false;
      final updateMessage = updateData['message'] as String? ?? 'يتوفر تحديث جديد للتطبيق';
      final isAvailable = updateData['isAvailable'] as bool? ?? true; // افتراضي true إذا لم يكن موجود
      
      // حفظ وقت الفحص
      await prefs.setString(_lastUpdateCheckKey, now);
      
             // التحقق من وجود تحديث
       if (latestVersion == null || updateUrl == null) {
         print('معلومات التحديث غير مكتملة: version=$latestVersion, url=$updateUrl');
         return null;
       }
       
       // إذا كان isAvailable false، لا نعرض التحديث
       if (isAvailable == false) {
         print('التحديث غير متاح حالياً');
         return null;
       }
      
             // مقارنة الإصدارات
       print('مقارنة الإصدارات: الحالي=$currentVersion, الجديد=$latestVersion');
       final comparison = _compareVersions(currentVersion, latestVersion);
       print('نتيجة المقارنة: $comparison');
       
       if (comparison < 0) {
         print('يوجد تحديث جديد متاح!');
         return {
           'currentVersion': currentVersion,
           'latestVersion': latestVersion,
           'updateUrl': updateUrl,
           'isForceUpdate': isForceUpdate,
           'message': updateMessage,
           'isAvailable': true,
         };
       } else {
         print('الإصدار الحالي محدث');
       }
      
      return null;
    } catch (e) {
      print('خطأ في التحقق من التحديث: $e');
      return null;
    }
  }
  
  /// مقارنة الإصدارات
  static int _compareVersions(String current, String latest) {
    List<int> currentParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    List<int> latestParts = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    
    // جعل المصفوفات بنفس الطول
    while (currentParts.length < latestParts.length) {
      currentParts.add(0);
    }
    while (latestParts.length < currentParts.length) {
      latestParts.add(0);
    }
    
    for (int i = 0; i < currentParts.length; i++) {
      if (currentParts[i] < latestParts[i]) return -1;
      if (currentParts[i] > latestParts[i]) return 1;
    }
    
    return 0;
  }
  
  /// فتح رابط التحديث
  static Future<bool> openUpdateUrl(String url) async {
    try {
      // تأكيد أن الرابط يبدأ بـ https
      String finalUrl = url.trim();
      if (!finalUrl.startsWith('http')) {
        finalUrl = 'https://$finalUrl';
      }
      final uri = Uri.parse(finalUrl);

      // المحاولة 1: فتح بتطبيق خارجي (المتصفح)
      try {
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (ok) return true;
      } catch (_) {}

      // المحاولة 2: الوضع الافتراضي للنظام
      try {
        final ok = await launchUrl(uri, mode: LaunchMode.platformDefault);
        if (ok) return true;
      } catch (_) {}

      // المحاولة 3: داخل التطبيق (WebView/CustomTabs)
      try {
        final ok = await launchUrl(uri, mode: LaunchMode.inAppWebView);
        if (ok) return true;
      } catch (_) {}

      return false;
    } catch (e) {
      print('خطأ في فتح رابط التحديث: $e');
      return false;
    }
  }
  
  /// حفظ حالة التحديث
  static Future<void> markUpdateAsSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('updateSeen_${DateTime.now().millisecondsSinceEpoch}', true);
    } catch (e) {
      print('خطأ في حفظ حالة التحديث: $e');
    }
  }
  
  /// التحقق من عدم عرض التحديث مرة أخرى في نفس الجلسة
  static Future<bool> shouldShowUpdate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().day;
      final lastSeenDay = prefs.getInt('lastUpdateSeenDay');
      
      // إذا كان اليوم مختلف، اعرض التحديث
      if (lastSeenDay != today) {
        await prefs.setInt('lastUpdateSeenDay', today);
        return true;
      }
      
      return false;
    } catch (e) {
      print('خطأ في التحقق من عرض التحديث: $e');
      return true;
    }
  }

  /// إعادة تعيين حالة التحديث لعرضه مرة أخرى
  static Future<void> resetUpdateSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('lastUpdateSeenDay');
      print('تم إعادة تعيين حالة التحديث');
    } catch (e) {
      print('خطأ في إعادة تعيين حالة التحديث: $e');
    }
  }
}
