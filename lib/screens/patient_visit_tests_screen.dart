import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:dio/dio.dart';
// import 'package:jawda_his/screens/pdf_view_screen.dart';
// import 'package:jawda_his/screens/result_entry_screen.dart';
import 'package:path_provider/path_provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:shared_preferences/shared_preferences.dart';

class PatientVisitTestsScreen extends StatefulWidget {
  final int patientId;
  
  final String patientPhone;

  const PatientVisitTestsScreen({
    super.key,
    required this.patientId,
    
    required this.patientPhone,
  });

  @override
  State<PatientVisitTestsScreen> createState() =>
      _PatientVisitTestsScreenState();
}

class _PatientVisitTestsScreenState extends State<PatientVisitTestsScreen> {
  Map<String, dynamic> patient = {};
  List<Map<String, dynamic>> tests = [];
  List<bool> checked = [];
  bool isLoading = true;

  final Color _color1 = const Color.fromARGB(255, 215, 213, 219);
  final Color _color2 = const Color.fromARGB(255, 10, 113, 121);

  @override
  void initState() {
    super.initState();
    _fetchPatientAndTests();
  }

  String _extractErrorMessage(dynamic e) {
    if (e is DioException) {
      if (e.response != null && e.response!.data != null) {
        final data = e.response!.data;
        
        // محاولة استخراج الرسالة من حقول مختلفة
        if (data is Map) {
          // محاولة الحصول على message
          if (data['message'] != null) {
            return data['message'].toString();
          }
          // محاولة الحصول على error
          if (data['error'] != null) {
            if (data['error'] is String) {
              return data['error'];
            } else if (data['error'] is Map && data['error']['message'] != null) {
              return data['error']['message'].toString();
            }
          }
          // محاولة الحصول على errors (قائمة)
          if (data['errors'] != null) {
            if (data['errors'] is Map) {
              final errors = data['errors'] as Map;
              if (errors.isNotEmpty) {
                final firstError = errors.values.first;
                if (firstError is List && firstError.isNotEmpty) {
                  return firstError.first.toString();
                } else if (firstError is String) {
                  return firstError;
                }
              }
            }
          }
        }
        
        // إذا لم نجد رسالة واضحة، نعيد status code
        return 'خطأ ${e.response!.statusCode}: ${e.response!.statusMessage ?? 'حدث خطأ'}';
      }
      
      // إذا لم يكن هناك response، نعيد رسالة الاتصال
      return 'خطأ في الاتصال بالسيرفر: ${e.message ?? 'يرجى التحقق من الاتصال بالإنترنت'}';
    }
    
    return 'حدث خطأ غير متوقع: $e';
  }

  // جلب بيانات المريض والفحوصات
  Future<void> _fetchPatientAndTests() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    final url = 
      'https://alroomylab.a.pinggy.link/jawda-medical/public/api/visits/${widget.patientId}/lab-requests';
    

    try {
      final dio = Dio();
      dio.options.headers = {
        'Accept': 'application/json',
      };

      final response = await dio.get(url);

      if (!mounted) return;

      if (response.statusCode == 200 && response.data != null) {
        final rawData = response.data;
        final data =
            (rawData is Map && rawData.containsKey('data'))
                ? rawData['data']
                : rawData;

        if (data is List && data.isNotEmpty) {
          tests =
              data.map<Map<String, dynamic>>((item) {
                final mainTest = item['main_test'] ?? {};
                return {
                  'id': item['id'].toString(),
                  'name': mainTest['main_test_name'] ?? 'غير معروف',
                  'price': mainTest['price'] ?? 0,
                  'hidden': item['hidden'] ?? true,
                };
              }).toList();

          checked = tests.map<bool>((test) {
            return test['hidden'] == false;
          }).toList();

          final firstItem = data.first;
          patient = {
            'id': firstItem['pid'] ?? widget.patientId,
            'patient_name': firstItem['patient_name'] ?? '-',
            'created_at': firstItem['created_at'] ?? '',
            'patient_phone_for_whatsapp':
                firstItem['patient_phone_for_whatsapp'] ?? widget.patientPhone,
          };
        } else {
          tests = [];
          checked = [];
          patient = {};
        }
      } else {
        // محاولة استخراج رسالة الخطأ من response
        String errorMsg = 'حدث خطأ أثناء جلب البيانات';
        if (response.data != null && response.data is Map) {
          final responseData = response.data as Map;
          if (responseData['message'] != null) {
            errorMsg = responseData['message'].toString();
          } else if (responseData['error'] != null) {
            if (responseData['error'] is String) {
              errorMsg = responseData['error'];
            } else if (responseData['error'] is Map && responseData['error']['message'] != null) {
              errorMsg = responseData['error']['message'].toString();
            }
          } else if (responseData['errors'] != null && responseData['errors'] is Map) {
            final errors = responseData['errors'] as Map;
            if (errors.isNotEmpty) {
              final firstError = errors.values.first;
              if (firstError is List && firstError.isNotEmpty) {
                errorMsg = firstError.first.toString();
              } else if (firstError is String) {
                errorMsg = firstError;
              }
            }
          }
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errorMsg)),
          );
        }
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_extractErrorMessage(e))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ غير متوقع: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // تنسيق السعر
  String _formatPrice(dynamic value) {
    try {
      final numVal = value is num ? value : num.parse(value.toString());
      return intl.NumberFormat('#,##0').format(numVal);
    } catch (_) {
      return value.toString();
    }
  }

  // حساب المبلغ الكلي
  int get totalPrice {
    int total = 0;
    for (var t in tests) {
      final price = t['price'];
      total +=
          price is num ? price.toInt() : int.tryParse(price.toString()) ?? 0;
    }
    return total;
  }

  // تحميل PDF مؤقت
  Future<File?> _downloadPdf(String pdfUrl, String filename) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$filename');

      final dio = Dio();
      dio.options.headers = {
        'Accept': 'application/pdf',
      };

      final response = await dio.download(pdfUrl, file.path);

      if (response.statusCode == 200) return file;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل تحميل PDF: ${response.statusCode}')),
        );
      }
      return null;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ أثناء تحميل PDF: $e')));
      }
      return null;
    }
  }

  // إرسال PDF عبر واتساب باستخدام UltraMsg
  Future<void> _sendPdfToWhatsapp(String toChatId, File pdfFile) async {
    // قراءة إعدادات الواتساب من الإعدادات
    String instanceId = '';
    String token = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      instanceId = prefs.getString('whatsapp_instance_id') ?? '';
      token = prefs.getString('whatsapp_token') ?? '';
    } catch (_) {}

    if (instanceId.isEmpty || token.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('يرجى ضبط "Instance ID" و"Token" في الإعدادات'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final String ultraMsgUrl =
        'https://api.ultramsg.com/$instanceId/messages/document?token=$token';

    if (!pdfFile.existsSync()) {
      print('PDF file does not exist: ${pdfFile.path}');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('الملف غير موجود')));
      }
      return;
    }

    try {
      // تنظيف رقم الهاتف
      String phone = toChatId.trim().replaceAll(RegExp(r'\s+'), '');

      // إزالة + إن وجدت مؤقتاً للتنظيف
      phone = phone.replaceAll('+', '');
      phone = phone.replaceAll(RegExp(r'[^\d]'), '');

      // إذا كان الرقم يبدأ بـ 0، قم بإزالته
      if (phone.startsWith('0')) {
        phone = phone.substring(1);
      }

      // إضافة رمز البلد إذا لم يكن موجوداً (966 للسعودية)
      if (!phone.startsWith('966') && phone.length < 12) {
        phone = '966$phone';
      }

      // UltraMsg يتطلب رقم الهاتف مع + في البداية
      if (!phone.startsWith('+')) {
        phone = '+$phone';
      }

      print('Sending to phone: $phone');
      print('PDF file path: ${pdfFile.path}');
      print('PDF file exists: ${pdfFile.existsSync()}');
      print('PDF file size: ${await pdfFile.length()} bytes');

      // المشكلة: UltraMsg API لا يقرأ multipart/form-data بشكل صحيح
      // الحل: تجربة إرسال الملف كـ base64 مع JSON
      final dio = Dio();

      // قراءة الملف كـ bytes ثم تحويله إلى base64
      final fileBytes = await pdfFile.readAsBytes();
      final base64File = base64Encode(fileBytes);

      print('File converted to base64: ${base64File.length} characters');

      // محاولة إرسال البيانات كـ JSON مع base64
      // ملاحظة: هذا يعتمد على ما إذا كان UltraMsg API يدعم هذه الطريقة
      try {
        final response = await dio.post(
          ultraMsgUrl,
          data: {
            'to': phone,
            'filename': 'lab_result.pdf',
            'document': base64File, // إرسال كـ base64
          },
          options: Options(
            method: 'POST',
            contentType: 'application/json',
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            followRedirects: false,
            validateStatus: (status) => true,
          ),
        );

        print('UltraMsg response code (JSON method): ${response.statusCode}');
        print('UltraMsg response body (JSON method): ${response.data}');

        final responseData = response.data as Map<String, dynamic>;

        // التحقق من النجاح - إذا كان statusCode 200 وليس هناك error حقيقي
        final hasError =
            responseData.containsKey('error') && responseData['error'] != null;
        bool isRealError = false;
        if (hasError) {
          final error = responseData['error'];
          if (error is List) {
            isRealError = error.isNotEmpty;
          } else if (error is String) {
            isRealError = error.isNotEmpty;
          } else {
            isRealError = true;
          }
        }

        final hasSuccessFlag =
            responseData['sent'] == true || responseData['success'] == true;

        // إذا نجح JSON method، استخدمه
        if (response.statusCode == 200 && (hasSuccessFlag || !isRealError)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'تم إرسال النتيجة عبر واتساب',
                  textAlign: TextAlign.end,
                ),
                backgroundColor: Colors.green,
              ),
            );
          }
          return;
        }
      } catch (e) {
        print('JSON method failed: $e');
      }

      // إذا فشل JSON method، جرّب multipart مرة أخرى
      print('Trying multipart/form-data method...');
      final formData = FormData.fromMap({
        'to': phone,
        'filename': 'lab_result.pdf',
        'document': await MultipartFile.fromFile(
          pdfFile.path,
          filename: 'lab_result.pdf',
        ),
      });

      final response = await dio.post(
        ultraMsgUrl,
        data: formData,
        options: Options(
          method: 'POST',
          followRedirects: false,
          validateStatus: (status) => true,
        ),
      );

      print(
        'UltraMsg response code (multipart method): ${response.statusCode}',
      );
      print('UltraMsg response body (multipart method): ${response.data}');

      final responseData = response.data as Map<String, dynamic>;

      if (response.statusCode == 200) {
        // التحقق من وجود error في الاستجابة
        final hasError =
            responseData.containsKey('error') && responseData['error'] != null;

        // إذا كان هناك error، تحقق مما إذا كان حقيقياً أم لا
        bool isRealError = false;
        if (hasError) {
          final error = responseData['error'];
          if (error is List) {
            // إذا كانت قائمة errors غير فارغة، فهناك خطأ حقيقي
            isRealError = error.isNotEmpty;
          } else if (error is String) {
            // إذا كانت نص error، فهناك خطأ
            isRealError = error.isNotEmpty;
          } else {
            isRealError = true;
          }
        }

        // التحقق من وجود علامات النجاح
        final hasSuccessFlag =
            responseData['sent'] == true || responseData['success'] == true;

        // إذا كان هناك علامة نجاح أو لم يكن هناك error حقيقي، يعني النجاح
        final isSuccess = hasSuccessFlag || !isRealError;

        if (isSuccess) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('تم إرسال النتيجة عبر واتساب'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('فشل الإرسال: ${responseData.toString()}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('فشل الإرسال: ${response.statusCode}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      print('Error sending PDF: $e');
      print('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء الإرسال: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // نافذة إدخال رقم الهاتف وإرسال PDF
  void _showWhatsAppDialog() {
    final TextEditingController phoneController = TextEditingController(
      text: patient['patient_phone_for_whatsapp'] ?? widget.patientPhone,
    );
    bool isSending = false;

    showDialog(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (context, setState) => AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  title: const Text(
                    'إرسال النتيجة عبر واتساب',
                    textAlign: TextAlign.end,
                    style: TextStyle(fontSize: 18),
                  ),
                  content: TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    enabled: !isSending,
                    decoration: const InputDecoration(
                      labelText: 'رقم الهاتف',
                      prefixIcon: Icon(Icons.phone, color: Color(0xFF0A7179)),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed:
                          isSending ? null : () => Navigator.pop(dialogContext),
                      child: const Text('إلغاء'),
                    ),
                    ElevatedButton.icon(
                      icon:
                          isSending
                              ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                              : const Icon(Icons.send, color: Colors.white),
                      label: Text(
                        isSending ? 'جاري الإرسال...' : 'إرسال',
                        style: const TextStyle(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A7179),
                        disabledBackgroundColor: const Color(
                          0xFF0A7179,
                        ).withOpacity(0.6),
                      ),
                      onPressed:
                          isSending
                              ? null
                              : () async {
                                String phone = phoneController.text.trim();
                                print('Phone from controller: "$phone"');

                                if (phone.isEmpty) {
                                  ScaffoldMessenger.of(
                                    dialogContext,
                                  ).showSnackBar(
                                    const SnackBar(
                                      content: Text('الرجاء إدخال رقم الهاتف'),
                                    ),
                                  );
                                  return;
                                }

                                setState(() => isSending = true);

                                try {
                                  final pdfUrl = 
                                    'https://alroomylab.a.pinggy.link/jawda-medical/public/api/visits/${widget.patientId}/lab-report/pdf';
                                  

                                  print('Downloading PDF from: $pdfUrl');
                                  final pdfFile = await _downloadPdf(
                                    pdfUrl,
                                    'lab_result.pdf',
                                  );

                                  if (pdfFile != null && pdfFile.existsSync()) {
                                    print(
                                      'PDF downloaded successfully: ${pdfFile.path}',
                                    );

                                    // إغلاق dialog وإرسال الملف
                                    Navigator.pop(dialogContext);

                                    // استخدام context من الـ widget
                                    if (mounted) {
                                      await _sendPdfToWhatsapp(phone, pdfFile);
                                    }
                                  } else {
                                    setState(() => isSending = false);
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        dialogContext,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('فشل تحميل الملف'),
                                        ),
                                      );
                                    }
                                  }
                                } catch (e) {
                                  setState(() => isSending = false);
                                  if (mounted) {
                                    ScaffoldMessenger.of(
                                      dialogContext,
                                    ).showSnackBar(
                                      SnackBar(content: Text('حدث خطأ: $e')),
                                    );
                                  }
                                }
                              },
                    ),
                  ],
                ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'بيانات المريض',
            style: TextStyle(color: Colors.white),
          ),
          centerTitle: true,
          backgroundColor: const Color(0xFF0A7179),
          actions: [
            IconButton(
              icon: const FaIcon(
                FontAwesomeIcons.whatsapp,
                color: Colors.white,
              ),
              onPressed: _showWhatsAppDialog,
            ),
          ],
        ),
        body: SafeArea(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _color1,
                  _color2.withOpacity(0.2),
                  _color2.withOpacity(0.4),
                  _color2.withOpacity(0.6),
                ],
              ),
            ),
            child:
                isLoading
                    ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF0A7179),
                      ),
                    )
                    : Column(
                      children: [
                        if (patient.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 16.0,
                            ),
                            child: SizedBox(
                              width: double.infinity,
                              child: Card(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: const BorderSide(
                                    color: Color(0xFF0A7179),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                    horizontal: 12,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Text(
                                        '${patient['id']}',
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF0A7179),
                                        ),
                                      ),
                                      const SizedBox(height: 10),

                                      Text(
                                        patient['patient_name'] ?? '-',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Expanded(
                          child:
                              tests.isNotEmpty
                                  ? Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: Card(
                                      elevation: 2,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        side: const BorderSide(
                                          color: Color(0xFF0A7179),
                                        ),
                                      ),
                                      child: ListView.builder(
                                        padding: EdgeInsets.zero,
                                        itemCount: tests.length,
                                        itemBuilder: (context, i) {
                                          final t = tests[i];
                                          return InkWell(
                                            onTap: () {
                                              /*setState(
                                                () => checked[i] = !checked[i],
                                              );
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder:
                                                      (_) => ResultEntryScreen(
                                                        labRequestId: t['id'],
                                                        mainTestName: t['name'],
                                                        mainTestId:
                                                            t['id'].toString(),
                                                      ),
                                                ),
                                              );*/
                                            },
                                            child: Column(
                                              children: [
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 10,
                                                      ),
                                                  child: Row(
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          t['name'],
                                                          style: TextStyle(
                                                            fontSize: 16,
                                                            color:
                                                                checked[i]
                                                                    ? const Color(
                                                                        0xFF0A7179,
                                                                      )
                                                                    : Colors.black,
                                                            fontWeight:
                                                                checked[i]
                                                                    ? FontWeight
                                                                        .bold
                                                                    : FontWeight
                                                                        .normal,
                                                          ),
                                                        ),
                                                      ),
                                                      Checkbox(
                                                        value: checked[i],
                                                        activeColor: const Color(
                                                          0xFF0A7179,
                                                        ),
                                                        onChanged:
                                                            (val) => setState(
                                                              () =>
                                                                  checked[i] =
                                                                      val ?? false,
                                                            ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                if (i < tests.length - 1)
                                                  const Divider(
                                                    height: 1,
                                                    thickness: 1,
                                                    color: Color(0xFF0A7179),
                                                  ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  )
                                  : const Center(
                                    child: Text(
                                      'لا توجد فحوصات متاحة',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                        ),
                        if (tests.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '${_formatPrice(totalPrice)} ',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Text(
                                      ' : المبلغ الكلي',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    icon: const Icon(
                                      Icons.picture_as_pdf,
                                      color: Colors.white,
                                    ),
                                    label: const Text(
                                      'عرض النتيجة',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0A7179),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    onPressed: () async {
                                    /*  final pdfUrl = 
                                        'https://alroomylab.a.pinggy.link/jawda-medical/public/api/visits/${widget.patientId}/lab-report/pdf';
                                      
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder:
                                              (_) => PdfViewScreen(
                                                pdfUrl: pdfUrl,
                                              ),
                                        ),
                                      );*/
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
          ),
        ),
      ),
    );
  }
}
