import 'dart:convert';

import 'package:http/http.dart' as http;

class WhatsAppService {
  static const String phoneNumberId = '1276228115582754';
  static const String accessToken =
      'EAAapSj9k2sABRIVNLKtomho0lxjbXkH9JXm1Asgzosmz0x3nsOAlDdzRauNcJOgYNwUfXzRz5xCetT0SqgKZAeJZAD2h92NaUnrXWDOiFyjdZAaStoF1d36EPgwzAxZC6UmihhYyGZCyx2JdlDIBvpl2JTTvNFdTPYi215N0GiS2XhmoHULg9F6WK6iwd7ZBklXgZDZD';

  static Future<void> sendBookingTemplate({
    required String phoneNumber,
    required String facilityName,
    required String patientName,
    required String doctorName,
    required String specializationName,
    required String dayName,
    required String date,
    required String period,
    required String patientPhone,
    required String centerPhone,
  }) async {
    final url = Uri.parse(
      'https://graph.facebook.com/v22.0/$phoneNumberId/messages',
    );

    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'messaging_product': 'whatsapp',
        'to': phoneNumber,
        'type': 'template',
        'template': {
          'name': 'booking_message',
          'language': {'code': 'ar'},
          'components': [
            {
              'type': 'body',
              'parameters': [
                {'type': 'text', 'text': facilityName},
                {'type': 'text', 'text': patientName},
                {'type': 'text', 'text': patientPhone},
                {'type': 'text', 'text': doctorName},
                {'type': 'text', 'text': specializationName},
                {'type': 'text', 'text': dayName},
                {'type': 'text', 'text': date},
                {'type': 'text', 'text': period},
                {'type': 'text', 'text': centerPhone},
              ],
            },
          ],
        },
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('فشل إرسال رسالة WhatsApp: ${response.body}');
    }
  }

  static Future<void> sendCancelBookingTemplate({
    required String phoneNumber,
    required String patientName,
    required String doctorName,
    required String date,
    required String period,
    required String centerPhone,
  }) async {
    final url = Uri.parse(
      'https://graph.facebook.com/v22.0/$phoneNumberId/messages',
    );

    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'messaging_product': 'whatsapp',
        'to': phoneNumber,
        'type': 'template',
        'template': {
          'name': 'cancel_booking',
          'language': {'code': 'ar'},
          'components': [
            {
              'type': 'body',
              'parameters': [
                {'type': 'text', 'text': patientName},
                {'type': 'text', 'text': doctorName},
                {'type': 'text', 'text': date},
                {'type': 'text', 'text': period},
                {'type': 'text', 'text': centerPhone},
              ],
            },
          ],
        },
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('فشل إرسال رسالة إلغاء WhatsApp: ${response.body}');
    }
  }
}
