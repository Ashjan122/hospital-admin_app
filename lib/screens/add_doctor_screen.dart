import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:hospital_admin_app/services/central_data_service.dart';

class AddDoctorScreen extends StatefulWidget {
  final String centerId;
  final String? centerName;

  const AddDoctorScreen({
    super.key,
    required this.centerId,
    this.centerName,
  });

  @override
  State<AddDoctorScreen> createState() => _AddDoctorScreenState();
}

class _AddDoctorScreenState extends State<AddDoctorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _morningLimitController = TextEditingController(text: '20');
  final _eveningLimitController = TextEditingController(text: '20');
  String? _selectedSpecialization;
  String? _selectedDoctor;
  String _selectedDoctorPhone = '';
  String _selectedDoctorSpecName = '';
  String _selectedPhotoUrl = 'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQupVHd_oeqnkds0k3EjT1SX4ctwwblwYP2Uw&s';
  bool _isLoading = false;
  bool _isUploadingImage = false;
  File? _selectedImageFile;
  final ImagePicker _picker = ImagePicker();
  List<Map<String, dynamic>> _specializations = [];
  List<Map<String, dynamic>> _allDoctors = [];
  List<Map<String, dynamic>> _availableDoctors = [];
  bool _isLoadingData = true;
  Set<String> _centerDoctorIds = {};



  void _showDoctorPickerDialog() {
    String localQuery = '';
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('اختر الطبيب'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'بحث...',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => localQuery = v),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView(
                    shrinkWrap: true,
                    children: _availableDoctors
                        .where((d) => localQuery.isEmpty || (d['name'] as String).toLowerCase().contains(localQuery.toLowerCase()))
                        .map((d) => ListTile(
                              title: Text(d['name'] as String),
                              subtitle: Text((d['phoneNumber'] as String?) ?? ''),
                              onTap: () async {
                                Navigator.of(context).pop();
                                await _populateFromDoctor(d);
                              },
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إلغاء'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoadingData = true;
    });

    try {
      // جلب التخصصات الموجودة في المركز
      final specializationsSnapshot = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .get();

      final specializations = specializationsSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['specName'] ?? doc.id,
        };
      }).toList();

      // جلب جميع الأطباء من قاعدة البيانات المركزية
      final allDoctors = await CentralDataService.getAllDoctors();
      // جمع معرفات الأطباء المضافين مسبقاً في المركز (كل التخصصات)
      final existingDoctorIds = await _collectExistingCenterDoctorIds(widget.centerId);

      setState(() {
        _specializations = specializations;
        _allDoctors = allDoctors;
        _centerDoctorIds = existingDoctorIds;
        _availableDoctors = _allDoctors.where((d) => !_centerDoctorIds.contains(d['id'] as String)).toList();
        _isLoadingData = false;
      });
    } catch (e) {
      // Error loading data
      setState(() {
        _isLoadingData = false;
      });
    }
  }




  Future<Set<String>> _collectExistingCenterDoctorIds(String centerId) async {
    try {
      final Set<String> ids = {};
      final specsSnap = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(centerId)
          .collection('specializations')
          .get();
      for (final spec in specsSnap.docs) {
        final docsSnap = await FirebaseFirestore.instance
            .collection('medicalFacilities')
            .doc(centerId)
            .collection('specializations')
            .doc(spec.id)
            .collection('doctors')
            .get();
        for (final d in docsSnap.docs) {
          ids.add(d.id);
        }
      }
      return ids;
    } catch (e) {
      // Error collecting existing center doctor IDs
      return {};
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
      // إنشاء اسم فريد للصورة
      final fileName = 'doctors/${DateTime.now().millisecondsSinceEpoch}_${path.basename(_selectedImageFile!.path)}';
      
      // رفع الصورة إلى Firebase Storage
      final storageRef = FirebaseStorage.instance.ref().child(fileName);
      final uploadTask = storageRef.putFile(_selectedImageFile!);
      
      // انتظار اكتمال الرفع
      final snapshot = await uploadTask;
      
      // الحصول على رابط التحميل
      final downloadUrl = await snapshot.ref.getDownloadURL();
      
      setState(() {
        _selectedPhotoUrl = downloadUrl;
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

  Future<void> _populateFromDoctor(Map<String, dynamic> doctor) async {
    final String specId = doctor['specialization'] as String? ?? '';
    String specName = '';
    try {
      if (specId.isNotEmpty) {
        final doc = await FirebaseFirestore.instance.collection('medicalSpecialties').doc(specId).get();
        if (doc.exists) {
          specName = (doc.data()?['name'] as String?) ?? '';
        }
      }
    } catch (_) {}

    setState(() {
      _selectedDoctor = doctor['id'] as String?;
      _selectedDoctorPhone = (doctor['phoneNumber'] as String?) ?? '';
      _selectedSpecialization = specId.isNotEmpty ? specId : null;
      _selectedDoctorSpecName = specName;
    });

    // تأكد من وجود التخصص في المركز
    if (specId.isNotEmpty) {
      final centerSpecRef = FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .doc(specId);
      final exists = await centerSpecRef.get();
      if (!exists.exists) {
        await centerSpecRef.set({
          'specName': specName.isNotEmpty ? specName : specId,
          'isActive': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
        // أعد تحميل قائمة التخصصات المحلية لعرض الاسم مباشرة
        final specializationsSnapshot = await FirebaseFirestore.instance
            .collection('medicalFacilities')
            .doc(widget.centerId)
            .collection('specializations')
            .get();
        setState(() {
          _specializations = specializationsSnapshot.docs.map((doc) {
            final data = doc.data();
            return {
              'id': doc.id,
              'name': data['specName'] ?? doc.id,
            };
          }).toList();
        });
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

  Future<void> _addDoctor() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedSpecialization == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('يرجى اختيار التخصص'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_selectedDoctor == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('يرجى اختيار الطبيب'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // إضافة الطبيب إلى التخصص المحدد
      await CentralDataService.addDoctorToCenter(
        widget.centerId,
        _selectedSpecialization!,
        _selectedDoctor!,
        {
          'morningPatientLimit': int.tryParse(_morningLimitController.text) ?? 20,
          'eveningPatientLimit': int.tryParse(_eveningLimitController.text) ?? 20,
          'photoUrl': _selectedPhotoUrl,
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم إضافة الطبيب بنجاح'),
            backgroundColor: Colors.green,
          ),
        );

        Navigator.of(context).pop(true); // إرجاع true للإشارة إلى النجاح
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ في إضافة الطبيب: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingData) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.centerName != null ? 'إضافة طبيب - ${widget.centerName}' : 'إضافة طبيب',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF2FBDAF),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Profile image section
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
                              color: const Color(0xFF2FBDAF),
                              width: 3,
                            ),
                          ),
                          child: ClipOval(
                            child: _isUploadingImage
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : Image.network(
                                    _selectedPhotoUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        color: Colors.grey[300],
                                        child: const Icon(
                                          Icons.person,
                                          size: 60,
                                          color: Colors.grey,
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _showImageSourceDialog,
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('تغيير الصورة'),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF2FBDAF),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Form fields
                Container(
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
                        'معلومات الطبيب',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Doctor searchable picker (first)
                      TextFormField(
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: 'اختر الطبيب',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: const Icon(Icons.person),
                          suffixIcon: const Icon(Icons.arrow_drop_down),
                        ),
                        controller: TextEditingController(
                          text: _selectedDoctor == null
                              ? ''
                              : (_availableDoctors.firstWhere(
                                      (d) => d['id'] == _selectedDoctor,
                                      orElse: () => {'name': ''})['name'] as String? ?? ''),
                        ),
                        onTap: _showDoctorPickerDialog,
                        validator: (_) => _selectedDoctor == null ? 'يرجى اختيار الطبيب' : null,
                      ),
                      const SizedBox(height: 16),

                      // Specialization (auto-filled)
                      TextFormField(
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: 'التخصص',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: const Icon(Icons.medical_services),
                        ),
                        controller: TextEditingController(
                          text: _selectedDoctorSpecName,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Phone (auto-filled)
                      TextFormField(
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: 'رقم الهاتف',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: const Icon(Icons.phone),
                        ),
                        controller: TextEditingController(
                          text: _selectedDoctorPhone,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Morning patient limit
                      TextFormField(
                        controller: _morningLimitController,
                        decoration: InputDecoration(
                          labelText: 'الحد الأقصى للمرضى في الفترة الصباحية',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: Icon(Icons.wb_sunny),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'يرجى إدخال الحد الأقصى';
                          }
                          final number = int.tryParse(value);
                          if (number == null || number <= 0) {
                            return 'يرجى إدخال رقم صحيح موجب';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Evening patient limit
                      TextFormField(
                        controller: _eveningLimitController,
                        decoration: InputDecoration(
                          labelText: 'الحد الأقصى للمرضى في الفترة المسائية',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: Icon(Icons.nightlight),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'يرجى إدخال الحد الأقصى';
                          }
                          final number = int.tryParse(value);
                          if (number == null || number <= 0) {
                            return 'يرجى إدخال رقم صحيح موجب';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),

                      // Add button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _addDoctor,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2FBDAF),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Text(
                                  'إضافة الطبيب',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
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
      ),
    );
  }
}
