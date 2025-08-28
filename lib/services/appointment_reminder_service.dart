import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'sms_service.dart';

class AppointmentReminderService {
  static const String _whatsAppToken = 'df2r46jz82otkegg';
  static const String _whatsAppInstance = 'instance140877';

  // دالة للتحقق من المواعيد القادمة وإرسال التذكيرات
  static Future<void> checkAndSendReminders() async {
    try {
      final now = DateTime.now();
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      final dayAfterTomorrow = DateTime(now.year, now.month, now.day + 2);

      // جلب جميع المراكز الطبية
      final centersSnapshot = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .get();

      for (var centerDoc in centersSnapshot.docs) {
        final centerId = centerDoc.id;
        
        // جلب جميع الأطباء في المركز
        final doctorsSnapshot = await FirebaseFirestore.instance
            .collection('medicalFacilities')
            .doc(centerId)
            .collection('doctors')
            .get();

        for (var doctorDoc in doctorsSnapshot.docs) {
          final doctorId = doctorDoc.id;
          
          // جلب المواعيد المجدولة للطبيب
          final appointmentsSnapshot = await FirebaseFirestore.instance
              .collection('medicalFacilities')
              .doc(centerId)
              .collection('doctors')
              .doc(doctorId)
              .collection('scheduledAppointments')
              .where('reminderSent', isEqualTo: false)
              .where('status', isEqualTo: 'scheduled')
              .get();

          for (var appointmentDoc in appointmentsSnapshot.docs) {
            final appointmentData = appointmentDoc.data();
            final appointmentDate = DateTime.parse(appointmentData['appointmentDate']);
            
            // التحقق من أن الموعد غداً ولم يتم إرسال تذكير بعد
            if (appointmentDate.isAfter(tomorrow) && 
                appointmentDate.isBefore(dayAfterTomorrow)) {
              
              await _sendReminder(appointmentDoc.reference, appointmentData);
            }
          }
        }
      }
    } catch (e) {
      print('خطأ في فحص وإرسال التذكيرات: $e');
    }
  }

  // دالة إرسال التذكير
  static Future<void> _sendReminder(
    DocumentReference appointmentRef,
    Map<String, dynamic> appointmentData,
  ) async {
    try {
      final patientName = appointmentData['patientName'] ?? '';
      final patientPhone = appointmentData['patientPhone'] ?? '';
      final doctorName = appointmentData['doctorName'] ?? '';
      final appointmentDate = DateTime.parse(appointmentData['appointmentDate']);
      final appointmentType = appointmentData['appointmentType'] ?? 'موعد';

      // إنشاء رسالة التذكير
      final reminderMessage = _createReminderMessage(
        patientName,
        doctorName,
        appointmentDate,
        appointmentType,
      );

      bool reminderSent = false;

      // محاولة إرسال عبر واتساب أولاً
      try {
        await _sendWhatsAppReminder(patientPhone, reminderMessage);
        reminderSent = true;
        print('✅ تم إرسال تذكير واتساب للمريض: $patientName');
      } catch (e) {
        print('❌ فشل إرسال تذكير واتساب: $e');
      }

      // إذا فشل الواتساب، جرب الرسالة النصية
      if (!reminderSent) {
        try {
          final result = await SMSService.sendSimpleSMS(patientPhone, reminderMessage);
          if (result['success'] == true) {
            reminderSent = true;
            print('✅ تم إرسال تذكير SMS للمريض: $patientName');
          }
        } catch (e) {
          print('❌ فشل إرسال تذكير SMS: $e');
        }
      }

      // تحديث حالة التذكير في Firestore
      if (reminderSent) {
        await appointmentRef.update({
          'reminderSent': true,
          'reminderSentAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print('خطأ في إرسال التذكير: $e');
    }
  }

  // دالة إنشاء رسالة التذكير
  static String _createReminderMessage(
    String patientName,
    String doctorName,
    DateTime appointmentDate,
    String appointmentType,
  ) {
    final dateStr = _formatDate(appointmentDate);
    
    return '''مرحباً $patientName،
تذكير بموعدك غداً:
📅 التاريخ: $dateStr
👨‍⚕️ الطبيب: د. $doctorName
🏥 نوع الموعد: $appointmentType

يرجى الحجز.
شكراً لكم''';
  }

  // دالة إرسال تذكير واتساب
  static Future<void> _sendWhatsAppReminder(String phone, String message) async {
    try {
      var headers = {
        'Content-Type': 'application/x-www-form-urlencoded'
      };
      
      var request = http.Request(
        'POST', 
        Uri.parse('https://api.ultramsg.com/$_whatsAppInstance/messages/chat')
      );
      
      request.bodyFields = {
        'token': _whatsAppToken,
        'to': phone,
        'body': message,
      };
      request.headers.addAll(headers);

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode != 200) {
        throw Exception('WhatsApp API error: ${response.statusCode} - $responseBody');
      }

      final responseData = responseBody;
      if (!responseData.contains('"sent":"true"')) {
        throw Exception('WhatsApp message not sent: $responseData');
      }
    } catch (e) {
      throw Exception('Failed to send WhatsApp reminder: $e');
    }
  }

  // دالة تنسيق التاريخ
  static String _formatDate(DateTime date) {
    final days = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
    final months = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
    ];
    
    return '${days[date.weekday - 1]} ${date.day} ${months[date.month - 1]} ${date.year}';
  }

  // دالة تنسيق الوقت
  static String _formatTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  // دالة لجدولة فحص التذكيرات (يمكن استدعاؤها من Cloud Functions)
  static Future<void> scheduleReminderCheck() async {
    // يمكن إضافة منطق إضافي هنا للجدولة
    await checkAndSendReminders();
  }
}
