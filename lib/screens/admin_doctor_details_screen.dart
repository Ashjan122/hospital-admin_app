import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:hospital_admin_app/screens/doctor_bookings_screen.dart';
import 'package:hospital_admin_app/screens/admin_doctors_schedule_screen.dart';
import 'package:intl/intl.dart' as intl;
import 'package:intl/date_symbol_data_local.dart';
import 'package:hospital_admin_app/widgets/optimized_loading_widget.dart';

class AdminDoctorDetailsScreen extends StatefulWidget {
  final String doctorId;
  final String centerId;
  final String? centerName;

  const AdminDoctorDetailsScreen({
    super.key,
    required this.doctorId,
    required this.centerId,
    this.centerName,
  });

  @override
  State<AdminDoctorDetailsScreen> createState() => _AdminDoctorDetailsScreenState();
}

class _AdminDoctorDetailsScreenState extends State<AdminDoctorDetailsScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _morningLimitController = TextEditingController();
  final TextEditingController _eveningLimitController = TextEditingController();
  bool _isEditing = false;
  bool _isLoading = false;
  bool _isUploadingImage = false;
  File? _selectedImageFile;
  final ImagePicker _picker = ImagePicker();
  String? _currentPhotoUrl;
  
  // متغيرات إيقاف الحجز
  DateTime? _selectedBlockDate;
  String? _selectedBlockPeriod; // 'morning', 'evening', 'all'
  bool _isBlockingBooking = false;
  Map<String, dynamic>? _doctorData; // لتخزين بيانات الطبيب

  @override
  void initState() {
    super.initState();
    // تهيئة اللغة العربية
    initializeDateFormatting('ar', null);
  }

  Future<Map<String, dynamic>?> fetchDoctorDetails() async {
    try {
      // البحث عن الطبيب في جميع التخصصات
      final specializationsSnapshot = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .get()
          .timeout(const Duration(seconds: 8));

      for (var specDoc in specializationsSnapshot.docs) {
        final doctorDoc = await FirebaseFirestore.instance
            .collection('medicalFacilities')
            .doc(widget.centerId)
            .collection('specializations')
            .doc(specDoc.id)
            .collection('doctors')
            .doc(widget.doctorId)
            .get()
            .timeout(const Duration(seconds: 8));

        if (doctorDoc.exists) {
          final doctorData = doctorDoc.data()!;
          
          // جلب معلومات الطبيب من قاعدة البيانات المركزية
          try {
            final centralDoctorDoc = await FirebaseFirestore.instance
                .collection('allDoctors')
                .doc(widget.doctorId)
                .get();
            
            if (centralDoctorDoc.exists) {
              final centralDoctorData = centralDoctorDoc.data()!;
              doctorData['name'] = centralDoctorData['name'] ?? 'طبيب غير معروف';
              doctorData['phoneNumber'] = centralDoctorData['phoneNumber'] ?? '';
              doctorData['photoUrl'] = centralDoctorData['photoUrl'] ?? 
                  'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQupVHd_oeqnkds0k3EjT1SX4ctwwblwYP2Uw&s';
            }
          } catch (e) {
            // إذا فشل في جلب البيانات من المركزية، استخدم المعرف
            doctorData['name'] = widget.doctorId;
          }
          
          // إضافة اسم التخصص للبيانات
          final specializationData = specDoc.data();
          doctorData['specialization'] = specializationData['specName'] ?? specDoc.id;
          doctorData['specializationId'] = specDoc.id;
          _doctorData = doctorData; // تخزين البيانات في المتغير
          return doctorData;
        }
      }
      
      return null;
    } catch (e) {
      // Error loading doctor details
      return null;
    }
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
      // Starting image upload in details page
      // File path: ${_selectedImageFile!.path}
      
      // التحقق من وجود الملف
      if (!await _selectedImageFile!.exists()) {
        throw Exception('الملف غير موجود في المسار المحدد');
      }
      
      // إنشاء اسم فريد للصورة
      final fileName = 'doctors/${DateTime.now().millisecondsSinceEpoch}_${path.basename(_selectedImageFile!.path)}';
      // File name in Storage: $fileName
      
      // رفع الصورة إلى Firebase Storage
      final storageRef = FirebaseStorage.instance.ref().child(fileName);
      // Storage reference: ${storageRef.fullPath}
      
      // إضافة metadata للصورة
      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {
          'uploaded_at': DateTime.now().toIso8601String(),
          'doctor_id': widget.doctorId,
        },
      );
      
      final uploadTask = storageRef.putFile(_selectedImageFile!, metadata);
      
      // مراقبة تقدم الرفع (بدون استخدام متغيرات محلية لتفادي تحذيرات اللينتر)
      uploadTask.snapshotEvents.listen((_) {});
      
      // انتظار اكتمال الرفع
      final snapshot = await uploadTask;
      // Image uploaded successfully
      
      // الحصول على رابط التحميل
      final downloadUrl = await snapshot.ref.getDownloadURL();
      // Download URL: $downloadUrl
      
      // تحديث رابط الصورة في قاعدة البيانات
      await _updateDoctorPhoto(downloadUrl);
      
      setState(() {
        _currentPhotoUrl = downloadUrl;
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
      // Error uploading image: $e
      // Error type: ${e.runtimeType}
      
      setState(() {
        _isUploadingImage = false;
      });
      
      String errorMessage = 'خطأ في رفع الصورة';
      
      if (e.toString().contains('permission')) {
        errorMessage = 'خطأ في الأذونات - تأكد من قواعد الأمان في Firebase Storage';
      } else if (e.toString().contains('network')) {
        errorMessage = 'خطأ في الاتصال بالإنترنت - تأكد من اتصالك بالإنترنت';
      } else if (e.toString().contains('storage')) {
        errorMessage = 'خطأ في Firebase Storage - تأكد من إعدادات Firebase';
      } else if (e.toString().contains('file')) {
        errorMessage = 'خطأ في الملف - تأكد من صحة الصورة';
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$errorMessage\n$e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _updateDoctorPhoto(String photoUrl) async {
    try {
      // تحديث الصورة في قاعدة البيانات المركزية
      await FirebaseFirestore.instance
          .collection('allDoctors')
          .doc(widget.doctorId)
          .update({
        'photoUrl': photoUrl,
      });
      
      // تحديث الصورة في قاعدة البيانات المحلية أيضاً
      final specializationsSnapshot = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .get();

      for (var specDoc in specializationsSnapshot.docs) {
        final doctorDoc = await FirebaseFirestore.instance
            .collection('medicalFacilities')
            .doc(widget.centerId)
            .collection('specializations')
            .doc(specDoc.id)
            .collection('doctors')
            .doc(widget.doctorId)
            .get();

        if (doctorDoc.exists) {
          // تحديث رابط الصورة
          await FirebaseFirestore.instance
              .collection('medicalFacilities')
              .doc(widget.centerId)
              .collection('specializations')
              .doc(specDoc.id)
              .collection('doctors')
              .doc(widget.doctorId)
              .update({
            'photoUrl': photoUrl,
          });
          break;
        }
      }
    } catch (e) {
      // Error updating doctor photo: $e
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

  Future<void> updateDoctorData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // البحث عن الطبيب في جميع التخصصات
      final specializationsSnapshot = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .get();

      for (var specDoc in specializationsSnapshot.docs) {
        final doctorDoc = await FirebaseFirestore.instance
            .collection('medicalFacilities')
            .doc(widget.centerId)
            .collection('specializations')
            .doc(specDoc.id)
            .collection('doctors')
            .doc(widget.doctorId)
            .get();

        if (doctorDoc.exists) {
          // تحديث البيانات - فقط الحد الأقصى للحجوزات
          await FirebaseFirestore.instance
              .collection('medicalFacilities')
              .doc(widget.centerId)
              .collection('specializations')
              .doc(specDoc.id)
              .collection('doctors')
              .doc(widget.doctorId)
              .update({
            'morningPatientLimit': int.tryParse(_morningLimitController.text) ?? 20,
            'eveningPatientLimit': int.tryParse(_eveningLimitController.text) ?? 20,
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم تحديث إعدادات الطبيب بنجاح'),
              backgroundColor: Colors.green,
            ),
          );

          setState(() {
            _isEditing = false;
          });
          break;
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ في تحديث البيانات'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _unblockBooking(String dateStr) async {
    setState(() {
      _isBlockingBooking = true;
    });

    try {
      // حذف اليوم المحظور من Firestore
      await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .doc(_doctorData!['specializationId'])
          .collection('doctors')
          .doc(widget.doctorId)
          .collection('blockedDates')
          .doc(dateStr)
          .delete();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم إلغاء حظر الحجز في $dateStr'),
          backgroundColor: Colors.green,
        ),
      );

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في إلغاء حظر الحجز: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isBlockingBooking = false;
      });
    }
  }

  Future<void> _showBlockedDatesDialog() async {
    try {
      final blockedSnapshot = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .doc(_doctorData!['specializationId'])
          .collection('doctors')
          .doc(widget.doctorId)
          .collection('blockedDates')
          .get();

      if (blockedSnapshot.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لا توجد أيام محظورة'),
            backgroundColor: const Color(0xFF2FBDAF),
          ),
        );
        return;
      }

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('الأيام المحظورة'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: blockedSnapshot.docs.length,
              itemBuilder: (context, index) {
                final doc = blockedSnapshot.docs[index];
                final data = doc.data();
                final dateStr = data['date'] as String;
                final period = data['period'] as String;

                
                final periodText = period == 'all' ? 'اليوم كاملاً' : 
                                  (period == 'morning' ? 'صباحاً' : 'مساءً');
                
                return ListTile(
                  title: Text(dateStr),
                  subtitle: Text('الفترة: $periodText'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () {
                      Navigator.pop(context);
                      _unblockBooking(dateStr);
                    },
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في تحميل الأيام المحظورة: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _blockBooking() async {
    if (_selectedBlockDate == null || _selectedBlockPeriod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى اختيار التاريخ والفترة'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isBlockingBooking = true;
    });

    try {
      final dateStr = _selectedBlockDate!.toIso8601String().split('T')[0]; // YYYY-MM-DD
      final periodText = _selectedBlockPeriod == 'all' ? 'اليوم كاملاً' : 
                        (_selectedBlockPeriod == 'morning' ? 'الفترة الصباحية' : 'الفترة المسائية');
      
      // حفظ إيقاف الحجز في Firestore
      await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .doc(_doctorData!['specializationId'])
          .collection('doctors')
          .doc(widget.doctorId)
          .collection('blockedDates')
          .doc(dateStr)
          .set({
        'date': dateStr,
        'period': _selectedBlockPeriod,
        'blockedAt': FieldValue.serverTimestamp(),
        'blockedBy': 'admin', // يمكن إضافة معرف المدير لاحقاً
        'reason': 'إيقاف الحجز من قبل المدير',
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم إيقاف الحجز في $dateStr للفترة $periodText'),
          backgroundColor: Colors.green,
        ),
      );

      // إعادة تعيين المتغيرات
      setState(() {
        _selectedBlockDate = null;
        _selectedBlockPeriod = null;
        _isBlockingBooking = false;
      });

    } catch (e) {
      setState(() {
        _isBlockingBooking = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في إيقاف الحجز: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _getArabicDayName(DateTime date) {
    return intl.DateFormat('EEEE', 'ar').format(date).trim();
  }

  Future<void> _showBlockBookingDialog() {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إيقاف الحجز'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // اختيار التاريخ
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: const Text('اختر التاريخ'),
              subtitle: Text(_selectedBlockDate != null 
                  ? '${_selectedBlockDate!.year}/${_selectedBlockDate!.month}/${_selectedBlockDate!.day}'
                  : 'لم يتم الاختيار'),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  selectableDayPredicate: (date) {
                    // فحص إذا كان اليوم متاح في جدول الطبيب
                    if (_doctorData == null) return true;
                    
                    final workingSchedule = _doctorData!['workingSchedule'] as Map<String, dynamic>?;
                    if (workingSchedule == null) return true;
                    
                    final dayName = _getArabicDayName(date);
                    final schedule = workingSchedule[dayName];
                    
                    if (schedule != null && schedule is Map<String, dynamic>) {
                      final morning = schedule['morning'];
                      final evening = schedule['evening'];
                      
                      return (morning != null && morning is Map && morning.isNotEmpty) ||
                             (evening != null && evening is Map && evening.isNotEmpty);
                    }
                    
                    return false;
                  },
                  builder: (context, child) {
                    return Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: ColorScheme.light(
                          primary: const Color(0xFF2FBDAF),
                          onPrimary: Colors.white,
                          onSurface: Colors.black,
                        ),
                        textButtonTheme: TextButtonThemeData(
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF2FBDAF),
                          ),
                        ),
                      ),
                      child: child!,
                    );
                  },
                );
                if (date != null) {
                  setState(() {
                    _selectedBlockDate = date;
                  });
                  Navigator.pop(context);
                  _showBlockBookingDialog();
                }
              },
            ),
            const SizedBox(height: 16),
            
            // اختيار الفترة
            const Text('اختر الفترة:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('صباحاً'),
                  selected: _selectedBlockPeriod == 'morning',
                  onSelected: (selected) {
                    setState(() {
                      _selectedBlockPeriod = selected ? 'morning' : null;
                    });
                    Navigator.pop(context);
                    _showBlockBookingDialog();
                  },
                ),
                ChoiceChip(
                  label: const Text('مساءً'),
                  selected: _selectedBlockPeriod == 'evening',
                  onSelected: (selected) {
                    setState(() {
                      _selectedBlockPeriod = selected ? 'evening' : null;
                    });
                    Navigator.pop(context);
                    _showBlockBookingDialog();
                  },
                ),
                ChoiceChip(
                  label: const Text('اليوم كاملاً'),
                  selected: _selectedBlockPeriod == 'all',
                  onSelected: (selected) {
                    setState(() {
                      _selectedBlockPeriod = selected ? 'all' : null;
                    });
                    Navigator.pop(context);
                    _showBlockBookingDialog();
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: _isBlockingBooking ? null : _blockBooking,
            child: _isBlockingBooking 
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('إيقاف الحجز'),
          ),
        ],
      ),
    );
  }

  Future<void> toggleDoctorStatus(bool isActive) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // البحث عن الطبيب في جميع التخصصات
      final specializationsSnapshot = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .get();

      for (var specDoc in specializationsSnapshot.docs) {
        final doctorDoc = await FirebaseFirestore.instance
            .collection('medicalFacilities')
            .doc(widget.centerId)
            .collection('specializations')
            .doc(specDoc.id)
            .collection('doctors')
            .doc(widget.doctorId)
            .get();

        if (doctorDoc.exists) {
          // تحديث حالة الطبيب
          await FirebaseFirestore.instance
              .collection('medicalFacilities')
              .doc(widget.centerId)
              .collection('specializations')
              .doc(specDoc.id)
              .collection('doctors')
              .doc(widget.doctorId)
              .update({
            'isActive': isActive,
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isActive ? 'تم تفعيل الطبيب' : 'تم تعطيل الطبيب'),
              backgroundColor: Colors.green,
            ),
          );
          break;
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ في تحديث حالة الطبيب'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> toggleDoctorBooking(bool isEnabled) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // البحث عن الطبيب في جميع التخصصات
      final specializationsSnapshot = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .get();

      for (var specDoc in specializationsSnapshot.docs) {
        final doctorDoc = await FirebaseFirestore.instance
            .collection('medicalFacilities')
            .doc(widget.centerId)
            .collection('specializations')
            .doc(specDoc.id)
            .collection('doctors')
            .doc(widget.doctorId)
            .get();

        if (doctorDoc.exists) {
          // تحديث حالة تفعيل الحجز للطبيب
          await FirebaseFirestore.instance
              .collection('medicalFacilities')
              .doc(widget.centerId)
              .collection('specializations')
              .doc(specDoc.id)
              .collection('doctors')
              .doc(widget.doctorId)
              .update({
            'isBookingEnabled': isEnabled,
          });

          // تحديث البيانات المحلية
          if (_doctorData != null) {
            _doctorData!['isBookingEnabled'] = isEnabled;
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isEnabled ? 'تم تفعيل الحجز للطبيب' : 'تم إيقاف الحجز للطبيب'),
              backgroundColor: Colors.green,
            ),
          );
          break;
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ في تحديث حالة الحجز'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showImagePickerDialog(BuildContext context) {
    _showImageSourceDialog();
  }





  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            "تفاصيل الطبيب",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontSize: 24,
            ),
          ),
          backgroundColor: const Color(0xFF2FBDAF),
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              icon: Icon(_isEditing ? Icons.save : Icons.settings),
              onPressed: _isLoading ? null : () {
                if (_isEditing) {
                  updateDoctorData();
                } else {
                  setState(() {
                    _isEditing = true;
                  });
                }
              },
              tooltip: _isEditing ? 'حفظ الإعدادات' : 'تعديل الإعدادات',
            ),
          ],
        ),
        body: SafeArea(
          child: FutureBuilder<Map<String, dynamic>?>(
            future: fetchDoctorDetails(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const OptimizedLoadingWidget(
                message: 'جاري تحميل بيانات الطبيب...',
                color: Color(0xFF2FBDAF),
              );
            }

            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'حدث خطأ في تحميل البيانات',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              );
            }

            if (!snapshot.hasData || snapshot.data == null) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'لم يتم العثور على بيانات الطبيب',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              );
            }

            final doctorData = snapshot.data!;
            
            // استخراج بيانات الطبيب من قاعدة البيانات
            final doctorName = doctorData['docName'] ?? 'طبيب غير معروف';
            final specialization = doctorData['specialization'] ?? 'غير محدد';
            final photoUrl = doctorData['photoUrl'] ?? 
                'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQupVHd_oeqnkds0k3EjT1SX4ctwwblwYP2Uw&s';
            final phoneNumber = doctorData['phoneNumber'] ?? 'غير متوفر';
            final isActive = doctorData['isActive'] ?? true;
            final isBookingEnabled = doctorData['isBookingEnabled'] ?? true;

            // تعيين القيم في controllers إذا لم تكن محددة
            if (!_isEditing) {
              _nameController.text = doctorName;
              _phoneController.text = phoneNumber;
              _morningLimitController.text = (doctorData['morningPatientLimit'] ?? 20).toString();
              _eveningLimitController.text = (doctorData['eveningPatientLimit'] ?? 20).toString();
              _currentPhotoUrl = photoUrl;
            }

            return SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Doctor profile card
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withAlpha(26),
                          spreadRadius: 1,
                          blurRadius: 10,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Profile image
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 60,
                              backgroundImage: _selectedImageFile != null
                                  ? FileImage(_selectedImageFile!)
                                  : NetworkImage(_currentPhotoUrl ?? photoUrl) as ImageProvider,
                              onBackgroundImageError: (exception, stackTrace) {
                                // Handle image error
                              },
                            ),
                            if (_isUploadingImage)
                              Positioned.fill(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withAlpha(128),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  ),
                                ),
                              ),
                            if (_isEditing)
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2FBDAF),
                                    shape: BoxShape.circle,
                                  ),
                                  child: IconButton(
                                    icon: Icon(
                                      _isUploadingImage ? Icons.hourglass_empty : Icons.camera_alt,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    onPressed: _isUploadingImage ? null : () {
                                      _showImagePickerDialog(context);
                                    },
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        
                        // Doctor name
                        Text(
                          doctorName,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        
                        // Specialization
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2FBDAF).withAlpha(26),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            specialization,
                            style: TextStyle(
                              fontSize: 16,
                              color: const Color(0xFF2FBDAF),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Contact information
                  _buildInfoSection(
                    'معلومات التواصل',
                    [
                      _buildInfoRow(Icons.phone, 'رقم الهاتف', phoneNumber),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Patient limits
                  _buildInfoSection(
                    'إعدادات عدد المرضى',
                    [
                      if (_isEditing) ...[
                        _buildEditableInfoRow(
                          Icons.wb_sunny, 
                          'الحد الأقصى للمرضى - الفترة الصباحية', 
                          _morningLimitController,
                          keyboard: TextInputType.number,
                        ),
                        _buildEditableInfoRow(
                          Icons.nightlight, 
                          'الحد الأقصى للمرضى - الفترة المسائية', 
                          _eveningLimitController,
                          keyboard: TextInputType.number,
                        ),
                      ] else ...[
                        _buildInfoRow(
                          Icons.wb_sunny, 
                          'الحد الأقصى للمرضى - الفترة الصباحية', 
                          '${doctorData['morningPatientLimit'] ?? 5} مريض',
                        ),
                        _buildInfoRow(
                          Icons.nightlight, 
                          'الحد الأقصى للمرضى - الفترة المسائية', 
                          '${doctorData['eveningPatientLimit'] ?? 5} مريض',
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Status indicator
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isActive ? Colors.green[50] : Colors.red[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isActive ? Colors.green[200]! : Colors.red[200]!,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isActive ? Icons.check_circle : Icons.cancel,
                          color: isActive ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          isActive ? 'الطبيب نشط' : 'الطبيب معطل',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isActive ? Colors.green[700] : Colors.red[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Booking status indicator (tappable toggle)
                  InkWell(
                    onTap: _isLoading ? null : () {
                      toggleDoctorBooking(!isBookingEnabled);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isBookingEnabled ? Colors.green[50] : Colors.orange[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isBookingEnabled ? Colors.green[200]! : Colors.orange[200]!,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isBookingEnabled ? Icons.play_circle : Icons.pause_circle,
                            color: isBookingEnabled ? Colors.green : Colors.orange,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isBookingEnabled ? 'الحجز مُفعّل' : 'الحجز متوقف',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: isBookingEnabled ? Colors.green[700] : Colors.orange[700],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'اضغط للتبديل',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_isLoading)
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Action buttons
                  Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isLoading ? null : () {
                                toggleDoctorStatus(!isActive);
                              },
                              icon: Icon(isActive ? Icons.block : Icons.check_circle),
                              label: Text(isActive ? 'تعطيل الطبيب' : 'تفعيل الطبيب'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isActive ? Colors.red : Colors.green,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => DoctorBookingsScreen(
                                      doctorId: widget.doctorId,
                                      centerId: widget.centerId,
                                      centerName: widget.centerName,
                                      doctorName: doctorName,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.calendar_today),
                              label: const Text('حجوزات الطبيب'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2FBDAF),
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => AdminDoctorsScheduleScreen(
                                      centerId: widget.centerId,
                                      centerName: widget.centerName,
                                      selectedDoctorId: widget.doctorId,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.schedule),
                              label: const Text('جدول الطبيب'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.purple,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                _showBlockBookingDialog();
                              },
                              icon: const Icon(Icons.block),
                              label: const Text('إيقاف الحجز'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                _showBlockedDatesDialog();
                              },
                              icon: const Icon(Icons.list),
                              label: const Text('الأيام المحظورة'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
        ),
      ),
    );
  }

  Widget _buildInfoSection(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withAlpha(26),
            spreadRadius: 1,
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF2FBDAF).withAlpha(26),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: const Color(0xFF2FBDAF),
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableInfoRow(IconData icon, String label, TextEditingController controller, {TextInputType? keyboard}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF2FBDAF).withAlpha(26),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: const Color(0xFF2FBDAF),
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: controller,
                  keyboardType: keyboard ?? TextInputType.text,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
