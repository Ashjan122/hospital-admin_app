import 'package:http/http.dart' as http;
import 'dart:math';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SMSService {
  static const String _baseUrl = 'https://www.airtel.sd/api/html_send_sms/';
  static const String _username = 'jawda';
  static const String _password = 'Wda%^054J)(aDSn^';
  static const String _sender = 'Jawda';

  // Generate OTP code
  static String generateOTP() {
    Random random = Random();
    return (100000 + random.nextInt(900000)).toString(); // 6-digit OTP
  }

  // Send OTP SMS
  static Future<Map<String, dynamic>> sendOTP(String phoneNumber, String otp) async {
    try {
      print('🔍 بدء إرسال رمز التحقق...');
      print('📱 رقم الهاتف المدخل: $phoneNumber');
      print('🔐 رمز التحقق: $otp');
      
      // Format phone number (remove + and add 249 if needed)
      String formattedPhone = _formatPhoneNumber(phoneNumber);
      print('📞 رقم الهاتف المنسق: $formattedPhone');
      
      // Prepare SMS text
      String smsText = 'رمز التحقق الخاص بك هو: $otp. صالح لمدة 5 دقائق.';
      print('💬 نص الرسالة: $smsText');
      
      // Encode parameters
      String encodedText = Uri.encodeComponent(smsText);
      String encodedSender = Uri.encodeComponent(_sender);
      print('🔤 النص المشفر: $encodedText');
      print('📝 المرسل المشفر: $encodedSender');
      
      // Build URL with exact format as specified
      String url = '$_baseUrl?username=$_username&password=$_password&phone_number=$formattedPhone&message=$encodedText&sender=$encodedSender';
      
      print('🌐 رابط API: $url');
      
      // Send HTTP request
      print('📡 إرسال طلب HTTP...');
      final response = await http.get(Uri.parse(url));
      
      print('📊 رمز الاستجابة: ${response.statusCode}');
      print('📄 محتوى الاستجابة: ${response.body}');
      
      // Parse response
      Map<String, dynamic> result = {
        'success': false,
        'statusCode': response.statusCode,
        'response': response.body,
        'phoneNumber': formattedPhone,
      };
      
      // Check if SMS was sent successfully
      if (response.statusCode == 200) {
        print('✅ تم استلام استجابة 200');
        
        // Try to parse the response for additional details
        try {
          // The response might contain information about the SMS status
          if (response.body.contains('apiMsgId') || response.body.contains('Status: completed')) {
            print('✅ تم العثور على مؤشرات النجاح في الاستجابة');
            result['success'] = true;
            result['message'] = 'SMS sent successfully';
            
            // Extract apiMsgId if available
            RegExp apiMsgIdRegex = RegExp(r'apiMsgId: (\d+)');
            Match? match = apiMsgIdRegex.firstMatch(response.body);
            if (match != null) {
              result['apiMsgId'] = match.group(1);
              print('📱 معرف الرسالة: ${result['apiMsgId']}');
            }
            
            // Extract units if available
            RegExp unitsRegex = RegExp(r'units=(\d+)');
            match = unitsRegex.firstMatch(response.body);
            if (match != null) {
              result['units'] = int.parse(match.group(1)!);
              print('📊 الوحدات المستخدمة: ${result['units']}');
            }
          } else {
            print('⚠️ لم يتم العثور على مؤشرات النجاح في الاستجابة');
            result['message'] = 'SMS response received but status unclear';
          }
        } catch (e) {
          print('⚠️ خطأ في تحليل الاستجابة: $e');
          result['success'] = true; // Assume success if we can't parse but got 200
          result['message'] = 'SMS sent (response parsing failed)';
        }
      } else {
        print('❌ فشل في الاتصال: رمز الاستجابة ${response.statusCode}');
        result['message'] = 'SMS sending failed: HTTP ${response.statusCode}';
      }
      
      print('🎯 النتيجة النهائية: $result');
      return result;
    } catch (e) {
      print('❌ خطأ في إرسال SMS: $e');
      return {
        'success': false,
        'message': 'Error sending SMS: $e',
        'phoneNumber': phoneNumber,
      };
    }
  }

  // Send simple SMS (for testing)
  static Future<Map<String, dynamic>> sendSimpleSMS(String phoneNumber, String message) async {
    try {
      // Format phone number
      String formattedPhone = _formatPhoneNumber(phoneNumber);
      
      // Encode parameters
      String encodedText = Uri.encodeComponent(message);
      String encodedSender = Uri.encodeComponent(_sender);
      
      // Build URL
      String url = '$_baseUrl?username=$_username&password=$_password&phone_number=$formattedPhone&message=$encodedText&sender=$encodedSender';
      
      print('Sending SMS to: $formattedPhone');
      print('Message: $message');
      print('SMS URL: $url');
      
      // Send HTTP request
      final response = await http.get(Uri.parse(url));
      
      print('SMS Response: ${response.statusCode} - ${response.body}');
      
      // Parse response
      Map<String, dynamic> result = {
        'success': false,
        'statusCode': response.statusCode,
        'response': response.body,
        'phoneNumber': formattedPhone,
      };
      
      if (response.statusCode == 200) {
        result['success'] = true;
        result['message'] = 'SMS sent successfully';
        
        // Extract additional info if available
        if (response.body.contains('apiMsgId')) {
          RegExp apiMsgIdRegex = RegExp(r'apiMsgId: (\d+)');
          Match? match = apiMsgIdRegex.firstMatch(response.body);
          if (match != null) {
            result['apiMsgId'] = match.group(1);
          }
        }
      } else {
        result['message'] = 'SMS sending failed: HTTP ${response.statusCode}';
      }
      
      return result;
    } catch (e) {
      print('Error sending SMS: $e');
      return {
        'success': false,
        'message': 'Error sending SMS: $e',
        'phoneNumber': phoneNumber,
      };
    }
  }

  // Format phone number for SMS API
  static String _formatPhoneNumber(String phone) {
    print('🔧 تنسيق رقم الهاتف: $phone');
    
    // Remove any non-digit characters except +
    String cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    print('🧹 بعد التنظيف: $cleaned');
    
    // Remove + if present
    if (cleaned.startsWith('+')) {
      cleaned = cleaned.substring(1);
      print('➖ بعد إزالة +: $cleaned');
    }
    
    // Handle Sudanese phone numbers
    if (cleaned.startsWith('249')) {
      // Already has country code
      print('✅ الرقم يحتوي على رمز البلد بالفعل: $cleaned');
      return cleaned;
    } else if (cleaned.startsWith('0')) {
      // Remove leading 0 and add 249
      cleaned = cleaned.substring(1);
      // For Sudanese numbers, the format should be 249 + 9 digits
      if (cleaned.length == 9) {
        cleaned = '249$cleaned';
        print('🔄 بعد إزالة 0 وإضافة 249: $cleaned');
      } else if (cleaned.length == 10) {
        // If it's 10 digits, take only the last 9 digits
        cleaned = cleaned.substring(1);
        cleaned = '249$cleaned';
        print('🔄 بعد إزالة 0 وأول رقم وإضافة 249: $cleaned');
      } else {
        print('⚠️ الرقم لا يحتوي على 9 أو 10 أرقام بعد إزالة 0: $cleaned');
      }
    } else if (cleaned.length == 9) {
      // 9 digits without country code, add 249
      cleaned = '249$cleaned';
      print('➕ إضافة 249 للرقم المكون من 9 أرقام: $cleaned');
    } else {
      // Other cases, add 249 if not present
      if (!cleaned.startsWith('249')) {
        cleaned = '249$cleaned';
        print('➕ إضافة 249: $cleaned');
      }
    }
    
    print('📞 الرقم النهائي: $cleaned');
    return cleaned;
  }

  // Verify OTP
  static bool verifyOTP(String inputOTP, String storedOTP, DateTime otpCreatedAt) {
    // Check if OTP is expired (5 minutes)
    DateTime now = DateTime.now();
    Duration difference = now.difference(otpCreatedAt);
    
    if (difference.inMinutes > 5) {
      return false; // OTP expired
    }
    
    // Check if OTP matches
    return inputOTP == storedOTP;
  }

}

class NotificationService {
  static const String _notificationsKey = 'reception_notifications';

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
      final prefs = await SharedPreferences.getInstance();
      final notifications = prefs.getStringList('${_notificationsKey}_$userId') ?? [];
      
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
      
      final success = await prefs.setStringList('${_notificationsKey}_$userId', notifications);
      print('Notification saved for user $userId: ${notification['id']}, success: $success');
    } catch (e) {
      print('Error saving notification: $e');
    }
  }

  // تنظيف وتحويل البيانات القديمة إلى JSON
  static Future<void> _cleanupOldData(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final notifications = prefs.getStringList('${_notificationsKey}_$userId') ?? [];
      
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
            final cleanStr = notificationStr.replaceAll('{', '').replaceAll('}', '');
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
        await prefs.setStringList('${_notificationsKey}_$userId', cleanedNotifications);
        print('Cleaned up old data format');
      }
    } catch (e) {
      print('Error cleaning up old data: $e');
    }
  }

  // جلب الإشعارات
  static Future<List<Map<String, dynamic>>> getNotifications(String userId) async {
    try {
      // تنظيف البيانات القديمة أولاً
      await _cleanupOldData(userId);
      
      final prefs = await SharedPreferences.getInstance();
      final notifications = prefs.getStringList('${_notificationsKey}_$userId') ?? [];
      
      return notifications.map((notificationStr) {
        try {
          // محاولة تحليل كـ JSON أولاً
          final notification = jsonDecode(notificationStr) as Map<String, dynamic>;
          return notification;
        } catch (e) {
          // إذا فشل JSON، محاولة تحليل كـ String representation
          try {
            print('Trying to parse as string representation: $notificationStr');
            final cleanStr = notificationStr.replaceAll('{', '').replaceAll('}', '');
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
            
            print('Successfully parsed string representation: $notification');
            return notification;
          } catch (e2) {
            print('Error parsing notification (both methods failed): $e2');
            print('Problematic string: $notificationStr');
            return <String, dynamic>{};
          }
        }
      }).where((notification) => notification.isNotEmpty).toList();
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
      final notifications = prefs.getStringList('${_notificationsKey}_$userId') ?? [];
      
      print('Found ${notifications.length} notifications');
      
      final updatedNotifications = notifications.map((notificationStr) {
        final notification = jsonDecode(notificationStr) as Map<String, dynamic>;
        if (notification['id'] == notificationId) {
          print('Found notification to mark as read: ${notification['id']}');
          notification['isRead'] = true;
        }
        return jsonEncode(notification);
      }).toList();
      
      final success = await prefs.setStringList('${_notificationsKey}_$userId', updatedNotifications);
      print('Successfully marked notification as read: $success');
      
      // انتظار لحظة لضمان حفظ البيانات
      await Future.delayed(const Duration(milliseconds: 100));
      
      // التحقق من أن البيانات تم حفظها
      final savedNotifications = prefs.getStringList('${_notificationsKey}_$userId') ?? [];
      print('Saved notifications count: ${savedNotifications.length}');
      
      // التحقق من أن الإشعار المحدد أصبح مقروء
      for (var notificationStr in savedNotifications) {
        final notification = jsonDecode(notificationStr) as Map<String, dynamic>;
        if (notification['id'] == notificationId) {
          print('Verification: Notification ${notification['id']} isRead = ${notification['isRead']}');
          break;
        }
      }
      
      // التحقق النهائي من أن البيانات تم حفظها بشكل صحيح
      if (!success) {
        print('WARNING: Failed to save notification data!');
        // محاولة إعادة الحفظ
        final retrySuccess = await prefs.setStringList('${_notificationsKey}_$userId', updatedNotifications);
        print('Retry save success: $retrySuccess');
      }
    } catch (e) {
      print('Error marking notification as read: $e');
    }
  }

  // حذف إشعار
  static Future<void> deleteNotification(String userId, String notificationId) async {
    try {
      print('Deleting notification: $notificationId for user: $userId');
      final prefs = await SharedPreferences.getInstance();
      final notifications = prefs.getStringList('${_notificationsKey}_$userId') ?? [];
      
      print('Found ${notifications.length} notifications before deletion');
      
      final updatedNotifications = notifications.where((notificationStr) {
        final notification = jsonDecode(notificationStr) as Map<String, dynamic>;
        return notification['id'] != notificationId;
      }).toList();
      
      print('Notifications after deletion: ${updatedNotifications.length}');
      
      final success = await prefs.setStringList('${_notificationsKey}_$userId', updatedNotifications);
      print('Successfully deleted notification: $success');
      
      // انتظار لحظة لضمان حفظ البيانات
      await Future.delayed(const Duration(milliseconds: 100));
      
      // التحقق من أن البيانات تم حفظها
      final savedNotifications = prefs.getStringList('${_notificationsKey}_$userId') ?? [];
      print('Saved notifications count after deletion: ${savedNotifications.length}');
      
      // التحقق النهائي من أن البيانات تم حفظها بشكل صحيح
      if (!success) {
        print('WARNING: Failed to delete notification data!');
        // محاولة إعادة الحفظ
        final retrySuccess = await prefs.setStringList('${_notificationsKey}_$userId', updatedNotifications);
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
        print('Notification ${notification['id']}: isRead=$isRead, isUnread=$isUnread');
        return isUnread;
      }).length;
      
      print('Unread count: $unreadCount');
      
      // التحقق من صحة العد
      final verification = await getNotifications(userId);
      final verificationCount = verification.where((n) => n['isRead'] == false || n['isRead'] == 'false').length;
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
