import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

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
  String? _currentLoadingPatientId;

  List<Map<String, dynamic>> _patients = [];

  String? _errorMessage;

  Timer? _searchDebounce;

  int _selectedSearchMethod = 0; // 0: رقم الهاتف, 1: رقم الإيصال

  bool _isReceiptFieldFocused = false;
  bool _isPhoneFieldFocused = false;

  String? _targetCollection;
  bool _isLoadingCollection = true;

  /// Firestore الخاص بالمشروع الثاني
  late final FirebaseFirestore _secondaryFirestore;

  @override
  void initState() {
    super.initState();

    _secondaryFirestore = FirebaseFirestore.instanceFor(
      app: Firebase.app('secondaryApp'),
    );

    _receiptController.addListener(_onReceiptChanged);
    _receiptFocusNode.addListener(_onReceiptFocusChanged);
    _phoneFocusNode.addListener(_onPhoneFocusChanged);

    _loadTargetCollection();
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

  /// جلب اسم Collection الخاصة بالمركز من Firebase الأساسي
  Future<void> _loadTargetCollection() async {
    try {
      final centerDoc =
          await FirebaseFirestore.instance
              .collection('medicalFacilities')
              .doc(widget.centerId)
              .get();

      if (!centerDoc.exists || centerDoc.data() == null) {
        setState(() {
          _targetCollection = null;
          _isLoadingCollection = false;
          _errorMessage = 'لم يتم العثور على بيانات المركز';
        });
        return;
      }

      final data = centerDoc.data()!;

      final targetCollection =
          data['targetCollection']?.toString().trim() ?? '';

      if (targetCollection.isEmpty) {
        setState(() {
          _targetCollection = null;
          _isLoadingCollection = false;
          _errorMessage = 'لم يتم تحديد Collection الخاصة بنتائج المختبر';
        });
        return;
      }

      debugPrint('Target collection: $targetCollection');

      setState(() {
        _targetCollection = targetCollection;
        _isLoadingCollection = false;
      });
    } catch (e) {
      debugPrint('Error loading target collection: $e');

      if (!mounted) return;

      setState(() {
        _targetCollection = null;
        _isLoadingCollection = false;
        _errorMessage = 'حدث خطأ في تحميل إعدادات نتائج المختبر';
      });
    }
  }

  void _onReceiptFocusChanged() {
    if (!mounted) return;

    setState(() {
      _isReceiptFieldFocused = _receiptFocusNode.hasFocus;
    });
  }

  void _onReceiptChanged() {
    _searchDebounce?.cancel();

    if (!mounted) return;

    setState(() {
      _patients = [];
      _errorMessage = null;
    });
  }

  void _onPhoneFocusChanged() {
    if (!mounted) return;

    setState(() {
      _isPhoneFieldFocused = _phoneFocusNode.hasFocus;
    });
  }

  // ============================================================
  // البحث برقم الهاتف
  // ============================================================

  Future<void> _searchByPhone() async {
    final phone = _phoneController.text.trim();

    if (phone.isEmpty) {
      setState(() {
        _errorMessage = 'يرجى إدخال رقم الهاتف';
        _patients = [];
      });
      return;
    }

    if (_targetCollection == null || _targetCollection!.isEmpty) {
      setState(() {
        _errorMessage = 'لم يتم إعداد نتائج المختبر لهذا المركز';
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
      final phoneFormats = _getPhoneFormats(phone);

      debugPrint('Searching phone formats: $phoneFormats');
      debugPrint('Collection: $_targetCollection');

      final Map<String, Map<String, dynamic>> uniquePatients = {};

      for (final phoneFormat in phoneFormats) {
        try {
          final snapshot =
              await _secondaryFirestore
                  .collection(_targetCollection!)
                  .where('patient_phone', isEqualTo: phoneFormat)
                  .get();

          for (final doc in snapshot.docs) {
            final data = doc.data();

            final patientId = doc.id;

            final patientName =
                data['patient_name']?.toString() ?? 'المريض';

            final patientPhone =
                data['patient_phone']?.toString() ?? phoneFormat;

            final displayDate = _getDisplayDate(data);

            uniquePatients[patientId] = {
              'patient_id': patientId,
              'patient_name': patientName,
              'patient_phone': patientPhone,
              'patient_date': displayDate,
              'pdf_data': data,
              'result_url': data['result_url']?.toString(),
              'receipt_id':
                  data['receipt_id']?.toString() ??
                  data['receipt']?.toString() ??
                  doc.id,
            };
          }
        } catch (e) {
          debugPrint(
            'Error searching phone format $phoneFormat: $e',
          );
        }
      }

      if (!mounted) return;

      if (uniquePatients.isNotEmpty) {
        final patients = uniquePatients.values.toList();

        patients.sort((a, b) {
          final dateA = _parseDate(a['patient_date']);
          final dateB = _parseDate(b['patient_date']);

          return dateB.compareTo(dateA);
        });

        setState(() {
          _patients = patients;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'لم يتم العثور على نتائج بهذا الرقم';
          _patients = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Phone search error: $e');

      if (!mounted) return;

      setState(() {
        _errorMessage = 'حدث خطأ أثناء البحث عن النتائج';
        _patients = [];
        _isLoading = false;
      });
    }
  }

  /// إنشاء جميع صيغ رقم الهاتف المحتملة
  List<String> _getPhoneFormats(String phone) {
    String cleanPhone = phone.replaceAll(RegExp(r'[^\d]'), '');

    final Set<String> formats = {};

    if (cleanPhone.startsWith('249')) {
      final local = cleanPhone.substring(3);

      formats.add('0$local');
      formats.add('249$local');
      formats.add(local);
    } else if (cleanPhone.startsWith('0') && cleanPhone.length >= 10) {
      final local = cleanPhone.substring(1);

      formats.add(cleanPhone);
      formats.add('249$local');
      formats.add(local);
    } else if (cleanPhone.startsWith('9') && cleanPhone.length == 9) {
      formats.add('0$cleanPhone');
      formats.add('249$cleanPhone');
      formats.add(cleanPhone);
    } else if (cleanPhone.length == 9) {
      formats.add('0$cleanPhone');
      formats.add('249$cleanPhone');
      formats.add(cleanPhone);
    } else {
      formats.add(cleanPhone);
    }

    return formats.toList();
  }

  // ============================================================
  // البحث برقم الإيصال
  // ============================================================

  Future<void> _searchByReceipt() async {
    final receipt = _receiptController.text.trim();

    if (receipt.isEmpty) {
      setState(() {
        _errorMessage = 'يرجى إدخال رقم الإيصال';
        _patients = [];
      });
      return;
    }

    if (_targetCollection == null || _targetCollection!.isEmpty) {
      setState(() {
        _errorMessage = 'لم يتم إعداد نتائج المختبر لهذا المركز';
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
      debugPrint('Searching receipt: $receipt');
      debugPrint('Collection: $_targetCollection');

      /// في نظام نتائج المختبر رقم الإيصال هو ID للمستند
      final doc =
          await _secondaryFirestore
              .collection(_targetCollection!)
              .doc(receipt)
              .get();

      if (!doc.exists || doc.data() == null) {
        if (!mounted) return;

        setState(() {
          _errorMessage = 'لم يتم العثور على نتائج بهذا الرقم';
          _patients = [];
          _isLoading = false;
        });

        return;
      }

      final data = doc.data()!;

      final patientId =
          data['patient_id']?.toString() ??
          data['patientId']?.toString() ??
          doc.id;

      final patientName =
          data['patient_name']?.toString() ?? 'المريض';

      final patientPhone =
          data['patient_phone']?.toString() ?? '';

      final displayDate = _getDisplayDate(data);

      final patient = {
        'patient_id': patientId,
        'patient_name': patientName,
        'patient_phone': patientPhone,
        'patient_date': displayDate,
        'pdf_data': data,
        'result_url': data['result_url']?.toString(),
        'receipt_id': doc.id,
      };

      if (!mounted) return;

      setState(() {
        _patients = [patient];
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Receipt search error: $e');

      if (!mounted) return;

      setState(() {
        _errorMessage = 'حدث خطأ أثناء البحث عن النتيجة';
        _patients = [];
        _isLoading = false;
      });
    }
  }

  // ============================================================
  // التاريخ
  // ============================================================

  String _getDisplayDate(Map<String, dynamic> data) {
    dynamic value =
        data['created_at'] ??
        data['updated_at'] ??
        data['generated_at'];

    if (value == null) {
      return 'غير محدد';
    }

    try {
      DateTime? dateTime;

      if (value is Timestamp) {
        dateTime = value.toDate();
      } else if (value is DateTime) {
        dateTime = value;
      } else {
        dateTime = DateTime.tryParse(value.toString());
      }

      if (dateTime == null) {
        return value.toString();
      }

      return '${dateTime.year}-'
          '${dateTime.month.toString().padLeft(2, '0')}-'
          '${dateTime.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return value.toString();
    }
  }

  DateTime _parseDate(dynamic value) {
    if (value == null) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    return DateTime.tryParse(value.toString()) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  // ============================================================
  // عرض النتيجة
  // ============================================================

  Future<void> _viewResults(Map<String, dynamic> patient) async {
    final patientId = patient['patient_id']?.toString();
    final patientName =
        patient['patient_name']?.toString() ?? 'المريض';

    if (patientId == null || patientId.isEmpty) {
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

    await _checkResultsStatus(
      patientId,
      patientName,
      patient,
    );
  }

  // ============================================================
  // التحقق من جاهزية النتيجة
  // ============================================================

  Future<void> _checkResultsStatus(
    String patientId,
    String patientName,
    Map<String, dynamic> patient,
  ) async {
    try {
      setState(() {
        _isLoading = true;
        _currentLoadingPatientId = patientId;
      });

      final data =
          patient['pdf_data'] as Map<String, dynamic>? ?? {};

      final resultUrl =
          data['result_url']?.toString().trim() ?? '';

      final pdfBase64 =
          data['pdf_base64']?.toString().trim() ?? '';

      final isReady =
          resultUrl.isNotEmpty ||
          pdfBase64.isNotEmpty;

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _currentLoadingPatientId = null;
      });

      if (isReady) {
        _showResultsReadyDialog(
          patientId,
          patientName,
          patient,
        );
      } else {
        _showResultsNotReadyDialog(patientName);
      }
    } catch (e) {
      debugPrint('Check result status error: $e');

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _currentLoadingPatientId = null;
      });

      _showResultsNotReadyDialog(patientName);
    }
  }

  // ============================================================
  // تحميل وفتح PDF
  // ============================================================

  Future<void> _navigateToResultsView(
    String patientId,
    String patientName, [
    Map<String, dynamic>? patient,
  ]) async {
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 12),
                Text('جاري تحميل النتيجة...'),
              ],
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }

      final data =
          patient?['pdf_data'] as Map<String, dynamic>? ?? {};

      final pdfBase64 =
          data['pdf_base64']?.toString().trim() ?? '';

      if (pdfBase64.isNotEmpty) {
        final bytes = base64Decode(pdfBase64);

        await _downloadAndOpenPDFBytes(
          patientName,
          bytes,
          patientId,
        );

        return;
      }

      final resultUrl =
          data['result_url']?.toString().trim() ?? '';

      if (resultUrl.isEmpty) {
        throw Exception('لم يتم العثور على ملف النتيجة');
      }

      final response = await http
          .get(Uri.parse(resultUrl))
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw Exception(
              'انتهت مهلة تحميل النتيجة',
            ),
          );

      if (response.statusCode != 200) {
        throw Exception(
          'فشل تحميل ملف النتيجة: ${response.statusCode}',
        );
      }

      await _downloadAndOpenPDFBytes(
        patientName,
        response.bodyBytes,
        patientId,
      );
    } catch (e) {
      debugPrint('Open result error: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحميل النتيجة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _downloadAndOpenPDFBytes(
    String patientName,
    Uint8List bytes,
    String patientId,
  ) async {
    try {
      final cleanName = patientName
          .replaceAll(RegExp(r'[0-9]'), '')
          .replaceAll(' ', '_')
          .replaceAll(RegExp(r'_+'), '_');

      final fileName =
          patientId.isNotEmpty
              ? 'lab_result_$patientId.pdf'
              : 'نتائج_$cleanName.pdf';

      final directory =
          await getApplicationDocumentsDirectory();

      final filePath = '${directory.path}/$fileName';

      final file = File(filePath);

      if (await file.exists()) {
        await file.delete();
      }

      await file.writeAsBytes(bytes);

      if (!await file.exists()) {
        throw Exception('فشل في حفظ ملف النتيجة');
      }

      await OpenFilex.open(filePath);
    } catch (e) {
      throw Exception('فشل فتح ملف النتيجة: $e');
    }
  }

  // ============================================================
  // مشاركة النتيجة
  // ============================================================

  Future<void> _shareOnWhatsApp(
    String patientId,
    String patientName, [
    Map<String, dynamic>? patient,
  ]) async {
    try {
      final directory =
          await getApplicationDocumentsDirectory();

      final savedFilePath =
          '${directory.path}/lab_result_$patientId.pdf';

      final savedFile = File(savedFilePath);

      if (await savedFile.exists() &&
          savedFile.lengthSync() > 0) {
        await Share.shareXFiles(
          [
            XFile(
              savedFile.path,
              name: 'نتائج_$patientName.pdf',
            ),
          ],
          text:
              'نتائج المختبر - $patientName\n'
              'رقم المريض: $patientId',
          subject: 'نتائج المختبر - $patientName',
        );

        return;
      }

      final data =
          patient?['pdf_data'] as Map<String, dynamic>? ?? {};

      final pdfBase64 =
          data['pdf_base64']?.toString().trim() ?? '';

      if (pdfBase64.isNotEmpty) {
        final bytes = base64Decode(pdfBase64);

        await _saveAndSharePdf(
          bytes,
          patientId,
          patientName,
        );

        return;
      }

      final resultUrl =
          data['result_url']?.toString().trim() ?? '';

      if (resultUrl.isEmpty) {
        throw Exception(
          'لم يتم العثور على ملف النتيجة',
        );
      }

      final response = await http
          .get(Uri.parse(resultUrl))
          .timeout(
            const Duration(seconds: 30),
          );

      if (response.statusCode != 200) {
        throw Exception(
          'فشل تحميل ملف النتيجة',
        );
      }

      await _saveAndSharePdf(
        response.bodyBytes,
        patientId,
        patientName,
      );
    } catch (e) {
      debugPrint('Share result error: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'حدث خطأ في مشاركة النتيجة: $e',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveAndSharePdf(
    Uint8List pdfBytes,
    String patientId,
    String patientName,
  ) async {
    final directory =
        await getApplicationDocumentsDirectory();

    final cleanName = patientName
        .replaceAll(RegExp(r'[0-9]'), '')
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'_+'), '_');

    final fileName = 'نتائج_$cleanName.pdf';

    final filePath =
        '${directory.path}/$fileName';

    final file = File(filePath);

    if (await file.exists()) {
      await file.delete();
    }

    await file.writeAsBytes(pdfBytes);

    if (await file.exists() &&
        file.lengthSync() > 0) {
      await Share.shareXFiles(
        [
          XFile(
            file.path,
            name: fileName,
          ),
        ],
        text:
            'نتائج المختبر - $patientName\n'
            'رقم المريض: $patientId',
        subject:
            'نتائج المختبر - $patientName',
      );
    } else {
      throw Exception(
        'فشل في حفظ ملف النتيجة',
      );
    }
  }

  // ============================================================
  // Dialog - النتيجة جاهزة
  // ============================================================

  void _showResultsReadyDialog(
    String patientId,
    String patientName,
    Map<String, dynamic> patient,
  ) {
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

                              _shareOnWhatsApp(
                                patientId,
                                patientName,
                                patient,
                              );
                            },
                            icon: const Icon(
                              Icons.share,
                              size: 18,
                              color: Colors.green,
                            ),
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
                              padding:
                                  const EdgeInsets.symmetric(
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(10),
                                side: const BorderSide(
                                  color: Colors.green,
                                  width: 1,
                                ),
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

                              _navigateToResultsView(
                                patientId,
                                patientName,
                                patient,
                              );
                            },
                            icon: const Icon(
                              Icons.visibility,
                              size: 18,
                              color: Colors.blue,
                            ),
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
                              padding:
                                  const EdgeInsets.symmetric(
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(10),
                                side: const BorderSide(
                                  color: Colors.blue,
                                  width: 1,
                                ),
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
                    onPressed: () =>
                        Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
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

  // ============================================================
  // Dialog - النتيجة غير جاهزة
  // ============================================================

  void _showResultsNotReadyDialog(
    String patientName, [
    Map<String, dynamic>? statusData,
  ]) {
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
                      onPressed: () =>
                          Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.blue,
                        padding:
                            const EdgeInsets.symmetric(
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(10),
                          side: const BorderSide(
                            color: Colors.blue,
                            width: 1,
                          ),
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

  // ============================================================
  // الواجهة
  // ============================================================

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
              color: Color.fromARGB(255, 34, 96, 129),
              fontSize: 24,
            ),
          ),
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back,
              color: Color.fromARGB(255, 34, 96, 129),
            ),
            onPressed: () =>
                Navigator.of(context).pop(),
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
                      borderRadius:
                          BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color:
                              Colors.grey.withOpacity(0.1),
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
                            fontWeight:
                                FontWeight.w500,
                            color: Colors.grey[700],
                          ),
                        ),

                        const SizedBox(height: 16),

                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () =>
                                    setState(
                                  () =>
                                      _selectedSearchMethod =
                                          1,
                                ),
                                child: Container(
                                  padding:
                                      const EdgeInsets
                                          .symmetric(
                                    vertical: 12,
                                    horizontal: 16,
                                  ),
                                  decoration:
                                      BoxDecoration(
                                    color:
                                        _selectedSearchMethod ==
                                                1
                                            ? const Color
                                                .fromARGB(
                                                255,
                                                34,
                                                96,
                                                129,
                                              )
                                            : Colors.white,
                                    borderRadius:
                                        BorderRadius
                                            .circular(12),
                                    border:
                                        Border.all(
                                      color:
                                          _selectedSearchMethod ==
                                                  1
                                              ? const Color
                                                  .fromARGB(
                                                  255,
                                                  34,
                                                  96,
                                                  129,
                                                )
                                              : Colors
                                                  .grey[300]!,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment
                                            .center,
                                    children: [
                                      Icon(
                                        Icons.receipt,
                                        color:
                                            _selectedSearchMethod ==
                                                    1
                                                ? Colors
                                                    .white
                                                : Colors
                                                    .grey[600],
                                        size: 20,
                                      ),
                                      const SizedBox(
                                        width: 8,
                                      ),
                                      Text(
                                        'رقم الإيصال',
                                        style:
                                            TextStyle(
                                          color:
                                              _selectedSearchMethod ==
                                                      1
                                                  ? Colors
                                                      .white
                                                  : Colors
                                                      .grey[600],
                                          fontWeight:
                                              FontWeight
                                                  .w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(width: 12),

                            Expanded(
                              child: GestureDetector(
                                onTap: () =>
                                    setState(
                                  () =>
                                      _selectedSearchMethod =
                                          0,
                                ),
                                child: Container(
                                  padding:
                                      const EdgeInsets
                                          .symmetric(
                                    vertical: 12,
                                    horizontal: 16,
                                  ),
                                  decoration:
                                      BoxDecoration(
                                    color:
                                        _selectedSearchMethod ==
                                                0
                                            ? const Color
                                                .fromARGB(
                                                255,
                                                34,
                                                96,
                                                129,
                                              )
                                            : Colors.white,
                                    borderRadius:
                                        BorderRadius
                                            .circular(12),
                                    border:
                                        Border.all(
                                      color:
                                          _selectedSearchMethod ==
                                                  0
                                              ? const Color
                                                  .fromARGB(
                                                  255,
                                                  34,
                                                  96,
                                                  129,
                                                )
                                              : Colors
                                                  .grey[300]!,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment
                                            .center,
                                    children: [
                                      Icon(
                                        Icons.phone,
                                        color:
                                            _selectedSearchMethod ==
                                                    0
                                                ? Colors
                                                    .white
                                                : Colors
                                                    .grey[600],
                                        size: 20,
                                      ),
                                      const SizedBox(
                                        width: 8,
                                      ),
                                      Text(
                                        'رقم الهاتف',
                                        style:
                                            TextStyle(
                                          color:
                                              _selectedSearchMethod ==
                                                      0
                                                  ? Colors
                                                      .white
                                                  : Colors
                                                      .grey[600],
                                          fontWeight:
                                              FontWeight
                                                  .w500,
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

                  // حالة تحميل Collection
                  if (_isLoadingCollection)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: LinearProgressIndicator(),
                    ),

                  // البحث برقم الإيصال
                  if (_selectedSearchMethod == 1) ...[
                    Container(
                      padding:
                          const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey
                                .withOpacity(0.1),
                            spreadRadius: 2,
                            blurRadius: 15,
                            offset:
                                const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.receipt,
                                color: Colors.grey[600],
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'أدخل رقم الإيصال:',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight:
                                      FontWeight.w500,
                                  color:
                                      Colors.grey[700],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          Container(
                            decoration:
                                BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius:
                                  BorderRadius.circular(
                                12,
                              ),
                            ),
                            child: TextField(
                              controller:
                                  _receiptController,
                              focusNode:
                                  _receiptFocusNode,
                              keyboardType:
                                  TextInputType.number,
                              textAlign:
                                  TextAlign.right,
                              textDirection:
                                  TextDirection.rtl,
                              decoration:
                                  const InputDecoration(
                                border:
                                    InputBorder.none,
                                contentPadding:
                                    EdgeInsets
                                        .symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed:
                                  _isLoading ||
                                          _isLoadingCollection
                                      ? null
                                      : _searchByReceipt,
                              style:
                                  ElevatedButton
                                      .styleFrom(
                                backgroundColor:
                                    const Color.fromARGB(
                                  255,
                                  34,
                                  96,
                                  129,
                                ),
                                padding:
                                    const EdgeInsets
                                        .symmetric(
                                  vertical: 16,
                                ),
                                shape:
                                    RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius
                                          .circular(
                                    12,
                                  ),
                                ),
                              ),
                              child:
                                  _isLoading
                                      ? const CircularProgressIndicator(
                                        color:
                                            Colors.white,
                                      )
                                      : const Text(
                                        'البحث برقم الإيصال',
                                        style:
                                            TextStyle(
                                          color:
                                              Colors.white,
                                          fontSize: 16,
                                          fontWeight:
                                              FontWeight
                                                  .bold,
                                        ),
                                      ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    // البحث برقم الهاتف
                    Container(
                      padding:
                          const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey
                                .withOpacity(0.1),
                            spreadRadius: 2,
                            blurRadius: 15,
                            offset:
                                const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.phone,
                                color: Colors.grey[600],
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'أدخل رقم الهاتف:',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight:
                                      FontWeight.w500,
                                  color:
                                      Colors.grey[700],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          Container(
                            decoration:
                                BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius:
                                  BorderRadius.circular(
                                12,
                              ),
                            ),
                            child: TextField(
                              controller:
                                  _phoneController,
                              focusNode:
                                  _phoneFocusNode,
                              keyboardType:
                                  TextInputType.phone,
                              textAlign:
                                  TextAlign.left,
                              textDirection:
                                  TextDirection.ltr,
                              decoration:
                                  const InputDecoration(
                                border:
                                    InputBorder.none,
                                contentPadding:
                                    EdgeInsets
                                        .symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed:
                                  _isLoading ||
                                          _isLoadingCollection
                                      ? null
                                      : _searchByPhone,
                              style:
                                  ElevatedButton
                                      .styleFrom(
                                backgroundColor:
                                    const Color.fromARGB(
                                  255,
                                  34,
                                  96,
                                  129,
                                ),
                                padding:
                                    const EdgeInsets
                                        .symmetric(
                                  vertical: 16,
                                ),
                                shape:
                                    RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius
                                          .circular(
                                    12,
                                  ),
                                ),
                              ),
                              child:
                                  _isLoading
                                      ? const CircularProgressIndicator(
                                        color:
                                            Colors.white,
                                      )
                                      : const Text(
                                        'الاستعلام عن النتيجة',
                                        style:
                                            TextStyle(
                                          color:
                                              Colors.white,
                                          fontSize: 16,
                                          fontWeight:
                                              FontWeight
                                                  .bold,
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
                      padding:
                          const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius:
                            BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.red[200]!,
                        ),
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
                    child:
                        _patients.isEmpty &&
                                !_isLoading &&
                                _errorMessage == null
                            ? Center(
                                child: Column(
                                  mainAxisAlignment:
                                      MainAxisAlignment
                                          .center,
                                  children: [
                                    if (!(
                                      _selectedSearchMethod ==
                                              0 &&
                                          _isPhoneFieldFocused
                                    ) &&
                                        !(
                                          _selectedSearchMethod ==
                                                  1 &&
                                              _isReceiptFieldFocused
                                        )) ...[
                                      Icon(
                                        _selectedSearchMethod ==
                                                0
                                            ? Icons.phone
                                            : Icons.receipt,
                                        size: 64,
                                        color:
                                            Colors.grey[400],
                                      ),

                                      const SizedBox(
                                        height: 16,
                                      ),

                                      Text(
                                        _selectedSearchMethod ==
                                                0
                                            ? 'ادخل رقم الهاتف ثم اضغط على الاستعلام عن النتيجة'
                                            : 'أدخل رقم الإيصال ثم اضغط "البحث برقم الإيصال" لعرض النتائج',
                                        style:
                                            const TextStyle(
                                          fontSize: 16,
                                          color:
                                              Color.fromARGB(
                                            255,
                                            250,
                                            152,
                                            5,
                                          ),
                                          height: 1.5,
                                        ),
                                        textAlign:
                                            TextAlign
                                                .center,
                                      ),
                                    ],
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount:
                                    _patients.length,
                                itemBuilder:
                                    (context, index) {
                                  final patient =
                                      _patients[index];

                                  return _buildPatientCard(
                                    patient,
                                  );
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

  // ============================================================
  // بطاقة المريض
  // ============================================================

  Widget _buildPatientCard(
    Map<String, dynamic> patient,
  ) {
    final patientId =
        patient['patient_id']?.toString() ?? '';

    final isRowLoading =
        _isLoading &&
        _currentLoadingPatientId == patientId;

    final receiptId =
        patient['receipt_id']?.toString() ?? '';

    return Card(
      margin:
          const EdgeInsets.only(bottom: 12),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(12),
      ),
      child: Padding(
        padding:
            const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    patient['patient_name']
                            ?.toString() ??
                        'غير محدد',
                    style:
                        const TextStyle(
                      fontSize: 18,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    patient['patient_date']
                            ?.toString() ??
                        'غير محدد',
                    style: TextStyle(
                      fontSize: 14,
                      color:
                          Colors.grey[600],
                    ),
                  ),

                  if (receiptId.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'رقم الإيصال: $receiptId',
                      style: TextStyle(
                        fontSize: 13,
                        color:
                            Colors.grey[600],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            ElevatedButton(
              onPressed:
                  isRowLoading
                      ? null
                      : () =>
                          _viewResults(
                            patient,
                          ),
              style:
                  ElevatedButton
                      .styleFrom(
                backgroundColor:
                    const Color.fromARGB(
                  255,
                  34,
                  96,
                  129,
                ),
                padding:
                    const EdgeInsets
                        .symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                shape:
                    RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(
                    8,
                  ),
                ),
              ),
              child:
                  isRowLoading
                      ? const SizedBox(
                        width: 16,
                        height: 16,
                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<
                                  Color>(
                            Colors.white,
                          ),
                        ),
                      )
                      : const Text(
                        'عرض النتيجة',
                        style:
                            TextStyle(
                          color:
                              Colors.white,
                          fontSize: 12,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
            ),
          ],
        ),
      ),
    );
  }
}