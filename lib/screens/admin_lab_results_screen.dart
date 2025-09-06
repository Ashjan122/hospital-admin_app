import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:open_filex/open_filex.dart';

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
  final TextEditingController _phoneController = TextEditingController();
  bool _isLoading = false;
  List<Map<String, dynamic>> _patients = [];
  String? _errorMessage;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _phoneController.addListener(_onPhoneChanged);
  }

  @override
  void dispose() {
    _phoneController.removeListener(_onPhoneChanged);
    _phoneController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onPhoneChanged() {
    final phone = _phoneController.text.trim();
    
    // إلغاء البحث السابق
    _searchDebounce?.cancel();
    
    if (phone.isEmpty) {
      setState(() {
        _patients = [];
        _errorMessage = null;
      });
      return;
    }
    
    // البحث فقط عند اكتمال الرقم (10 رقم)
    if (phone.length == 10) {
      // تأخير البحث لمدة 200 مللي ثانية لتسريع الاستجابة
      _searchDebounce = Timer(const Duration(milliseconds: 200), () {
        _searchPatients();
      });
    } else if (phone.length > 10) {
      // إذا تم كتابة أكثر من 10 رقم، ابحث فوراً
      _searchPatients();
    }
  }

  Future<void> _searchPatients() async {
    final phone = _phoneController.text.trim();
    
    if (phone.isEmpty) {
      setState(() {
        _errorMessage = 'يرجى إدخال رقم الهاتف';
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
      final url = 'https://alroomy.a.pinggy.link/projects/bootstraped/new/patients_api.php?phone=$phone';
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('انتهت مهلة الاتصال');
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['success'] == true) {
          setState(() {
            _patients = List<Map<String, dynamic>>.from(data['data']);
            _isLoading = false;
          });
          
                     // للتشخيص - عرض بيانات المرضى
           debugPrint('Found ${_patients.length} patients');
           for (int i = 0; i < _patients.length; i++) {
             debugPrint('Patient $i: ${_patients[i]}');
           }
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

  Future<void> _viewResults(Map<String, dynamic> patient) async {
    final patientId = patient['patient_id']?.toString();
    
    if (patientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('خطأ: معرف المريض غير متوفر'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // للتشخيص - عرض معرف المريض
    debugPrint('Patient ID: $patientId');
    debugPrint('Patient Name: ${patient['patient_name']}');

    // إظهار مؤشر التحميل
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2FBDAF)),
          ),
        );
      },
    );

    try {
      final url = 'https://alroomy.a.pinggy.link/projects/bootstraped/new/lab_results_api.php?patient_id=$patientId';
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('انتهت مهلة الاتصال');
        },
      );

      // إخفاء مؤشر التحميل
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['success'] == true) {
          // تحميل وعرض PDF
          await _downloadAndOpenPDF(patient['patient_name'] ?? 'نتائج_المختبر', data);
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['message'] ?? 'خطأ في تحميل النتائج'),
                backgroundColor: Colors.red,
              ),
            );
          }
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
      // إخفاء مؤشر التحميل في حالة الخطأ
      if (context.mounted && Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في الاتصال: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _downloadAndOpenPDF(String patientName, Map<String, dynamic> apiData) async {
    try {
      // للتشخيص - عرض بيانات API
      debugPrint('API Data: $apiData');
      
      // إنشاء اسم الملف
      final fileName = 'نتائج_${patientName}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      
      // الحصول على مجلد التطبيق
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/$fileName';
      
      // التحقق من وجود بيانات PDF في الاستجابة
      final pdfData = apiData['data'];
      PdfDocument document;
      
      if (pdfData != null && pdfData['pdf_base64'] != null) {
        // إذا كان هناك PDF base64، استخدمه
        try {
          final Uint8List pdfBytes = base64Decode(pdfData['pdf_base64']);
          document = PdfDocument(inputBytes: pdfBytes);
        } catch (e) {
          // في حالة فشل فك الترميز، أنشئ PDF جديد
          document = PdfDocument();
          final PdfPage page = document.pages.add();
          final PdfGraphics graphics = page.graphics;
          
          final PdfFont titleFont = PdfStandardFont(PdfFontFamily.helvetica, 20, style: PdfFontStyle.bold);
          final PdfFont normalFont = PdfStandardFont(PdfFontFamily.helvetica, 14);
          final PdfFont smallFont = PdfStandardFont(PdfFontFamily.helvetica, 12);
          final PdfBrush brush = PdfSolidBrush(PdfColor(0, 0, 0));
          
          graphics.drawString(
            'نتائج المختبر',
            titleFont,
            brush: brush,
            bounds: Rect.fromLTWH(50, 50, 500, 30),
          );
          
          graphics.drawString(
            'اسم المريض: $patientName',
            normalFont,
            brush: brush,
            bounds: Rect.fromLTWH(50, 100, 500, 25),
          );
          
          graphics.drawString(
            'تاريخ الطباعة: ${DateTime.now().toString().split('.')[0]}',
            smallFont,
            brush: brush,
            bounds: Rect.fromLTWH(50, 130, 500, 20),
          );
          
          graphics.drawLine(
            PdfPen(PdfColor(0, 0, 0), width: 1),
            Offset(50, 170),
            Offset(550, 170),
          );
          
          graphics.drawString(
            'تم إنشاء هذا التقرير بناءً على طلب عرض نتائج المختبر',
            smallFont,
            brush: brush,
            bounds: Rect.fromLTWH(50, 200, 500, 20),
          );
        }
      } else {
        // إنشاء ملف PDF بسيط مع معلومات المريض
        document = PdfDocument();
        final PdfPage page = document.pages.add();
        final PdfGraphics graphics = page.graphics;
        
        final PdfFont titleFont = PdfStandardFont(PdfFontFamily.helvetica, 20, style: PdfFontStyle.bold);
        final PdfFont normalFont = PdfStandardFont(PdfFontFamily.helvetica, 14);
        final PdfFont smallFont = PdfStandardFont(PdfFontFamily.helvetica, 12);
        final PdfBrush brush = PdfSolidBrush(PdfColor(0, 0, 0));
        
        graphics.drawString(
          'نتائج المختبر',
          titleFont,
          brush: brush,
          bounds: Rect.fromLTWH(50, 50, 500, 30),
        );
        
        graphics.drawString(
          'اسم المريض: $patientName',
          normalFont,
          brush: brush,
          bounds: Rect.fromLTWH(50, 100, 500, 25),
        );
        
        graphics.drawString(
          'تاريخ الطباعة: ${DateTime.now().toString().split('.')[0]}',
          smallFont,
          brush: brush,
          bounds: Rect.fromLTWH(50, 130, 500, 20),
        );
        
        graphics.drawLine(
          PdfPen(PdfColor(0, 0, 0), width: 1),
          Offset(50, 170),
          Offset(550, 170),
        );
        
        graphics.drawString(
          'تم إنشاء هذا التقرير بناءً على طلب عرض نتائج المختبر',
          smallFont,
          brush: brush,
          bounds: Rect.fromLTWH(50, 200, 500, 20),
        );
      }
      
      // حفظ الملف
      final File file = File(filePath);
      final List<int> pdfBytes = await document.save();
      await file.writeAsBytes(pdfBytes);
      document.dispose();
      
      // التحقق من وجود الملف
      if (await file.exists()) {
        // محاولة فتح الملف
        try {
          await OpenFilex.open(filePath);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('تم فتح ملف النتائج بنجاح'),
                backgroundColor: Color(0xFF2FBDAF),
              ),
            );
          }
        } catch (e) {
          // في حالة فشل فتح الملف، اعرض رسالة نجاح مع مسار الملف
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('تم حفظ الملف بنجاح في: $filePath'),
                backgroundColor: const Color(0xFF2FBDAF),
                duration: const Duration(seconds: 8),
              ),
            );
          }
        }
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
                  // Search Section
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withValues(alpha: 0.1),
                          spreadRadius: 2,
                          blurRadius: 15,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                                             child: TextField(
                         controller: _phoneController,
                         keyboardType: TextInputType.phone,
                         textAlign: TextAlign.left,
                         textDirection: TextDirection.ltr,
                         decoration: InputDecoration(
                          hintText: 'أدخل رقم الهاتف',
                          prefixIcon: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: Padding(
                                    padding: EdgeInsets.all(12),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2FBDAF)),
                                    ),
                                  ),
                                )
                              : const Icon(Icons.phone, color: Color(0xFF2FBDAF)),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Error Message
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

                  // Results Section
                  Expanded(
                    child: _patients.isEmpty && !_isLoading && _errorMessage == null
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'ابحث عن المرضى برقم الهاتف',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[600],
                                  ),
                                ),
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
              onPressed: () => _viewResults(patient),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2FBDAF),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
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
