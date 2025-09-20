import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';


import 'package:hospital_admin_app/screens/central_specialties_screen.dart';
import 'package:hospital_admin_app/screens/central_doctors_screen.dart';
import 'package:hospital_admin_app/screens/central_insurance_screen.dart';
import 'package:hospital_admin_app/screens/dashboard_screen.dart';
import 'package:hospital_admin_app/screens/reception_staff_list_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'dart:typed_data';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:hospital_admin_app/screens/users_stats_screen.dart';
import 'package:hospital_admin_app/screens/sample_requests_screen.dart';
import 'package:hospital_admin_app/screens/support_numbers_screen.dart';
import 'package:hospital_admin_app/screens/control_notifications_screen.dart';
import 'package:hospital_admin_app/screens/home_clinic_centers_screen.dart';

class ControlPanelScreen extends StatefulWidget {
  const ControlPanelScreen({super.key});

  @override
  State<ControlPanelScreen> createState() => _ControlPanelScreenState();
}

class _ControlPanelScreenState extends State<ControlPanelScreen> {
  final _formKey = GlobalKey<FormState>();
  final _centerNameController = TextEditingController();
  final _centerAddressController = TextEditingController();
  final _centerPhoneController = TextEditingController();
  final _centerOrderController = TextEditingController();
  final _searchController = TextEditingController();
  final _centerNameFocus = FocusNode();
  final _centerAddressFocus = FocusNode();
  final _centerPhoneFocus = FocusNode();
  final _centerOrderFocus = FocusNode();
  bool _isAddingCenter = false;
  bool _showAddForm = false;
  String? _editingCenterId;
  String _searchQuery = '';
  bool _showHomeGrid = true; // عرض شبكة الأيقونات في الشاشة الرئيسية
  
  // Image handling variables
  String _selectedImageUrl = '';
  File? _selectedImageFile;
  bool _isUploadingImage = false;
  final ImagePicker _picker = ImagePicker();

  // تم استبدال نافذة الإحصائيات بشاشة مخصصة UsersStatsScreen

  @override
  void initState() {
    super.initState();
    print('ControlPanelScreen initState');
    _checkLoginStatus();
    _restoreLastView();
  }

  Future<void> _restoreLastView() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastView = prefs.getString('controlPanelLastView');
      if (!mounted) return;
      if (lastView == 'centers') {
        setState(() {
          _showHomeGrid = false;
        });
      }
    } catch (_) {}
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    final userType = prefs.getString('userType');
    
    print('ControlPanel _checkLoginStatus - isLoggedIn: $isLoggedIn, userType: $userType');
    
    if (!isLoggedIn || userType != 'control') {
      print('Redirecting to login screen');
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    } else {
      print('User is logged in as control, staying in ControlPanel');
      // حذف fromControlPanel عند الوصول للكنترول
      await prefs.remove('fromControlPanel');
      print('تم حذف fromControlPanel عند الوصول للكنترول');
      
      // إعادة الاشتراك في الإشعارات إذا كان مشترك سابقاً
      await _restoreNotificationSubscription();
    }
  }

  Future<void> _restoreNotificationSubscription() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isSubscribed = prefs.getBool('subscribed_to_new_signup') ?? false;
      
      if (isSubscribed) {
        // استيراد Firebase Messaging
        final FirebaseMessaging messaging = FirebaseMessaging.instance;
        await messaging.subscribeToTopic('new_signup');
        print('تم إعادة الاشتراك في إشعارات الحسابات الجديدة');
      } else {
        // إذا لم يكن مشترك، اشترك تلقائياً
        final FirebaseMessaging messaging = FirebaseMessaging.instance;
        await messaging.subscribeToTopic('new_signup');
        await prefs.setBool('subscribed_to_new_signup', true);
        print('تم الاشتراك التلقائي في إشعارات الحسابات الجديدة');
      }
    } catch (e) {
      print('خطأ في إعادة الاشتراك في الإشعارات: $e');
    }
  }

  @override
  void dispose() {
    _centerNameController.dispose();
    _centerAddressController.dispose();
    _centerPhoneController.dispose();
    _centerOrderController.dispose();
    _searchController.dispose();
    _centerNameFocus.dispose();
    _centerAddressFocus.dispose();
    _centerPhoneFocus.dispose();
    _centerOrderFocus.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      
      if (image != null) {
        setState(() {
          _selectedImageFile = File(image.path);
        });
        
        // رفع الصورة إلى Firebase Storage
        await _uploadImage();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في اختيار الصورة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _uploadImage() async {
    if (_selectedImageFile == null) return;
    
    setState(() {
      _isUploadingImage = true;
    });
    
    try {
      // إنشاء اسم فريد للصورة
      final fileName = 'facilities/${DateTime.now().millisecondsSinceEpoch}_${path.basename(_selectedImageFile!.path)}';
      
      // رفع الصورة إلى Firebase Storage
      final storageRef = FirebaseStorage.instance.ref().child(fileName);
      final uploadTask = storageRef.putFile(_selectedImageFile!);
      
      // انتظار اكتمال الرفع
      final snapshot = await uploadTask;
      
      // الحصول على رابط التحميل
      final downloadUrl = await snapshot.ref.getDownloadURL();
      
      setState(() {
        _selectedImageUrl = downloadUrl;
        _isUploadingImage = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم رفع الصورة بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isUploadingImage = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في رفع الصورة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showImageSourceDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('اختر مصدر الصورة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('الكاميرا'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('المعرض'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }




  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  // عنصر بطاقة أيقونة في الشاشة الرئيسية
  Widget _buildHomeCard({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color color = const Color(0xFF0D47A1),
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 32, color: color),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addCenter() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isAddingCenter = true;
      });

      try {
        // جلب أعلى ترتيب موجود لتحديد الترتيب التالي
        final snapshot = await FirebaseFirestore.instance
            .collection('medicalFacilities')
            .orderBy('order', descending: true)
            .limit(1)
            .get();
        
        int nextOrder = 1;
        if (snapshot.docs.isNotEmpty) {
          final highestOrder = snapshot.docs.first.data()['order'] ?? 0;
          nextOrder = highestOrder + 1;
        }

        final centerData = {
          'name': _centerNameController.text.trim(),
          'address': _centerAddressController.text.trim(),
          'phone': _centerPhoneController.text.trim(),
          'order': nextOrder, // ترتيب تلقائي
          'available': true,
          'imageUrl': _selectedImageUrl.isNotEmpty ? _selectedImageUrl : null,
          'createdAt': FieldValue.serverTimestamp(),
        };
        
        await FirebaseFirestore.instance
            .collection('medicalFacilities')
            .add(centerData);

        _centerNameController.clear();
        _centerAddressController.clear();
        _centerPhoneController.clear();
        _centerOrderController.clear(); // نمسح حقل الترتيب بعد الإضافة
        setState(() {
          _selectedImageUrl = '';
          _selectedImageFile = null;
          _showAddForm = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم إضافة المركز بنجاح'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('خطأ في إضافة المركز: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        setState(() {
          _isAddingCenter = false;
        });
      }
    }
  }

  Future<void> _toggleCenterAvailability(String centerId, bool currentStatus) async {
    try {
      await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(centerId)
          .update({
        'available': !currentStatus,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(currentStatus ? 'تم إلغاء تفعيل المركز' : 'تم تفعيل المركز'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحديث حالة المركز: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _exportCenterDoctorsSchedulePdf(String centerId, String centerName) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(
            color: Color(0xFF0D47A1),
          ),
        ),
      );

      final PdfDocument document = PdfDocument();

      // Load assets (logo and Arabic font) if available
      PdfBitmap? logoImage;
      PdfFont baseFont;
      Uint8List? arabicFontBytes;
      try {
        final ByteData logoData = await rootBundle.load('assets/images/logo.png');
        logoImage = PdfBitmap(logoData.buffer.asUint8List());
      } catch (_) {}

      try {
        final ByteData fontData = await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf');
        arabicFontBytes = fontData.buffer.asUint8List();
        baseFont = PdfTrueTypeFont(arabicFontBytes, 12, style: PdfFontStyle.regular);
      } catch (_) {
        baseFont = PdfStandardFont(PdfFontFamily.helvetica, 12);
      }

      final PdfFont titleFont = (arabicFontBytes != null)
          ? PdfTrueTypeFont(arabicFontBytes, 20, style: PdfFontStyle.bold)
          : PdfStandardFont(PdfFontFamily.helvetica, 20, style: PdfFontStyle.bold);
      final PdfFont headerFont = (arabicFontBytes != null)
          ? PdfTrueTypeFont(arabicFontBytes, 16, style: PdfFontStyle.bold)
          : PdfStandardFont(PdfFontFamily.helvetica, 16, style: PdfFontStyle.bold);
      // Compact fonts for dense tables
      final PdfFont colHeaderFont = (arabicFontBytes != null)
          ? PdfTrueTypeFont(arabicFontBytes, 12, style: PdfFontStyle.bold)
          : PdfStandardFont(PdfFontFamily.helvetica, 12, style: PdfFontStyle.bold);
      final PdfFont bodyFont = (arabicFontBytes != null)
          ? PdfTrueTypeFont(arabicFontBytes, 11, style: PdfFontStyle.bold)
          : PdfStandardFont(PdfFontFamily.helvetica, 11, style: PdfFontStyle.bold);

      // Fetch specializations for the center
      final specializationsSnapshot = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(centerId)
          .collection('specializations')
          .get();
      // headerDrawn no longer needed since center header is drawn on every page

      for (var specDoc in specializationsSnapshot.docs) {
        final specData = specDoc.data();
        final String specName = specData['specName']?.toString() ?? specDoc.id;

        // Fetch doctors under this specialization
        final doctorsSnapshot = await FirebaseFirestore.instance
            .collection('medicalFacilities')
            .doc(centerId)
            .collection('specializations')
            .doc(specDoc.id)
            .collection('doctors')
            .get();

        // Add a page per specialization
        final PdfPage page = document.pages.add();
        PdfGraphics currentG = page.graphics;
        Size currentPageSize = page.getClientSize();

        // Watermark on every page (more transparent centered logo)
        if (logoImage != null) {
          currentG.save();
          currentG.setTransparency(0.04);
          final double wmW = currentPageSize.width * 0.7;
          final double wmH = wmW;
          currentG.drawImage(
            logoImage,
            Rect.fromLTWH((currentPageSize.width - wmW) / 2, (currentPageSize.height - wmH) / 2, wmW, wmH),
          );
          currentG.restore();
        }
        // Draw center name and small logo on every page
        if (logoImage != null) {
          currentG.drawImage(logoImage, Rect.fromLTWH(currentPageSize.width - 60, 20, 40, 40));
        }
        currentG.drawString(
          centerName,
          titleFont,
          bounds: Rect.fromLTWH(0, 30, currentPageSize.width, 36),
          format: PdfStringFormat(alignment: PdfTextAlignment.center, textDirection: PdfTextDirection.rightToLeft),
        );
        currentG.drawString(
          specName,
          headerFont,
          bounds: Rect.fromLTWH(0, 80, currentPageSize.width, 28),
          format: PdfStringFormat(alignment: PdfTextAlignment.center, textDirection: PdfTextDirection.rightToLeft),
        );

        // Single table for all doctors in this specialization (rows=days, columns=doctors)
        final List<String> days = ['الأحد','الاثنين','الثلاثاء','الأربعاء','الخميس','الجمعة','السبت'];
        final double topStart = 120;  // more space above for titles
        final double rowHeight = 26;  // larger row height for clearer cells
        final double dayColWidth = 76; // wider day column
        final double doctorColWidth = 110; // wider doctor column
        // Unified paddings for consistent spacing
        const double cellPadX = 1.0;
        const double headerPadY = 4.0;
        const double bodyPadY = 3.0;

        // Collect active doctors
        final List<Map<String, dynamic>> activeDoctors = [];
        for (var d in doctorsSnapshot.docs) {
          final m = d.data();
          if ((m['isActive'] ?? true) == true) {
            activeDoctors.add({
              'name': m['docName']?.toString() ?? 'غير معروف',
              'schedule': (m['workingSchedule'] as Map<String, dynamic>?) ?? {},
            });
          }
        }

        // If no active doctors, skip this specialization (do not draw a page)
        if (activeDoctors.isEmpty) {
          // remove the just-added page (since nothing to show)
          document.pages.remove(page);
          continue;
        }

        // Determine how many doctor columns fit per table row (horizontally)
        final int maxColsPerTable = 6; // allow up to 6 doctors per table row
        const double tableSpacing = 8.0; // vertical space between stacked tables

        // Render stacked tables on the same page when space allows
        int start = 0;
        double currentYForTables = topStart;
        while (start < activeDoctors.length) {
          final int remaining = activeDoctors.length - start;
          final int colsThisTable = remaining < maxColsPerTable ? remaining : maxColsPerTable;

          // For small tables (1-2 doctors), expand to minimum width and center
          final bool isNarrow = colsThisTable <= 2;
          double dColW = doctorColWidth;
          double dayW = dayColWidth;
          double localTableWidth = dayW + colsThisTable * dColW;
          if (isNarrow) {
            final double minTableWidth = currentPageSize.width * 0.7; // at least 70% page width
            if (localTableWidth < minTableWidth) {
              final double scale = minTableWidth / localTableWidth;
              dColW *= scale;
              dayW *= scale;
              localTableWidth = dayW + colsThisTable * dColW;
            }
          }
          // For 5- or 6-doctor tables, shrink slightly to keep layout tidy
          if (!isNarrow && (colsThisTable == 5 || colsThisTable == 6)) {
            final double shrink = (colsThisTable == 5) ? 0.85 : 0.80;
            dColW *= shrink;
            dayW *= shrink;
            localTableWidth = dayW + colsThisTable * dColW;
          }
          // Ensure table fits within page width (with small margins)
          final double maxAllowedWidth = currentPageSize.width - 16;
          if (localTableWidth > maxAllowedWidth) {
            final double fitScale = maxAllowedWidth / localTableWidth;
            dColW *= fitScale;
            dayW *= fitScale;
            localTableWidth = dayW + colsThisTable * dColW;
          }
          final double startX = (currentPageSize.width - localTableWidth) / 2;

          // Measure table height (header + days rows)
          final double tableHeight = rowHeight * (1 + days.length);

          // If doesn't fit on current page, create a new page and reset currentYForTables
          if (currentYForTables + tableHeight > currentPageSize.height - 40) {
            currentG.drawString(
              'يتبع...',
              baseFont,
              bounds: Rect.fromLTWH(0, currentPageSize.height - 30, currentPageSize.width, 20),
              format: PdfStringFormat(alignment: PdfTextAlignment.center, textDirection: PdfTextDirection.rightToLeft),
            );
            final PdfPage nextPage = document.pages.add();
            currentG = nextPage.graphics;
            currentPageSize = nextPage.getClientSize();
            // Watermark on paginated pages
            if (logoImage != null) {
              currentG.save();
              currentG.setTransparency(0.04);
              final double wmW2 = currentPageSize.width * 0.7;
              final double wmH2 = wmW2;
              currentG.drawImage(
                logoImage,
                Rect.fromLTWH((currentPageSize.width - wmW2) / 2, (currentPageSize.height - wmH2) / 2, wmW2, wmH2),
              );
              currentG.restore();
            }
            currentG.drawString(
              specName,
              headerFont,
              bounds: Rect.fromLTWH(0, 60, currentPageSize.width, 25),
              format: PdfStringFormat(alignment: PdfTextAlignment.center, textDirection: PdfTextDirection.rightToLeft),
            );
            currentYForTables = topStart;
          }

          // Header row background
          currentG.drawRectangle(
            bounds: Rect.fromLTWH(startX, currentYForTables, localTableWidth, rowHeight),
            pen: PdfPen(PdfColor(180, 180, 180)),
            brush: PdfSolidBrush(PdfColor(235, 235, 235)),
          );

          // Day header (rightmost)
          currentG.drawString(
            'اليوم',
            colHeaderFont,
            bounds: Rect.fromLTWH(startX + colsThisTable * dColW, currentYForTables + headerPadY, dayW, rowHeight),
            format: PdfStringFormat(alignment: PdfTextAlignment.center, textDirection: PdfTextDirection.rightToLeft),
          );

          // Doctor headers
          for (int c = 0; c < colsThisTable; c++) {
            final String dName = activeDoctors[start + c]['name'] as String;
            final double x = startX + c * dColW;
            currentG.drawString(
              dName,
              colHeaderFont,
              bounds: Rect.fromLTWH(x + cellPadX, currentYForTables + headerPadY, dColW - (cellPadX * 2), rowHeight),
              format: PdfStringFormat(alignment: PdfTextAlignment.center, textDirection: PdfTextDirection.rightToLeft),
            );
          }

          double y = currentYForTables + rowHeight;

          // Rows for each day
          for (int i = 0; i < days.length; i++) {
            final String day = days[i];

            // row background
            currentG.drawRectangle(
              bounds: Rect.fromLTWH(startX, y, localTableWidth, rowHeight),
              pen: PdfPen(PdfColor(220, 220, 220)),
            );

            // Day cell (rightmost)
            currentG.drawString(
              day,
              bodyFont,
              bounds: Rect.fromLTWH(startX + colsThisTable * dColW, y + bodyPadY, dayW, rowHeight),
              format: PdfStringFormat(alignment: PdfTextAlignment.center, textDirection: PdfTextDirection.rightToLeft),
            );

            // Doctor cells (show only period labels without times)
            for (int c = 0; c < colsThisTable; c++) {
              final Map<String, dynamic> schedule = activeDoctors[start + c]['schedule'] as Map<String, dynamic>;
              String text = '—';
              final Map<String, dynamic>? daySchedule = schedule[day] as Map<String, dynamic>?;
              if (daySchedule != null) {
                final bool hasMorning = daySchedule['morning'] != null;
                final bool hasEvening = daySchedule['evening'] != null;
                final List<String> parts = [];
                if (hasMorning) parts.add('صباح');
                if (hasEvening) parts.add('مساء');
                if (parts.isNotEmpty) {
                  text = parts.join(' - ');
                }
              }

              final double x = startX + c * dColW;
              currentG.drawString(
                text,
                bodyFont,
                bounds: Rect.fromLTWH(x + cellPadX, y + bodyPadY, dColW - (cellPadX * 2), rowHeight),
                format: PdfStringFormat(alignment: PdfTextAlignment.center, textDirection: PdfTextDirection.rightToLeft),
              );
            }

            y += rowHeight;
          }

          // advance to next block (stacked table on same page if space allows)
          currentYForTables = y + tableSpacing;
          start += colsThisTable;
        }

      }

      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'جدول_الأطباء_${centerName.replaceAll(' ', '_')}.pdf';
      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(await document.save());
      document.dispose();

      if (mounted) {
        Navigator.of(context).pop();
      }

      await OpenFilex.open(file.path);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إنشاء وفتح ملف PDF لجدول الأطباء'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء إنشاء PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _editCenter(String centerId, Map<String, dynamic> centerData) async {
    setState(() {
      _editingCenterId = centerId;
      _centerNameController.text = centerData['name'] ?? '';
      _centerAddressController.text = centerData['address'] ?? '';
      _centerPhoneController.text = centerData['phone'] ?? '';
      // لا نعرض حقل الترتيب عند التعديل
      _selectedImageUrl = centerData['imageUrl'] ?? '';
      _showAddForm = true;
    });
  }

  Future<void> _updateCenter() async {
    if (_formKey.currentState!.validate() && _editingCenterId != null) {
      setState(() {
        _isAddingCenter = true;
      });

      try {
        // الحفاظ على الترتيب الحالي للمركز
        final currentCenterDoc = await FirebaseFirestore.instance
            .collection('medicalFacilities')
            .doc(_editingCenterId)
            .get();
        
        final currentOrder = currentCenterDoc.data()?['order'] ?? 999;

        await FirebaseFirestore.instance
            .collection('medicalFacilities')
            .doc(_editingCenterId)
            .update({
          'name': _centerNameController.text.trim(),
          'address': _centerAddressController.text.trim(),
          'phone': _centerPhoneController.text.trim(),
          'order': currentOrder, // الحفاظ على الترتيب الحالي
          'imageUrl': _selectedImageUrl.isNotEmpty ? _selectedImageUrl : null,
        });

        _centerNameController.clear();
        _centerAddressController.clear();
        _centerPhoneController.clear();
        _centerOrderController.clear(); // نمسح حقل الترتيب بعد التحديث
        setState(() {
          _selectedImageUrl = '';
          _selectedImageFile = null;
          _editingCenterId = null;
          _showAddForm = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم تحديث المركز بنجاح'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('خطأ في تحديث المركز: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        setState(() {
          _isAddingCenter = false;
        });
      }
    }
  }

  void _cancelEdit() {
    setState(() {
      _editingCenterId = null;
      _showAddForm = false;
      _centerNameController.clear();
      _centerAddressController.clear();
      _centerPhoneController.clear();
      _centerOrderController.clear(); // نمسح حقل الترتيب عند إلغاء التعديل
      _selectedImageUrl = '';
      _selectedImageFile = null;
    });
  }

  Future<void> _deleteCenter(String centerId, String centerName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف المركز "$centerName"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance
            .collection('medicalFacilities')
            .doc(centerId)
            .delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم حذف المركز بنجاح'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('خطأ في حذف المركز: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showSpecialtiesList() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CentralSpecialtiesScreen(),
      ),
    );
  }

  void _showDoctorsList() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CentralDoctorsScreen(),
      ),
    );
  }

  void _showInsuranceList() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CentralInsuranceScreen(),
      ),
    );
  }

  void _showReceptionStaffList() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ReceptionStaffListScreen(),
      ),
    );
  }

  void _showSampleRequests() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SampleRequestsScreen(),
      ),
    );
  }

  List<QueryDocumentSnapshot> _filterCenters(List<QueryDocumentSnapshot> centers) {
    // ترتيب المراكز أولاً
    final sortedCenters = List<QueryDocumentSnapshot>.from(centers);
    sortedCenters.sort((a, b) {
      try {
        final aData = a.data() as Map<String, dynamic>;
        final bData = b.data() as Map<String, dynamic>;
        
        // التحقق من حالة التفعيل أولاً
        final aAvailable = aData['available'] as bool? ?? false;
        final bAvailable = bData['available'] as bool? ?? false;
        
        // إذا كان أحدهما مفعل والآخر غير مفعل، المفعل يأتي أولاً
        if (aAvailable != bAvailable) {
          return aAvailable ? -1 : 1;
        }
        
        // إذا كان كلاهما مفعل، ترتيب حسب order
        if (aAvailable && bAvailable) {
          final aOrder = aData['order'] as int? ?? 999;
          final bOrder = bData['order'] as int? ?? 999;
          return aOrder.compareTo(bOrder);
        }
        
        // إذا كان كلاهما غير مفعل، ترتيب حسب order
        final aOrder = aData['order'] as int? ?? 999;
        final bOrder = bData['order'] as int? ?? 999;
        return aOrder.compareTo(bOrder);
      } catch (e) {
        return 0;
      }
    });
    
    // ثم تطبيق البحث
    if (_searchQuery.isEmpty) return sortedCenters;
    
    return sortedCenters.where((center) {
      final data = center.data() as Map<String, dynamic>;
      final name = data['name']?.toString().toLowerCase() ?? '';
      final searchLower = _searchQuery.toLowerCase();
      
      return name.contains(searchLower);
    }).toList();
  }

  void _navigateToCenterDashboard(String centerId, String centerName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('centerId', centerId);
    await prefs.setString('centerName', centerName);
    await prefs.setString('userType', 'admin');
    await prefs.setBool('isLoggedIn', true);
    await prefs.setBool('fromControlPanel', true);  // إضافة هذا المتغير
    
    if (mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DashboardScreen(
            centerId: centerId,
            centerName: centerName,
            fromControlPanel: true,
          ),
        ),
      );
      if (!mounted) return;
      setState(() {
        _showHomeGrid = false; // الرجوع إلى عرض المراكز عند العودة من الداشبورد
        _showAddForm = false;
        _searchQuery = '';
        _searchController.clear();
      });
      // persist last view as centers
      SharedPreferences.getInstance().then((p) => p.setString('controlPanelLastView', 'centers'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          title: const Text(
            'لوحة تحكم الكنترول',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF0D47A1),
          elevation: 0,
          centerTitle: true,
          leading: _showHomeGrid
              ? null
              : IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  tooltip: 'الرجوع',
                  onPressed: () {
                    setState(() {
                      _showHomeGrid = true;
                      _showAddForm = false;
                      _searchQuery = '';
                      _searchController.clear();
                    });
                    // persist last view as home
                    SharedPreferences.getInstance().then((p) => p.setString('controlPanelLastView', 'home'));
                  },
          ),
          actions: [
            if (_showHomeGrid)
            IconButton(
                onPressed: _logout,
                icon: const Icon(Icons.logout, color: Colors.white),
                tooltip: 'تسجيل الخروج',
              ),
            if (!_showHomeGrid)
            IconButton(
              onPressed: () => setState(() => _showAddForm = !_showAddForm),
              icon: Icon(
                _showAddForm ? Icons.close : Icons.add,
                color: Colors.white,
              ),
              tooltip: _showAddForm ? 'إغلاق النموذج' : 'إضافة مركز جديد',
            ),
          ],
        ),
        body: _showHomeGrid
            ? Padding(
                  padding: const EdgeInsets.all(16.0),
                child: GridView.count(
                  crossAxisCount: 3,
                  childAspectRatio: 0.9,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                    children: [
                    _buildHomeCard(
                      icon: Icons.business,
                      title: 'المراكز الطبية',
                      onTap: () {
                        setState(() {
                          _showHomeGrid = false;
                          _showAddForm = false;
                          _searchQuery = '';
                          _searchController.clear();
                        });
                        SharedPreferences.getInstance().then((p) => p.setString('controlPanelLastView', 'centers'));
                      },
                    ),
                    _buildHomeCard(
                      icon: Icons.storage,
                      title: 'التخصصات',
                      onTap: () {
                            _showSpecialtiesList();
                          },
                    ),
                    _buildHomeCard(
                      icon: Icons.medical_services,
                      title: 'الأطباء',
                      onTap: () {
                            _showDoctorsList();
                          },
                    ),
                    _buildHomeCard(
                      icon: Icons.verified_user,
                      title: 'التأمين',
                      onTap: () {
                            _showInsuranceList();
                          },
                    ),
                    _buildHomeCard(
                      icon: Icons.people_alt,
                      title: 'موظفي الاستقبال',
                      onTap: () {
                            _showReceptionStaffList();
                          },
                    ),
                    _buildHomeCard(
                      icon: Icons.biotech,
                      title: 'طلبات العيادة المنزلية',
                      onTap: () {
                            _showSampleRequests();
                          },
                    ),
                    _buildHomeCard(
                      icon: Icons.support_agent,
                      title: 'أرقام الدعم الفني',
                      onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const SupportNumbersScreen(),
                              ),
                            );
                          },
                    ),
                    _buildHomeCard(
                      icon: Icons.query_stats,
                      title: 'إحصائيات المستخدمين',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const UsersStatsScreen(),
                          ),
                        );
                      },
                      ),
                    _buildHomeCard(
                      icon: Icons.notifications,
                      title: 'الإشعارات',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ControlNotificationsScreen(),
                          ),
                        );
                      },
                      ),
                    _buildHomeCard(
                      icon: Icons.home_work,
                      title: 'مراكز العيادة المنزلية',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const HomeClinicCentersScreen(),
                          ),
                        );
                      },
                      ),
                    ],
                  ),
              )
            : Column(
          children: [
            // Add Center Section
            if (_showAddForm)
              Container(
                padding: const EdgeInsets.all(16.0),
                child: Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _editingCenterId != null ? Icons.edit : Icons.add_business,
                              color: const Color(0xFF0D47A1),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _editingCenterId != null ? 'تعديل المركز' : 'إضافة مركز جديد',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              // Image selection section
                              Center(
                                child: Column(
                                  children: [
                                    GestureDetector(
                                      onTap: _showImageSourceDialog,
                                      child: Container(
                                        width: 120,
                                        height: 120,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: const Color(0xFF0D47A1),
                                            width: 3,
                                          ),
                                        ),
                                        child: ClipOval(
                                          child: _isUploadingImage
                                              ? const Center(
                                                  child: CircularProgressIndicator(),
                                                )
                                              : _selectedImageUrl.isNotEmpty
                                                  ? Image.network(
                                                      _selectedImageUrl,
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (context, error, stackTrace) {
                                                        return Image.asset(
                                                          'assets/images/center.png',
                                                          fit: BoxFit.cover,
                                                        );
                                                      },
                                                    )
                                                  : Image.asset(
                                                      'assets/images/center.png',
                                                      fit: BoxFit.cover,
                                                    ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    TextButton.icon(
                                      onPressed: _showImageSourceDialog,
                                      icon: const Icon(Icons.camera_alt),
                                      label: const Text('اختيار صورة المركز'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: const Color(0xFF0D47A1),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _centerNameController,
                                focusNode: _centerNameFocus,
                                decoration: const InputDecoration(
                                  labelText: 'اسم المركز',
                                  border: OutlineInputBorder(),
                                ),
                                textInputAction: TextInputAction.next,
                                onFieldSubmitted: (_) {
                                  _centerNameFocus.unfocus();
                                  _centerAddressFocus.requestFocus();
                                },
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'يرجى إدخال اسم المركز';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _centerAddressController,
                                focusNode: _centerAddressFocus,
                                decoration: const InputDecoration(
                                  labelText: 'عنوان المركز',
                                  border: OutlineInputBorder(),
                                ),
                                textInputAction: TextInputAction.next,
                                onFieldSubmitted: (_) {
                                  _centerAddressFocus.unfocus();
                                  _centerPhoneFocus.requestFocus();
                                },
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'يرجى إدخال عنوان المركز';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _centerPhoneController,
                                focusNode: _centerPhoneFocus,
                                decoration: const InputDecoration(
                                  labelText: 'رقم الهاتف',
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.phone,
                                textInputAction: TextInputAction.next,
                                onFieldSubmitted: (_) {
                                  _centerPhoneFocus.unfocus();
                                  _centerOrderFocus.requestFocus();
                                },
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'يرجى إدخال رقم الهاتف';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _centerOrderController,
                                focusNode: _centerOrderFocus,
                                decoration: const InputDecoration(
                                  labelText: 'ترتيب المركز (رقم)',
                                  border: OutlineInputBorder(),
                                  hintText: 'مثال: 1 للمركز الأول، 2 للمركز الثاني',
                                ),
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) {
                                  _centerOrderFocus.unfocus();
                                },
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'يرجى إدخال ترتيب المركز';
                                  }
                                  final number = int.tryParse(value);
                                  if (number == null || number <= 0) {
                                    return 'يرجى إدخال رقم صحيح موجب';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: _isAddingCenter ? null : (_editingCenterId != null ? _updateCenter : _addCenter),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF0D47A1),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                      ),
                                      child: _isAddingCenter
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                              ),
                                            )
                                          : Text(_editingCenterId != null ? 'تحديث المركز' : 'إضافة المركز'),
                                    ),
                                  ),
                                  if (_editingCenterId != null) ...[
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: _cancelEdit,
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                        ),
                                        child: const Text('إلغاء'),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            
            // تم إزالة شريط البحث حسب الطلب
            
            // Centers List - Takes full remaining space
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('medicalFacilities')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error, color: Colors.red, size: 64),
                          const SizedBox(height: 16),
                          Text('خطأ في الاتصال: ${snapshot.error}'),
                        ],
                      ),
                    );
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final allCenters = snapshot.data?.docs ?? [];
                  final centers = _filterCenters(allCenters);

                  if (centers.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.business, color: Colors.grey, size: 64),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isEmpty
                                ? 'لا توجد مراكز طبية'
                                : 'لا توجد نتائج للبحث',
                            style: const TextStyle(fontSize: 18, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _searchQuery.isEmpty
                                ? 'قم بإضافة مركز جديد باستخدام النموذج أعلاه'
                                : 'جرب البحث بكلمات مختلفة',
                            style: const TextStyle(fontSize: 14, color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () => setState(() => _showAddForm = true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0D47A1),
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('إضافة مركز جديد'),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    itemCount: centers.length,
                    itemBuilder: (context, index) {
                      final center = centers[index];
                      final centerData = center.data() as Map<String, dynamic>;
                      final centerId = center.id;
                      final centerName = centerData['name'] ?? '';
                      final centerAddress = centerData['address'] ?? '';
                      final centerPhone = centerData['phone'] ?? '';
                      final isAvailable = centerData['available'] ?? false;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          onTap: () => _navigateToCenterDashboard(centerId, centerName),
                          leading: const Icon(Icons.business, color: Color(0xFF0D47A1)),
                          title: Text(
                            centerName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('العنوان: $centerAddress'),
                              Text('الهاتف: $centerPhone'),
                              Row(
                                children: [
                                  Icon(
                                    isAvailable ? Icons.check_circle : Icons.cancel,
                                    color: isAvailable ? Colors.green : Colors.red,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isAvailable ? 'مفعل' : 'غير مفعل',
                                    style: TextStyle(
                                      color: isAvailable ? Colors.green : Colors.red,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Icon(
                                    Icons.sort,
                                    color: const Color(0xFF0D47A1),
                                    size: 16,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'ترتيب: ${centerData['order'] ?? 999}',
                                    style: const TextStyle(
                                      color: Color(0xFF0D47A1),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.arrow_forward_ios,
                                color: Colors.grey[400],
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert),
                                onSelected: (value) {
                                  switch (value) {
                                    case 'edit':
                                      _editCenter(centerId, centerData);
                                      break;
                                    case 'toggle':
                                      _toggleCenterAvailability(centerId, isAvailable);
                                      break;
                                    case 'delete':
                                      _deleteCenter(centerId, centerName);
                                      break;
                                    case 'export_pdf':
                                      _exportCenterDoctorsSchedulePdf(centerId, centerName);
                                      break;
                                  }
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem<String>(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        const Icon(Icons.edit, color: Color(0xFF0D47A1), size: 20),
                                        const SizedBox(width: 8),
                                        const Text('تعديل المركز'),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem<String>(
                                    value: 'toggle',
                                    child: Row(
                                      children: [
                                        Icon(
                                          isAvailable ? Icons.block : Icons.check_circle,
                                          color: isAvailable ? Colors.orange : Colors.green,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(isAvailable ? 'إلغاء التفعيل' : 'تفعيل'),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem<String>(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        const Icon(Icons.delete, color: Colors.red, size: 20),
                                        const SizedBox(width: 8),
                                        const Text('حذف المركز'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuDivider(),
                                  const PopupMenuItem<String>(
                                    value: 'export_pdf',
                                    child: Row(
                                      children: [
                                        Icon(Icons.picture_as_pdf, color: Color(0xFF0D47A1), size: 20),
                                        SizedBox(width: 8),
                                        Text('جدول الأطباء PDF'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
