import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class AdminUserProfileScreen extends StatefulWidget {
  final String userId;

  const AdminUserProfileScreen({super.key, required this.userId});

  @override
  State<AdminUserProfileScreen> createState() => _AdminUserProfileScreenState();
}

class _AdminUserProfileScreenState extends State<AdminUserProfileScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _photoUrlController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _doctorSearchController = TextEditingController();

  final List<String> _roles = const ['admin', 'reception', 'doctor'];
  String _selectedRole = 'reception';
  String? _currentDoctorId;
  String? _currentDoctorName;
  String? _centerId;
  String? _originalRole;
  String? _originalDoctorId;
  List<Map<String, dynamic>> _centerDoctors = [];
  List<Map<String, dynamic>> _filteredDoctors = [];
  bool _loading = true;
  bool _saving = false;
  bool _uploadingImage = false;
  bool _loadingDoctors = false;
  bool _showDoctorsList = false;
  File? _pickedImageFile;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(widget.userId).get();
      final data = doc.data();
      if (data != null) {
        _nameController.text = (data['userName'] ?? '').toString();
        _phoneController.text = (data['userPhone'] ?? '').toString();
        _photoUrlController.text = (data['photoUrl'] ?? '').toString();
        final String existingRole = (data['userType'] ?? 'reception').toString();
        _selectedRole = _roles.contains(existingRole) ? existingRole : 'reception';
        _originalRole = _selectedRole;
        
        // تحميل معلومات الطبيب إذا كان المستخدم من نوع طبيب
        _currentDoctorId = data['doctorId'];
        _originalDoctorId = _currentDoctorId;
        _currentDoctorName = data['doctorName'];
        _centerId = data['centerId'];
        
        // تحميل قائمة الأطباء في المركز إذا كان النوع طبيب
        if (_selectedRole == 'doctor') {
          await _loadCenterDoctors(_centerId);
        }
      }
    } catch (_) {
      // ignore, show generic error UI below
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadCenterDoctors(String? centerId) async {
    if (centerId == null) return;
    
    setState(() {
      _loadingDoctors = true;
    });
    
    try {
      final specializationsSnapshot = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(centerId)
          .collection('specializations')
          .get();

      List<Map<String, dynamic>> doctors = [];
      Set<String> addedDoctorIds = {};

      for (var specDoc in specializationsSnapshot.docs) {
        final specializationData = specDoc.data();
        final specializationName = specializationData['specName'] ?? specDoc.id;
        
        final doctorsSnapshot = await FirebaseFirestore.instance
            .collection('medicalFacilities')
            .doc(centerId)
            .collection('specializations')
            .doc(specDoc.id)
            .collection('doctors')
            .where('isActive', isEqualTo: true)
            .get();

        for (var doctorDoc in doctorsSnapshot.docs) {
          if (!addedDoctorIds.contains(doctorDoc.id)) {
            final doctorData = doctorDoc.data();
            final doctorName = doctorData['docName'] ?? 'طبيب غير معروف';
            
            doctors.add({
              'doctorId': doctorDoc.id,
              'doctorName': doctorName,
              'specialization': specializationName,
              'specializationId': specDoc.id,
            });
            addedDoctorIds.add(doctorDoc.id);
          }
        }
      }

      setState(() {
        _centerDoctors = doctors;
        _filteredDoctors = doctors;
        _loadingDoctors = false;
      });
    } catch (e) {
      print('Error loading doctors: $e');
      setState(() {
        _loadingDoctors = false;
      });
    }
  }

  Future<void> _saveChanges() async {
    setState(() => _saving = true);
    try {
      final Map<String, dynamic> update = {
        'userName': _nameController.text.trim(),
        'userPhone': _phoneController.text.trim(),
        'photoUrl': _photoUrlController.text.trim(),
        'userType': _selectedRole,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      
      // إضافة أو إزالة معرف الطبيب حسب نوع المستخدم
      if (_selectedRole == 'doctor' && _currentDoctorId != null) {
        update['doctorId'] = _currentDoctorId;
        update['doctorName'] = _currentDoctorName;
      } else {
        update['doctorId'] = null;
        update['doctorName'] = null;
      }
      
      if (_passwordController.text.trim().isNotEmpty) {
        update['userPassword'] = _passwordController.text.trim();
      }
      await FirebaseFirestore.instance.collection('users').doc(widget.userId).update(update);

      // إدارة الاشتراك في توبيك الطبيب بناءً على الدور
      try {
        final FirebaseMessaging messaging = FirebaseMessaging.instance;
        final String? newDoctorId = update['doctorId'] as String? ?? _currentDoctorId;
        final bool wasDoctor = _originalRole == 'doctor' && (_originalDoctorId ?? '').isNotEmpty;
        final bool isDoctorNow = _selectedRole == 'doctor' && (newDoctorId ?? '').isNotEmpty;

        if (wasDoctor && (!isDoctorNow)) {
          final topic = 'doctor_${_originalDoctorId}';
          await messaging.unsubscribeFromTopic(topic);
          print('Unsubscribed from topic after role change: $topic');
        }

        if (isDoctorNow) {
          if (wasDoctor && _originalDoctorId != null && _originalDoctorId != newDoctorId) {
            final oldTopic = 'doctor_${_originalDoctorId}';
            await messaging.unsubscribeFromTopic(oldTopic);
            print('Switched doctor, unsubscribed from: $oldTopic');
          }
          final newTopic = 'doctor_${newDoctorId}';
          await messaging.subscribeToTopic(newTopic);
          print('Subscribed to doctor topic: $newTopic');
        }
      } catch (e) {
        print('Error managing doctor topic subscription: $e');
      }
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ التغييرات بنجاح'), backgroundColor: Colors.green),
        );
        // حدث القيم الأصلية بعد الحفظ
        _originalRole = _selectedRole;
        _originalDoctorId = _currentDoctorId;
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الحفظ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(source: source, imageQuality: 85, maxWidth: 1200);
      if (picked == null) return;
      setState(() {
        _pickedImageFile = File(picked.path);
      });
      await _uploadPickedImage();
    } catch (e) {
      if (!mounted || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل اختيار الصورة: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _uploadPickedImage() async {
    if (_pickedImageFile == null) return;
    setState(() => _uploadingImage = true);
    try {
      final String path = 'users/${widget.userId}/profile.jpg';
      final ref = FirebaseStorage.instance.ref().child(path);
      await ref.putFile(_pickedImageFile!);
      final url = await ref.getDownloadURL();
      setState(() {
        _photoUrlController.text = url;
      });
    } catch (e) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل رفع الصورة: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  Future<void> _showImageSourceSheet() async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اختر مصدر الصورة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('الكاميرا'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('المعرض'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _photoUrlController.dispose();
    _passwordController.dispose();
    _doctorSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_nameController.text.isNotEmpty ? _nameController.text : 'ملف المستخدم'),
          backgroundColor: const Color(0xFF2FBDAF),
          foregroundColor: Colors.white,
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF2FBDAF)),
              )
            : SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            CircleAvatar(
                              radius: 48,
                              backgroundColor: Colors.grey[200],
                              backgroundImage: (_pickedImageFile != null)
                                  ? FileImage(_pickedImageFile!)
                                  : (_photoUrlController.text.trim().isNotEmpty)
                                      ? NetworkImage(_photoUrlController.text.trim()) as ImageProvider
                                      : null,
                              child: (_pickedImageFile == null && _photoUrlController.text.trim().isEmpty)
                                  ? const Icon(Icons.person, size: 48, color: Colors.grey)
                                  : null,
                            ),
                            if (_uploadingImage)
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
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: Color(0xFF2FBDAF),
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  icon: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                                  tooltip: 'تغيير الصورة',
                                  onPressed: _uploadingImage ? null : _showImageSourceSheet,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_uploadingImage)
                        const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2FBDAF))),
                      const SizedBox(height: 16),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'الاسم',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.badge),
                        ),
                      ),
                                             const SizedBox(height: 16),
                       TextField(
                         controller: _phoneController,
                         keyboardType: TextInputType.phone,
                         decoration: const InputDecoration(
                           labelText: 'رقم الهاتف',
                           border: OutlineInputBorder(),
                           prefixIcon: Icon(Icons.phone),
                         ),
                       ),
                       const SizedBox(height: 16),
                       TextField(
                         controller: _passwordController,
                         obscureText: true,
                         decoration: const InputDecoration(
                           labelText: 'تغيير كلمة المرور (اختياري)',
                           border: OutlineInputBorder(),
                           prefixIcon: Icon(Icons.lock_reset),
                         ),
                       ),
                       const SizedBox(height: 24),
                       // قسم إعدادات المستخدم
                       Container(
                         padding: const EdgeInsets.all(16),
                         decoration: BoxDecoration(
                           color: Colors.grey[50],
                           borderRadius: BorderRadius.circular(12),
                           border: Border.all(color: Colors.grey[300]!),
                         ),
                         child: Column(
                           crossAxisAlignment: CrossAxisAlignment.start,
                           children: [
                                                           Row(
                                children: [
                                  Icon(Icons.person, color: Colors.grey[600]),
                                  const SizedBox(width: 8),
                                  Text(
                                    'نوع المستخدم',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey[800],
                                    ),
                                  ),
                                ],
                              ),
                             const SizedBox(height: 16),
                             InputDecorator(
                               decoration: const InputDecoration(
                                 labelText: 'نوع المستخدم',
                                 border: OutlineInputBorder(),
                               ),
                               child: DropdownButtonHideUnderline(
                                 child: DropdownButton<String>(
                                   value: _selectedRole,
                                   isExpanded: true,
                                   items: _roles
                                       .map(
                                         (r) => DropdownMenuItem(
                                           value: r,
                                           child: Text(_roleLabel(r)),
                                         ),
                                       )
                                       .toList(),
                                   onChanged: (v) {
                                     if (v == null) return;
                                     setState(() {
                                       _selectedRole = v;
                                       if (v == 'doctor') {
                                         // تحميل الأطباء عند تغيير النوع إلى طبيب
                                         _loadCenterDoctors(_getCenterIdFromUser());
                                                                               } else {
                                          // إزالة معرف الطبيب عند تغيير النوع
                                          _currentDoctorId = null;
                                          _currentDoctorName = null;
                                          _showDoctorsList = false;
                                        }
                                     });
                                   },
                                 ),
                               ),
                             ),
                                                           // اختيار الطبيب إذا كان نوع المستخدم طبيب
                              if (_selectedRole == 'doctor') ...[
                                const SizedBox(height: 16),
                                if (_loadingDoctors)
                                  const Center(child: CircularProgressIndicator())
                                else if (_centerDoctors.isEmpty)
                                  const Text(
                                    'لا يوجد أطباء في هذا المركز',
                                    style: TextStyle(color: Colors.red),
                                  )
                                                                  else ...[
                                    // حقل اختيار الطبيب
                                    TextField(
                                      onTap: () {
                                        setState(() {
                                          _showDoctorsList = true;
                                          _doctorSearchController.text = ''; // مسح النص عند الضغط
                                        });
                                      },
                                      onChanged: _filterDoctors,
                                      controller: _doctorSearchController,
                                      decoration: InputDecoration(
                                        labelText: 'اختر طبيب',
                                        border: const OutlineInputBorder(),
                                        prefixIcon: const Icon(Icons.medical_services),
                                        suffixIcon: GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _showDoctorsList = !_showDoctorsList;
                                              if (!_showDoctorsList) {
                                                _doctorSearchController.clear();
                                              }
                                            });
                                          },
                                          child: Icon(
                                            _showDoctorsList ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                                          ),
                                        ),
                                        hintText: _showDoctorsList ? 'بحث...' : (_currentDoctorName ?? 'اختر طبيب'),
                                      ),
                                    ),
                                    // قائمة الأطباء
                                    if (_showDoctorsList) ...[
                                      const SizedBox(height: 8),
                                      Container(
                                        height: 200,
                                        decoration: BoxDecoration(
                                          border: Border.all(color: Colors.grey[300]!),
                                          borderRadius: BorderRadius.circular(8),
                                          color: Colors.white,
                                        ),
                                        child: ListView.builder(
                                          itemCount: _filteredDoctors.length,
                                          itemBuilder: (context, index) {
                                            final doctor = _filteredDoctors[index];
                                            final isSelected = doctor['doctorId'] == _currentDoctorId;
                                            
                                            return ListTile(
                                              title: Text(
                                                doctor['doctorName'] as String,
                                                style: const TextStyle(fontWeight: FontWeight.bold),
                                              ),
                                              subtitle: Text(doctor['specialization'] as String),
                                              selected: isSelected,
                                              selectedTileColor: const Color(0xFF2FBDAF).withOpacity(0.1),
                                                                                             onTap: () {
                                                 setState(() {
                                                   _currentDoctorId = doctor['doctorId'] as String;
                                                   _currentDoctorName = doctor['doctorName'] as String;
                                                   _showDoctorsList = false; // إخفاء القائمة بعد الاختيار
                                                   _doctorSearchController.clear(); // مسح النص في الحقل
                                                 });
                                               },
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ],
                               ],
                             ],
                           ),
                         ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _saving ? null : _saveChanges,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.save),
                          label: const Text('حفظ التغييرات'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2FBDAF),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  void _filterDoctors(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredDoctors = _centerDoctors;
      } else {
        _filteredDoctors = _centerDoctors.where((doctor) {
          final doctorName = doctor['doctorName'].toString().toLowerCase();
          final specialization = doctor['specialization'].toString().toLowerCase();
          final searchQuery = query.toLowerCase();
          return doctorName.contains(searchQuery) || 
                 specialization.contains(searchQuery);
        }).toList();
      }
    });
  }

  String? _getCenterIdFromUser() {
    // جلب معرف المركز من بيانات المستخدم المحفوظة
    // سنستخدم متغير محلي لتخزين معرف المركز
    return _centerId;
  }

  String _roleLabel(String value) {
    switch (value) {
      case 'admin':
        return 'مدير';
      case 'reception':
        return 'موظف استقبال';
      case 'doctor':
        return 'طبيب';
      default:
        return 'موظف استقبال';
    }
  }
}


