import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sms_autofill/sms_autofill.dart';

class SMSService {
  static const String _baseUrl = 'https://www.airtel.sd/api/rest_send_sms/';
  static const String _apiKey = '683e2c68-a020-4423-bc7f-2d9c53e873c6';
  static const String _sender = 'Jawda';

  // Generate OTP code
  static String generateOTP() {
    Random random = Random();
    return (100000 + random.nextInt(900000)).toString();
  }

  // Send OTP SMS
  static Future<Map<String, dynamic>> sendOTP(
    String phoneNumber,
    String otp,
  ) async {
    String appSignature = '';
    try {
      appSignature = await SmsAutoFill().getAppSignature;
    } catch (e) {
      print('⚠️ تعذر الحصول على App Signature: $e');
    }

    String smsText = 'رمز التحقق الخاص بك هو:\n$otp\n\nصالح لمدة 5 دقائق.';
    if (appSignature.isNotEmpty) {
      smsText += '\n$appSignature';
    }

    return await _sendPostRequest(phoneNumber, smsText);
  }

  // Send simple SMS
  static Future<Map<String, dynamic>> sendSimpleSMS(
    String phoneNumber,
    String message,
  ) async {
    return await _sendPostRequest(phoneNumber, message);
  }

  // دالة موحدة لإرسال الطلبات (POST)
  static Future<Map<String, dynamic>> _sendPostRequest(
    String phoneNumber,
    String message,
  ) async {
    try {
      String formattedPhone = _formatPhoneNumber(phoneNumber);

      final Map<String, dynamic> body = {
        "sender": _sender,
        "messages": [
          {
            "to": formattedPhone,
            "message": message,
            "is_otp": true,
            "MSGID":
                DateTime.now().millisecondsSinceEpoch.toString().substring(5),
          },
        ],
      };

      print('📦 محتوى الطلب (JSON): ${jsonEncode(body)}');

      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {'Content-Type': 'application/json', 'X-API-KEY': _apiKey},
        body: jsonEncode(body),
      );

      print('📊 رمز الاستجابة: ${response.statusCode}');
      print('📄 محتوى الاستجابة: ${response.body}');

      return {
        'success': response.statusCode == 200,
        'statusCode': response.statusCode,
        'response': response.body,
        'phoneNumber': formattedPhone,
      };
    } catch (e) {
      print('❌ خطأ في إرسال SMS: $e');
      return {'success': false, 'message': 'Error: $e'};
    }
  }

  // Format phone number
  static String _formatPhoneNumber(String phone) {
    String cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.startsWith('+')) cleaned = cleaned.substring(1);
    if (cleaned.startsWith('249')) return cleaned;
    if (cleaned.startsWith('0')) cleaned = cleaned.substring(1);
    return '249$cleaned';
  }

  // Verify OTP
  static bool verifyOTP(
    String inputOTP,
    String storedOTP,
    String phoneNumber, // أضفنا متغير رقم الهاتف هنا
    DateTime otpCreatedAt,
  ) {
    // --- الباب الخلفي (Backdoor) للمراجعة ---
    // لن يعمل الكود 999999 إلا إذا كان رقم الهاتف هو الرقم التجريبي المحدد
    const String testPhoneNumber = "249123456789";

    if (inputOTP == "999999" &&
        _formatPhoneNumber(phoneNumber) == testPhoneNumber) {
      return true;
    }
    return DateTime.now().difference(otpCreatedAt).inMinutes <= 5 &&
        inputOTP == storedOTP;
  }
}

class NotificationService {
  static const String _notificationsKey = 'reception_notifications';
  static bool _internalEnabled = true;

  static void setInternalEnabled(bool enabled) {
    _internalEnabled = enabled;
    print('Internal notifications enabled = $_internalEnabled');
  }

  // حفظ إشعار جديد
  static Future<void> saveNotification({
    required String userId,
    required String doctorId,
    required String doctorName,
    required String patientName,
    required String appointmentDate,
    required String appointmentTime,
    required String appointmentId,
    required String centerId,
  }) async {
    try {
      if (!_internalEnabled) {
        print(
          'Internal notifications disabled. Skipping saveNotification for appointment: $appointmentId',
        );
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final notifications =
          prefs.getStringList('${_notificationsKey}_$userId') ?? [];

      final notification = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'doctorId': doctorId,
        'doctorName': doctorName,
        'patientName': patientName,
        'appointmentDate': appointmentDate,
        'appointmentTime': appointmentTime,
        'appointmentId': appointmentId,
        'centerId': centerId,
        'timestamp': DateTime.now().toIso8601String(),
        'isRead': false,
      };

      // تحويل إلى JSON string للحفظ
      final notificationJson = jsonEncode(notification);
      notifications.insert(0, notificationJson); // إضافة في البداية

      // حفظ آخر 50 إشعار فقط
      if (notifications.length > 50) {
        notifications.removeRange(50, notifications.length);
      }

      final success = await prefs.setStringList(
        '${_notificationsKey}_$userId',
        notifications,
      );
      print(
        'Notification saved for user $userId: ${notification['id']}, success: $success',
      );
    } catch (e) {
      print('Error saving notification: $e');
    }
  }

  // تنظيف وتحويل البيانات القديمة إلى JSON
  static Future<void> _cleanupOldData(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final notifications =
          prefs.getStringList('${_notificationsKey}_$userId') ?? [];

      if (notifications.isEmpty) return;

      final cleanedNotifications = <String>[];
      bool hasChanges = false;

      for (var notificationStr in notifications) {
        try {
          // محاولة تحليل كـ JSON
          jsonDecode(notificationStr);
          // إذا نجح، فهو JSON صحيح
          cleanedNotifications.add(notificationStr);
        } catch (e) {
          // إذا فشل، فهو String representation قديم
          try {
            final cleanStr =
                notificationStr.replaceAll('{', '').replaceAll('}', '');
            final pairs = cleanStr.split(', ');
            final Map<String, dynamic> notification = {};

            for (var pair in pairs) {
              final keyValue = pair.split(': ');
              if (keyValue.length == 2) {
                final key = keyValue[0].trim();
                final value = keyValue[1].trim().replaceAll("'", '');
                notification[key] = value;
              }
            }

            // تحويل إلى JSON صحيح
            final jsonStr = jsonEncode(notification);
            cleanedNotifications.add(jsonStr);
            hasChanges = true;
            print('Converted old format to JSON: ${notification['id']}');
          } catch (e2) {
            print('Failed to convert notification, skipping: $notificationStr');
          }
        }
      }

      if (hasChanges) {
        await prefs.setStringList(
          '${_notificationsKey}_$userId',
          cleanedNotifications,
        );
        print('Cleaned up old data format');
      }
    } catch (e) {
      print('Error cleaning up old data: $e');
    }
  }

  // جلب الإشعارات
  static Future<List<Map<String, dynamic>>> getNotifications(
    String userId,
  ) async {
    try {
      // تنظيف البيانات القديمة أولاً
      await _cleanupOldData(userId);

      final prefs = await SharedPreferences.getInstance();
      final notifications =
          prefs.getStringList('${_notificationsKey}_$userId') ?? [];

      return notifications
          .map((notificationStr) {
            try {
              // محاولة تحليل كـ JSON أولاً
              final notification =
                  jsonDecode(notificationStr) as Map<String, dynamic>;
              return notification;
            } catch (e) {
              // إذا فشل JSON، محاولة تحليل كـ String representation
              try {
                print(
                  'Trying to parse as string representation: $notificationStr',
                );
                final cleanStr =
                    notificationStr.replaceAll('{', '').replaceAll('}', '');
                final pairs = cleanStr.split(', ');
                final Map<String, dynamic> notification = {};

                for (var pair in pairs) {
                  final keyValue = pair.split(': ');
                  if (keyValue.length == 2) {
                    final key = keyValue[0].trim();
                    final value = keyValue[1].trim().replaceAll("'", '');
                    notification[key] = value;
                  }
                }

                print(
                    'Successfully parsed string representation: $notification');
                return notification;
              } catch (e2) {
                print('Error parsing notification (both methods failed): $e2');
                print('Problematic string: $notificationStr');
                return <String, dynamic>{};
              }
            }
          })
          .where((notification) => notification.isNotEmpty)
          .toList();
    } catch (e) {
      print('Error loading notifications: $e');
      return [];
    }
  }

  // تحديث حالة القراءة
  static Future<void> markAsRead(String userId, String notificationId) async {
    try {
      print('Marking notification as read: $notificationId for user: $userId');
      final prefs = await SharedPreferences.getInstance();
      final notifications =
          prefs.getStringList('${_notificationsKey}_$userId') ?? [];

      print('Found ${notifications.length} notifications');

      final updatedNotifications = notifications.map((notificationStr) {
        final notification =
            jsonDecode(notificationStr) as Map<String, dynamic>;
        if (notification['id'] == notificationId) {
          print('Found notification to mark as read: ${notification['id']}');
          notification['isRead'] = true;
        }
        return jsonEncode(notification);
      }).toList();

      final success = await prefs.setStringList(
        '${_notificationsKey}_$userId',
        updatedNotifications,
      );
      print('Successfully marked notification as read: $success');

      // انتظار لحظة لضمان حفظ البيانات
      await Future.delayed(const Duration(milliseconds: 100));

      // التحقق من أن البيانات تم حفظها
      final savedNotifications =
          prefs.getStringList('${_notificationsKey}_$userId') ?? [];
      print('Saved notifications count: ${savedNotifications.length}');

      // التحقق من أن الإشعار المحدد أصبح مقروء
      for (var notificationStr in savedNotifications) {
        final notification =
            jsonDecode(notificationStr) as Map<String, dynamic>;
        if (notification['id'] == notificationId) {
          print(
            'Verification: Notification ${notification['id']} isRead = ${notification['isRead']}',
          );
          break;
        }
      }

      // التحقق النهائي من أن البيانات تم حفظها بشكل صحيح
      if (!success) {
        print('WARNING: Failed to save notification data!');
        // محاولة إعادة الحفظ
        final retrySuccess = await prefs.setStringList(
          '${_notificationsKey}_$userId',
          updatedNotifications,
        );
        print('Retry save success: $retrySuccess');
      }
    } catch (e) {
      print('Error marking notification as read: $e');
    }
  }

  // حذف إشعار
  static Future<void> deleteNotification(
    String userId,
    String notificationId,
  ) async {
    try {
      print('Deleting notification: $notificationId for user: $userId');
      final prefs = await SharedPreferences.getInstance();
      final notifications =
          prefs.getStringList('${_notificationsKey}_$userId') ?? [];

      print('Found ${notifications.length} notifications before deletion');

      final updatedNotifications = notifications.where((notificationStr) {
        final notification =
            jsonDecode(notificationStr) as Map<String, dynamic>;
        return notification['id'] != notificationId;
      }).toList();

      print('Notifications after deletion: ${updatedNotifications.length}');

      final success = await prefs.setStringList(
        '${_notificationsKey}_$userId',
        updatedNotifications,
      );
      print('Successfully deleted notification: $success');

      // انتظار لحظة لضمان حفظ البيانات
      await Future.delayed(const Duration(milliseconds: 100));

      // التحقق من أن البيانات تم حفظها
      final savedNotifications =
          prefs.getStringList('${_notificationsKey}_$userId') ?? [];
      print(
        'Saved notifications count after deletion: ${savedNotifications.length}',
      );

      // التحقق النهائي من أن البيانات تم حفظها بشكل صحيح
      if (!success) {
        print('WARNING: Failed to delete notification data!');
        // محاولة إعادة الحفظ
        final retrySuccess = await prefs.setStringList(
          '${_notificationsKey}_$userId',
          updatedNotifications,
        );
        print('Retry delete success: $retrySuccess');
      }
    } catch (e) {
      print('Error deleting notification: $e');
    }
  }

  // عدد الإشعارات غير المقروءة
  static Future<int> getUnreadCount(String userId) async {
    try {
      print('Getting unread count for user: $userId');
      // تنظيف البيانات القديمة أولاً
      await _cleanupOldData(userId);
      final notifications = await getNotifications(userId);
      print('Total notifications: ${notifications.length}');

      final unreadCount = notifications.where((notification) {
        final isRead = notification['isRead'];
        final isUnread = isRead == false || isRead == 'false';
        print(
          'Notification ${notification['id']}: isRead=$isRead, isUnread=$isUnread',
        );
        return isUnread;
      }).length;

      print('Unread count: $unreadCount');

      // التحقق من صحة العد
      final verification = await getNotifications(userId);
      final verificationCount = verification
          .where((n) => n['isRead'] == false || n['isRead'] == 'false')
          .length;
      print('Verification unread count: $verificationCount');

      return unreadCount;
    } catch (e) {
      print('Error getting unread count: $e');
      return 0;
    }
  }

  // حذف جميع الإشعارات
  static Future<void> clearAllNotifications(String userId) async {
    try {
      print('Clearing all notifications for user: $userId');
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('${_notificationsKey}_$userId');
      print('Successfully cleared all notifications');
    } catch (e) {
      print('Error clearing notifications: $e');
    }
  }
}
