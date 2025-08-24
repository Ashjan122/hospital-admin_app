import 'package:http/http.dart' as http;
import 'dart:math';

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
