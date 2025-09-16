import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';

class AdminLabResultsScreen extends StatefulWidget {
  final String centerId;
  final String centerName;

  const AdminLabResultsScreen({
    super.key,
    required this.centerId,
    required this.centerName,
  });

  @override
  State<AdminLabResultsScreen> createState() => _AdminLabResultsScreenState();
}

class _AdminLabResultsScreenState extends State<AdminLabResultsScreen> {
  final TextEditingController _receiptController = TextEditingController();
  final FocusNode _receiptFocusNode = FocusNode();
  final FocusNode _phoneFocusNode = FocusNode();
  final TextEditingController _phoneController = TextEditingController();
  bool _isLoading = false;
  String? _currentLoadingPatientId; // تتبع العنصر الجاري تحميله
  List<Map<String, dynamic>> _patients = [];
  String? _errorMessage;
  Timer? _searchDebounce;
  int _selectedSearchMethod = 0; // 0: رقم الهاتف, 1: رقم الإيصال
  bool _isReceiptFieldFocused = false;
  bool _isPhoneFieldFocused = false;

  @override
  void initState() {
    super.initState();
    _receiptController.addListener(_onReceiptChanged);
    _receiptFocusNode.addListener(_onReceiptFocusChanged);
    _phoneFocusNode.addListener(_onPhoneFocusChanged);
  }

  @override
  void dispose() {
    _receiptController.removeListener(_onReceiptChanged);
    _receiptFocusNode.removeListener(_onReceiptFocusChanged);
    _phoneFocusNode.removeListener(_onPhoneFocusChanged);
    _receiptController.dispose();
    _receiptFocusNode.dispose();
    _phoneController.dispose();
    _phoneFocusNode.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onReceiptFocusChanged() {
    setState(() {
      _isReceiptFieldFocused = _receiptFocusNode.hasFocus;
    });
  }

  void _onReceiptChanged() {
    _searchDebounce?.cancel();
    setState(() {
      _patients = [];
      _errorMessage = null;
    });
  }

  void _onPhoneFocusChanged() {
    setState(() {
      _isPhoneFieldFocused = _phoneFocusNode.hasFocus;
    });
  }

  Future<void> _searchByPhone() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _patients = [];
    });

    try {
      // استخدم الرقم المُدخل إن وُجد، وإلا ابحث في SharedPreferences
      String? phone = _phoneController.text.trim();
      if (phone.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final keys = prefs.getKeys();
        debugPrint('Prefs keys: $keys');
        phone = prefs.getString('userPhone') ??
            prefs.getString('userEmail') ??
            prefs.getString('phone');
      }

      debugPrint('Phone from prefs: $phone');
      if (phone == null || phone.isEmpty) {
        setState(() {
          _errorMessage = 'لم يتم العثور على رقم الهاتف المسجل';
          _isLoading = false;
        });
        return;
      }

      final formattedPhone = _formatPhoneNumber(phone);
      debugPrint('Formatted phone: $formattedPhone');

      final url = 'https://alroomy.a.pinggy.link/projects/bootstraped/new/patients_api.php?phone=$formattedPhone';
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('انتهت مهلة الاتصال'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          setState(() {
            _patients = List<Map<String, dynamic>>.from(data['data']);
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = 'لم يتم العثور على مرضى بهذا الرقم';
            _patients = [];
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = 'خطأ في الاتصال بالخادم';
          _patients = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'خطأ في الاتصال: $e';
        _patients = [];
        _isLoading = false;
      });
    }
  }

  String _formatPhoneNumber(String phone) {
    String cleanPhone = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (cleanPhone.startsWith('249')) {
      cleanPhone = '0${cleanPhone.substring(3)}';
    } else if (cleanPhone.startsWith('9') && cleanPhone.length == 9) {
      cleanPhone = '0$cleanPhone';
    } else if (cleanPhone.startsWith('0')) {
      // already ok
    } else if (cleanPhone.length == 9) {
      cleanPhone = '0$cleanPhone';
    }
    return cleanPhone;
  }

  Future<void> _searchByReceipt() async {
    final receipt = _receiptController.text.trim();
    if (receipt.isEmpty) {
      setState(() {
        _errorMessage = 'يرجى إدخال رقم الإيصال';
        _patients = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _patients = [];
    });

    try {
      final url = 'https://alroomy.a.pinggy.link/projects/bootstraped/new/lab_results_api.php?patient_id=$receipt';
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('انتهت مهلة الاتصال'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final patientData = data['data'];
          final patientId = patientData['patient_id']?.toString();
          final patientName = patientData['patient_name'] ?? 'المريض';

          String displayDate = 'غير محدد';
          if (patientData['generated_at'] != null) {
            try {
              final dateTime = DateTime.parse(patientData['generated_at']);
              displayDate = '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
            } catch (e) {
              displayDate = patientData['generated_at'].toString();
            }
          }

          setState(() {
            _patients = [
              {
                'patient_id': patientId,
                'patient_name': patientName,
                'patient_date': displayDate,
                'pdf_data': patientData,
              }
            ];
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = 'لم يتم العثور على نتائج بهذا الرقم';
            _patients = [];
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = 'خطأ في الاتصال بالخادم';
          _patients = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'خطأ في الاتصال: $e';
        _patients = [];
        _isLoading = false;
      });
    }
  }

  Future<void> _viewResults(Map<String, dynamic> patient) async {
    final patientId = patient['patient_id']?.toString();
    final patientName = patient['patient_name'] ?? 'المريض';
    if (patientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('خطأ: معرف المريض غير متوفر'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    debugPrint('Patient ID: $patientId');
    debugPrint('Patient Name: $patientName');
    await _checkResultsStatus(patientId, patientName);
  }

  Future<void> _downloadAndOpenPDF(String patientName, Map<String, dynamic> apiData, [String? patientId]) async {
    try {
      debugPrint('API Data: $apiData');
      final String cleanName = patientName.replaceAll(RegExp(r'[0-9]'), '').replaceAll(' ', '_').replaceAll(RegExp(r'_+'), '_');
      final String fileName = patientId != null && patientId.isNotEmpty ? 'lab_result_$patientId.pdf' : 'نتائج_$cleanName.pdf';
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/$fileName';

      final pdfData = apiData['data'];
      PdfDocument document;

      if (pdfData != null && pdfData['pdf_base64'] != null) {
        try {
          final Uint8List pdfBytes = base64Decode(pdfData['pdf_base64']);
          document = PdfDocument(inputBytes: pdfBytes);
        } catch (e) {
          document = PdfDocument();
          final PdfPage page = document.pages.add();
          final PdfGraphics graphics = page.graphics;
          final PdfFont titleFont = PdfStandardFont(PdfFontFamily.helvetica, 20, style: PdfFontStyle.bold);
          final PdfFont normalFont = PdfStandardFont(PdfFontFamily.helvetica, 14);
          final PdfFont smallFont = PdfStandardFont(PdfFontFamily.helvetica, 12);
          final PdfBrush brush = PdfSolidBrush(PdfColor(0, 0, 0));
          graphics.drawString('نتائج المختبر', titleFont, brush: brush, bounds: const Rect.fromLTWH(50, 50, 500, 30));
          graphics.drawString('اسم المريض: $patientName', normalFont, brush: brush, bounds: const Rect.fromLTWH(50, 100, 500, 25));
          graphics.drawString('تاريخ الطباعة: ${DateTime.now().toString().split('.')[0]}', smallFont, brush: brush, bounds: const Rect.fromLTWH(50, 130, 500, 20));
          graphics.drawLine(PdfPen(PdfColor(0, 0, 0), width: 1), const Offset(50, 170), const Offset(550, 170));
          graphics.drawString('تم إنشاء هذا التقرير بناءً على طلب عرض نتائج المختبر', smallFont, brush: brush, bounds: const Rect.fromLTWH(50, 200, 500, 20));
        }
      } else {
        document = PdfDocument();
        final PdfPage page = document.pages.add();
        final PdfGraphics graphics = page.graphics;
        final PdfFont titleFont = PdfStandardFont(PdfFontFamily.helvetica, 20, style: PdfFontStyle.bold);
        final PdfFont normalFont = PdfStandardFont(PdfFontFamily.helvetica, 14);
        final PdfFont smallFont = PdfStandardFont(PdfFontFamily.helvetica, 12);
        final PdfBrush brush = PdfSolidBrush(PdfColor(0, 0, 0));
        graphics.drawString('نتائج المختبر', titleFont, brush: brush, bounds: const Rect.fromLTWH(50, 50, 500, 30));
        graphics.drawString('اسم المريض: $patientName', normalFont, brush: brush, bounds: const Rect.fromLTWH(50, 100, 500, 25));
        graphics.drawString('تاريخ الطباعة: ${DateTime.now().toString().split('.')[0]}', smallFont, brush: brush, bounds: const Rect.fromLTWH(50, 130, 500, 20));
        graphics.drawLine(PdfPen(PdfColor(0, 0, 0), width: 1), const Offset(50, 170), const Offset(550, 170));
        graphics.drawString('تم إنشاء هذا التقرير بناءً على طلب عرض نتائج المختبر', smallFont, brush: brush, bounds: const Rect.fromLTWH(50, 200, 500, 20));
      }

      final File file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
      final List<int> pdfBytes = await document.save();
      await file.writeAsBytes(pdfBytes);
      document.dispose();

      if (await file.exists()) {
        try {
          await OpenFilex.open(filePath);
        } catch (_) {}
      } else {
        throw Exception('فشل في حفظ الملف');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في فتح الملف: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _checkResultsStatus(String patientId, String patientName) async {
    try {
      setState(() {
        _isLoading = true;
        _currentLoadingPatientId = patientId;
      });

      final url = 'https://alroomy.a.pinggy.link/projects/bootstraped/new/lab_results_api.php?check_status=$patientId';
      debugPrint('Checking results status URL: $url');
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('انتهت مهلة الاتصال'),
      );

      setState(() {
        _isLoading = false;
        _currentLoadingPatientId = null;
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        bool isReady = false;
        if (data['success'] == true && data['data'] != null) {
          if (data['data']['is_ready'] != null) {
            isReady = data['data']['is_ready'] == true;
          } else if (data['data'] is String && (data['data'] as String).isNotEmpty) {
            isReady = true;
          }
        }
        if (isReady) {
          _showResultsReadyDialog(patientId, patientName, data['data']);
        } else {
          _showResultsNotReadyDialog(patientName, data['data']);
        }
      } else {
        _tryDirectResultFetch(patientId, patientName);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _currentLoadingPatientId = null;
      });
      _tryDirectResultFetch(patientId, patientName);
    }
  }

  Future<void> _tryDirectResultFetch(String patientId, String patientName) async {
    try {
      setState(() {
        _isLoading = true;
        _currentLoadingPatientId = patientId;
      });

      final url = 'https://alroomy.a.pinggy.link/projects/bootstraped/new/lab_results_api.php?patient_id=$patientId';
      debugPrint('Trying direct result fetch URL: $url');
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('انتهت مهلة الاتصال'),
      );

      setState(() {
        _isLoading = false;
        _currentLoadingPatientId = null;
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null && (data['data'] as String).isNotEmpty) {
          _showResultsReadyDialog(patientId, patientName);
        } else {
          _showResultsNotReadyDialog(patientName);
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('خطأ في الاتصال بالخادم'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _currentLoadingPatientId = null;
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في التحقق من حالة النتائج: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showResultsReadyDialog(String patientId, String patientName, [Map<String, dynamic>? statusData]) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            elevation: 8,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Text(
                        'النتيجة جاهزة',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'مرحباً $patientName،',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'نتائج المختبر الخاصة بك جاهزة. اختر ما تريد فعله:',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 45,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.of(context).pop();
                              _shareOnWhatsApp(patientId, patientName);
                            },
                            icon: const Icon(Icons.share, size: 18, color: Colors.green),
                            label: const Text(
                              'مشاركة في واتساب',
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: const BorderSide(color: Colors.green, width: 1),
                              ),
                              elevation: 1,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 45,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.of(context).pop();
                              _navigateToResultsView(patientId, patientName);
                            },
                            icon: const Icon(Icons.visibility, size: 18, color: Colors.blue),
                            label: const Text(
                              'عرض النتيجة',
                              style: TextStyle(
                                color: Colors.blue,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: const BorderSide(color: Colors.blue, width: 1),
                              ),
                              elevation: 1,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    child: const Text(
                      'إلغاء',
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showResultsNotReadyDialog(String patientName, [Map<String, dynamic>? statusData]) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            elevation: 8,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: const BoxDecoration(
                          color: Colors.orange,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.access_time,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Text(
                        'النتيجة غير جاهزة',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'مرحباً $patientName،',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'نتائج المختبر الخاصة بك لم تكتمل بعد.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 45,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.blue,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: const BorderSide(color: Colors.blue, width: 1),
                        ),
                        elevation: 1,
                      ),
                      child: const Text(
                        'حسناً',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _navigateToResultsView(String patientId, String patientName) async {
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('جاري تحميل النتيجة...'),
              ],
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }

      final url = 'https://alroomy.a.pinggy.link/projects/bootstraped/new/lab_results_api.php?patient_id=$patientId';
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw Exception('انتهت مهلة الاتصال'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          await _downloadAndOpenPDF(patientName, data, patientId);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['message'] ?? 'خطأ في تحميل النتائج'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('خطأ في الاتصال بالخادم'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحميل النتائج: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _shareOnWhatsApp(String patientId, String patientName) async {
    try {
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final String savedFilePath = '${appDocDir.path}/lab_result_$patientId.pdf';
      final File savedFile = File(savedFilePath);
      if (await savedFile.exists() && savedFile.lengthSync() > 0) {
        final String cleanName = patientName.replaceAll(RegExp(r'[0-9]'), '').replaceAll(' ', '_').replaceAll(RegExp(r'_+'), '_');
        final String fileName = 'نتائج_$cleanName.pdf';
        await Share.shareXFiles(
          [XFile(savedFile.path, name: fileName)],
          text: 'نتائج المختبر - $patientName\nرقم المريض: $patientId',
          subject: 'نتائج المختبر - $patientName',
        );
        return;
      }

      final response = await http
          .get(
            Uri.parse('https://api.romy-medical.com/api/lab-results/$patientId'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json, application/pdf',
              'User-Agent': 'HospitalApp/1.0',
            },
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final contentType = response.headers['content-type'] ?? '';
        if (contentType.contains('application/pdf')) {
          await _saveAndSharePdf(response.bodyBytes, patientId, patientName);
        } else if (contentType.contains('application/json')) {
          final jsonData = json.decode(response.body);
          String? pdfUrl;
          if (jsonData['data'] != null && jsonData['data']['pdf_url'] != null) {
            pdfUrl = jsonData['data']['pdf_url'];
          } else if (jsonData['pdf_url'] != null) {
            pdfUrl = jsonData['pdf_url'];
          } else if (jsonData['result'] != null && jsonData['result']['pdf_url'] != null) {
            pdfUrl = jsonData['result']['pdf_url'];
          }
          if (pdfUrl != null && pdfUrl.isNotEmpty) {
            await _downloadAndSharePdf(pdfUrl, patientId, patientName);
          } else {
            throw Exception('لم يتم العثور على رابط ملف PDF في الاستجابة');
          }
        } else {
          throw Exception('نوع محتوى غير متوقع: $contentType');
        }
      } else {
        throw Exception('فشل في تحميل البيانات: ${response.statusCode}');
      }
    } catch (e) {
      try {
        await _createAndShareSimplePdf(patientId, patientName);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('حدث خطأ في مشاركة الملف: ${e.toString()}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    }
  }

  Future<void> _saveAndSharePdf(Uint8List pdfBytes, String patientId, String patientName) async {
    final Directory appDocDir = await getApplicationDocumentsDirectory();
    final String cleanName = patientName.replaceAll(RegExp(r'[0-9]'), '').replaceAll(' ', '_').replaceAll(RegExp(r'_+'), '_');
    final String fileName = 'نتائج_$cleanName.pdf';
    final String filePath = '${appDocDir.path}/$fileName';
    final File file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
    await file.writeAsBytes(pdfBytes);
    if (await file.exists() && file.lengthSync() > 0) {
      await Share.shareXFiles(
        [XFile(file.path, name: fileName)],
        text: 'نتائج المختبر - $patientName\nرقم المريض: $patientId',
        subject: 'نتائج المختبر - $patientName',
      );
    } else {
      throw Exception('فشل في حفظ الملف أو الملف فارغ');
    }
  }

  Future<void> _downloadAndSharePdf(String pdfUrl, String patientId, String patientName) async {
    final pdfResponse = await http.get(Uri.parse(pdfUrl)).timeout(const Duration(seconds: 30));
    if (pdfResponse.statusCode == 200) {
      await _saveAndSharePdf(pdfResponse.bodyBytes, patientId, patientName);
    } else {
      throw Exception('فشل في تحميل ملف PDF: ${pdfResponse.statusCode}');
    }
  }

  Future<void> _createAndShareSimplePdf(String patientId, String patientName) async {
    final PdfDocument document = PdfDocument();
    final PdfPage page = document.pages.add();
    final PdfGraphics graphics = page.graphics;
    final PdfFont font = PdfStandardFont(PdfFontFamily.helvetica, 16);
    graphics.drawString('Lab Results - $patientName', font, bounds: const Rect.fromLTWH(50, 50, 500, 50));
    graphics.drawString('Patient ID: $patientId', font, bounds: const Rect.fromLTWH(50, 100, 500, 50));
    graphics.drawString('Print Date: ${DateTime.now().toString().split(' ')[0]}', font, bounds: const Rect.fromLTWH(50, 150, 500, 50));
    graphics.drawString('Note: This is a temporary file. Please contact the center for complete results.', font, bounds: const Rect.fromLTWH(50, 200, 500, 100));
    final Directory appDocDir = await getApplicationDocumentsDirectory();
    final String filePath = '${appDocDir.path}/lab_result_simple_$patientId.pdf';
    final File file = File(filePath);
    final List<int> bytes = await document.save();
    await file.writeAsBytes(bytes);
    document.dispose();
    final String cleanName = patientName.replaceAll(RegExp(r'[0-9]'), '').replaceAll(' ', '_').replaceAll(RegExp(r'_+'), '_');
    final String fileName = 'نتائج_$cleanName.pdf';
    await Share.shareXFiles(
      [XFile(file.path, name: fileName)],
      text: 'نتائج المختبر - $patientName\nرقم المريض: $patientId',
      subject: 'نتائج المختبر - $patientName',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          backgroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            "نتائج المختبر",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF2FBDAF),
              fontSize: 24,
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF2FBDAF)),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: SafeArea(
          child: Container(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // اختيار طريقة البحث
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          spreadRadius: 2,
                          blurRadius: 15,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Text(
                          'اختر طريقة البحث:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            // رقم الإيصال
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _selectedSearchMethod = 1),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: _selectedSearchMethod == 1 ? const Color(0xFF2FBDAF) : Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _selectedSearchMethod == 1 ? const Color(0xFF2FBDAF) : Colors.grey[300]!,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.receipt,
                                        color: _selectedSearchMethod == 1 ? Colors.white : Colors.grey[600],
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'رقم الإيصال',
                                        style: TextStyle(
                                          color: _selectedSearchMethod == 1 ? Colors.white : Colors.grey[600],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // رقم الهاتف
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _selectedSearchMethod = 0),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: _selectedSearchMethod == 0 ? const Color(0xFF2FBDAF) : Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _selectedSearchMethod == 0 ? const Color(0xFF2FBDAF) : Colors.grey[300]!,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.phone,
                                        color: _selectedSearchMethod == 0 ? Colors.white : Colors.grey[600],
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'رقم الهاتف',
                                        style: TextStyle(
                                          color: _selectedSearchMethod == 0 ? Colors.white : Colors.grey[600],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // إدخال البحث
                  if (_selectedSearchMethod == 1) ...[
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.1),
                            spreadRadius: 2,
                            blurRadius: 15,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(Icons.receipt, color: Colors.grey[600], size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'أدخل رقم الإيصال:',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: TextField(
                              controller: _receiptController,
                              focusNode: _receiptFocusNode,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.right,
                              textDirection: TextDirection.rtl,
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _searchByReceipt,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2FBDAF),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _isLoading
                                  ? const CircularProgressIndicator(color: Colors.white)
                                  : const Text(
                                      'البحث برقم الإيصال',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.1),
                            spreadRadius: 2,
                            blurRadius: 15,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.phone, color: Colors.grey[600], size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'أدخل رقم الهاتف:',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: TextField(
                              controller: _phoneController,
                              focusNode: _phoneFocusNode,
                              keyboardType: TextInputType.phone,
                              textAlign: TextAlign.left,
                              textDirection: TextDirection.ltr,
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _searchByPhone,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2FBDAF),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _isLoading
                                  ? const CircularProgressIndicator(color: Colors.white)
                                  : const Text(
                                      'الاستعلام عن النتيجة',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // رسالة الخطأ
                  if (_errorMessage != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red[200]!),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: Colors.red[700],
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  // النتائج
                  Expanded(
                    child: _patients.isEmpty && !_isLoading && _errorMessage == null
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (!(_selectedSearchMethod == 0 && _isPhoneFieldFocused) && !(_selectedSearchMethod == 1 && _isReceiptFieldFocused)) ...[
                                  Icon(
                                    _selectedSearchMethod == 0 ? Icons.phone : Icons.receipt,
                                    size: 64,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _selectedSearchMethod == 0
                                        ? 'اضغط على "الاستعلام عن النتيجة" للعثور على نتائج المختبر المرتبطة برقم هاتفك'
                                        : 'أدخل رقم الإيصال ثم اضغط "البحث برقم الإيصال" لعرض النتائج',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Color.fromARGB(255, 250, 152, 5),
                                      height: 1.5,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _patients.length,
                            itemBuilder: (context, index) {
                              final patient = _patients[index];
                              return _buildPatientCard(patient);
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPatientCard(Map<String, dynamic> patient) {
    final patientId = patient['patient_id']?.toString() ?? '';
    final isRowLoading = _isLoading && _currentLoadingPatientId == patientId;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    patient['patient_name'] ?? 'غير محدد',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    patient['patient_date'] ?? 'غير محدد',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: isRowLoading ? null : () => _viewResults(patient),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2FBDAF),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: isRowLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'عرض النتيجة',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
