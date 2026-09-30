import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class AdminUserProfileScreen extends StatefulWidget {
  final String? userId;

  // يستخدمان عند إضافة مستخدم جديد
  final bool isNewUser;
  final String? centerId;
  final String? centerName;

  const AdminUserProfileScreen({
    super.key,
    this.userId,
    this.isNewUser = false,
    this.centerId,
    this.centerName,
  });

  @override
  State<AdminUserProfileScreen> createState() => _AdminUserProfileScreenState();
}

class _AdminUserProfileScreenState extends State<AdminUserProfileScreen> {
  // ============================================================
  // Controllers
  // ============================================================

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _photoUrlController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _doctorSearchController = TextEditingController();

  // ============================================================
  // Roles
  // ============================================================

  final List<String> _roles = const [
    'admin',
    'reception',
    'doctor',
    'callcenter',
  ];

  String _selectedRole = 'reception';
  bool _canConfirmBooking = true;
  bool _canCancelBooking = true;

  // ============================================================
  // Doctor
  // ============================================================

  String? _currentDoctorId;
  String? _currentDoctorName;

  String? _centerId;
  String? _centerName;

  String? _originalRole;
  String? _originalDoctorId;

  List<Map<String, dynamic>> _centerDoctors = [];
  List<Map<String, dynamic>> _filteredDoctors = [];

  // ============================================================
  // States
  // ============================================================

  bool _loading = true;
  bool _saving = false;
  bool _uploadingImage = false;
  bool _loadingDoctors = false;
  bool _showDoctorsList = false;
  bool _obscurePassword = true;

  File? _pickedImageFile;

  static const String _adminApi =
      'https://us-central1-hospitalapp-681f1.cloudfunctions.net/api';

  // ============================================================
  // Colors
  // ============================================================

  static const Color _primaryColor = Color.fromARGB(255, 34, 96, 129);
  static const Color _borderColor = Color(0xFFE0E0E0);

  // ============================================================
  // Init
  // ============================================================

  @override
  void initState() {
    super.initState();

    if (widget.isNewUser) {
      _centerId = widget.centerId;
      _centerName = widget.centerName;

      // نفس الوضع الافتراضي للإضافة القديمة
      _selectedRole = 'callcenter';

      _originalRole = null;
      _originalDoctorId = null;

      _loading = false;
    } else {
      _loadUser();
    }
  }

  // ============================================================
  // تحميل المستخدم
  // ============================================================

  Future<void> _loadUser() async {
    if (widget.userId == null) {
      setState(() {
        _loading = false;
      });
      return;
    }

    try {
      final doc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(widget.userId)
              .get();

      final data = doc.data();

      if (data != null) {
        _nameController.text = (data['userName'] ?? '').toString();
        _phoneController.text = (data['userPhone'] ?? '').toString();
        _emailController.text = (data['email'] ?? '').toString();
        _photoUrlController.text = (data['photoUrl'] ?? '').toString();

        final existingRole = (data['userType'] ?? 'reception').toString();

        _selectedRole =
            _roles.contains(existingRole) ? existingRole : 'reception';
        final permissions =
            data['permissions'] is Map
                ? Map<String, dynamic>.from(data['permissions'])
                : <String, dynamic>{};

        _canConfirmBooking = permissions['confirmBooking'] ?? true;
        _canCancelBooking = permissions['cancelBooking'] ?? true;

        _originalRole = _selectedRole;

        _currentDoctorId = data['doctorId']?.toString();
        _originalDoctorId = _currentDoctorId;
        _currentDoctorName = data['doctorName']?.toString();

        _centerId = data['centerId']?.toString();
        _centerName = data['facilityName']?.toString();

        if (_selectedRole == 'doctor') {
          await _loadCenterDoctors(_centerId);
        }
      }
    } catch (e) {
      debugPrint('Error loading user: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // ============================================================
  // تحميل أطباء المركز
  // ============================================================

  Future<void> _loadCenterDoctors(String? centerId) async {
    if (centerId == null || centerId.isEmpty) {
      return;
    }

    if (mounted) {
      setState(() {
        _loadingDoctors = true;
      });
    }

    try {
      final specializationsSnapshot =
          await FirebaseFirestore.instance
              .collection('medicalFacilities')
              .doc(centerId)
              .collection('specializations')
              .get();

      final List<Map<String, dynamic>> doctors = [];
      final Set<String> addedDoctorIds = {};

      for (final specDoc in specializationsSnapshot.docs) {
        final specializationData = specDoc.data();

        final specializationName = specializationData['specName'] ?? specDoc.id;

        final doctorsSnapshot =
            await FirebaseFirestore.instance
                .collection('medicalFacilities')
                .doc(centerId)
                .collection('specializations')
                .doc(specDoc.id)
                .collection('doctors')
                .where('isActive', isEqualTo: true)
                .get();

        for (final doctorDoc in doctorsSnapshot.docs) {
          if (addedDoctorIds.contains(doctorDoc.id)) {
            continue;
          }

          final doctorData = doctorDoc.data();

          doctors.add({
            'doctorId': doctorDoc.id,
            'doctorName': doctorData['docName']?.toString() ?? 'طبيب غير معروف',
            'specialization': specializationName.toString(),
            'specializationId': specDoc.id,
          });

          addedDoctorIds.add(doctorDoc.id);
        }
      }

      if (!mounted) return;

      setState(() {
        _centerDoctors = doctors;
        _filteredDoctors = doctors;
        _loadingDoctors = false;
      });
    } catch (e) {
      debugPrint('Error loading doctors: $e');

      if (!mounted) return;

      setState(() {
        _loadingDoctors = false;
      });
    }
  }

  // ============================================================
  // إنشاء مستخدم جديد
  // ============================================================

  Future<void> _createUser() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.length < 3) {
      _showError('يجب أن يكون الاسم 3 أحرف على الأقل');
      return;
    }

    if (!email.contains('@')) {
      _showError('أدخل بريد إلكتروني صحيح');
      return;
    }

    if (password.length < 6) {
      _showError('يجب أن تكون كلمة المرور 6 أحرف على الأقل');
      return;
    }

    if (_centerId == null || _centerId!.isEmpty) {
      _showError('لم يتم تحديد المركز');
      return;
    }

    if (_selectedRole == 'doctor' &&
        (_currentDoctorId == null || _currentDoctorId!.isEmpty)) {
      _showError('اختر الطبيب المرتبط بهذا المستخدم');
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      // ========================================================
      // 1. إنشاء Firebase Auth
      // ========================================================

      final response = await http.post(
        Uri.parse('$_adminApi/auth-users'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'displayName': name,
          'role': _selectedRole,
        }),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        String errorMessage = 'فشل إنشاء المستخدم';

        try {
          final errorData = jsonDecode(response.body);

          errorMessage = errorData['error']?.toString() ?? errorMessage;
        } catch (_) {}

        throw Exception(errorMessage);
      }

      // ========================================================
      // 2. قراءة UID
      // ========================================================

      final created = jsonDecode(response.body);
      final uid = created['uid']?.toString();

      if (uid == null || uid.isEmpty) {
        throw Exception('لم يتم إرجاع UID من الخادم');
      }

      // ========================================================
      // 3. حفظ المستخدم في Firestore
      // ========================================================

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'facilityId': _centerId,
        'facilityName': _centerName,

        'centerId': _centerId,

        'role': _selectedRole,
        'userType': _selectedRole,

        'email': email,

        'displayName': name,
        'userName': name,

        'userPhone': phone,
        'permissions': {
          'confirmBooking': _canConfirmBooking,
          'cancelBooking': _canCancelBooking,
        },

        'photoUrl': _photoUrlController.text.trim(),

        'createdAt': FieldValue.serverTimestamp(),

        if (_selectedRole == 'doctor') ...{
          'doctorId': _currentDoctorId,
          'doctorName': _currentDoctorName,
        },
      }, SetOptions(merge: true));

      // ========================================================
      // 4. اشتراك الطبيب في Topic
      // ========================================================

      if (_selectedRole == 'doctor' && (_currentDoctorId ?? '').isNotEmpty) {
        try {
          await FirebaseMessaging.instance.subscribeToTopic(
            'doctor_$_currentDoctorId',
          );
        } catch (e) {
          debugPrint('Error subscribing doctor topic: $e');
        }
      }

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      _showError('خطأ: ${e.toString().replaceAll('Exception: ', '')}');
    }
  }

  // ============================================================
  // حفظ التعديلات
  // ============================================================

  Future<void> _saveChanges() async {
    if (widget.userId == null) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final Map<String, dynamic> update = {
        'userName': _nameController.text.trim(),
        'userPhone': _phoneController.text.trim(),
        'photoUrl': _photoUrlController.text.trim(),
        'userType': _selectedRole,
        'role': _selectedRole,
        'permissions': {
          'confirmBooking': _canConfirmBooking,
          'cancelBooking': _canCancelBooking,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // الطبيب
      if (_selectedRole == 'doctor' &&
          _currentDoctorId != null &&
          _currentDoctorId!.isNotEmpty) {
        update['doctorId'] = _currentDoctorId;
        update['doctorName'] = _currentDoctorName;
      } else {
        update['doctorId'] = null;
        update['doctorName'] = null;
      }

      // كلمة المرور
      if (_passwordController.text.trim().isNotEmpty) {
        update['userPassword'] = _passwordController.text.trim();
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .update(update);

      // ========================================================
      // إدارة Topic الطبيب
      // ========================================================

      try {
        final messaging = FirebaseMessaging.instance;

        final String? newDoctorId = update['doctorId'] as String?;

        final bool wasDoctor =
            _originalRole == 'doctor' && (_originalDoctorId ?? '').isNotEmpty;

        final bool isDoctorNow =
            _selectedRole == 'doctor' && (newDoctorId ?? '').isNotEmpty;

        // كان طبيب وأصبح ليس طبيب
        if (wasDoctor && !isDoctorNow) {
          await messaging.unsubscribeFromTopic('doctor_$_originalDoctorId');
        }

        // ما زال طبيب أو أصبح طبيب
        if (isDoctorNow) {
          // تغيير الطبيب
          if (wasDoctor &&
              _originalDoctorId != null &&
              _originalDoctorId != newDoctorId) {
            await messaging.unsubscribeFromTopic('doctor_$_originalDoctorId');
          }

          await messaging.subscribeToTopic('doctor_$newDoctorId');
        }
      } catch (e) {
        debugPrint('Error managing doctor topic: $e');
      }

      if (!mounted) return;

      _originalRole = _selectedRole;
      _originalDoctorId = _currentDoctorId;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حفظ التغييرات بنجاح'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      _showError('فشل الحفظ: $e');
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  // ============================================================
  // اختيار الصورة
  // ============================================================

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();

      final XFile? picked = await picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1200,
      );

      if (picked == null) {
        return;
      }

      setState(() {
        _pickedImageFile = File(picked.path);
      });

      if (!widget.isNewUser) {
        await _uploadPickedImage();
      }
    } catch (e) {
      if (!mounted) return;

      _showError('فشل اختيار الصورة: $e');
    }
  }

  // ============================================================
  // رفع الصورة
  // ============================================================

  Future<void> _uploadPickedImage() async {
    if (_pickedImageFile == null || widget.userId == null) {
      return;
    }

    setState(() {
      _uploadingImage = true;
    });

    try {
      final path = 'users/${widget.userId}/profile.jpg';

      final ref = FirebaseStorage.instance.ref().child(path);

      await ref.putFile(_pickedImageFile!);

      final url = await ref.getDownloadURL();

      if (!mounted) return;

      setState(() {
        _photoUrlController.text = url;
      });
    } catch (e) {
      if (mounted) {
        _showError('فشل رفع الصورة: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploadingImage = false;
        });
      }
    }
  }

  // ============================================================
  // مصدر الصورة
  // ============================================================

  Future<void> _showImageSourceSheet() async {
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
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
          ),
        );
      },
    );
  }

  // ============================================================
  // البحث عن الأطباء
  // ============================================================

  void _filterDoctors(String query) {
    setState(() {
      if (query.trim().isEmpty) {
        _filteredDoctors = _centerDoctors;
        return;
      }

      final searchQuery = query.toLowerCase();

      _filteredDoctors =
          _centerDoctors.where((doctor) {
            final doctorName = doctor['doctorName'].toString().toLowerCase();

            final specialization =
                doctor['specialization'].toString().toLowerCase();

            return doctorName.contains(searchQuery) ||
                specialization.contains(searchQuery);
          }).toList();
    });
  }

  // ============================================================
  // رسالة خطأ
  // ============================================================

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  // ============================================================
  // Dispose
  // ============================================================

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _photoUrlController.dispose();
    _passwordController.dispose();
    _doctorSearchController.dispose();

    super.dispose();
  }

  // ============================================================
  // Build
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final bool isNew = widget.isNewUser;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F8FA),

        appBar: AppBar(
          elevation: 0,
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          title: Text(
            isNew
                ? 'إضافة مستخدم جديد'
                : (_nameController.text.isNotEmpty
                    ? _nameController.text
                    : 'ملف المستخدم'),
          ),
        ),

        body:
            _loading
                ? const Center(
                  child: CircularProgressIndicator(color: _primaryColor),
                )
                : SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ==================================================
                        // الصورة + اسم المركز
                        // ==================================================
                        Center(
                          child: Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              CircleAvatar(
                                radius: 44,
                                backgroundColor: Colors.grey[200],
                                backgroundImage:
                                    _pickedImageFile != null
                                        ? FileImage(_pickedImageFile!)
                                        : (_photoUrlController.text
                                                .trim()
                                                .isNotEmpty
                                            ? NetworkImage(
                                              _photoUrlController.text.trim(),
                                            )
                                            : null),
                                child:
                                    (_pickedImageFile == null &&
                                            _photoUrlController.text
                                                .trim()
                                                .isEmpty)
                                        ? const Icon(
                                          Icons.person,
                                          size: 42,
                                          color: Colors.grey,
                                        )
                                        : null,
                              ),

                              if (_uploadingImage)
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withAlpha(120),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                      ),
                                    ),
                                  ),
                                ),

                              Container(
                                width: 32,
                                height: 32,
                                decoration: const BoxDecoration(
                                  color: _primaryColor,
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(
                                    Icons.camera_alt,
                                    color: Colors.white,
                                    size: 17,
                                  ),
                                  onPressed:
                                      _uploadingImage
                                          ? null
                                          : _showImageSourceSheet,
                                ),
                              ),
                            ],
                          ),
                        ),

                        if (isNew && (_centerName ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Center(
                            child: Text(
                              _centerName!,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 14),

                        // ==================================================
                        // بيانات المستخدم
                        // ==================================================
                        _sectionCard(
                          title: 'بيانات المستخدم',
                          icon: Icons.person_outline,
                          child: Column(
                            children: [
                              _textField(
                                controller: _nameController,
                                label: 'الاسم',
                                icon: Icons.badge_outlined,
                                textInputAction: TextInputAction.next,
                              ),

                              const SizedBox(height: 10),

                              _textField(
                                controller: _phoneController,
                                label: 'رقم الهاتف',
                                icon: Icons.phone_outlined,
                                keyboardType: TextInputType.phone,
                                textInputAction: TextInputAction.next,
                              ),

                              const SizedBox(height: 10),

                              _textField(
                                controller: _emailController,
                                label: 'البريد الإلكتروني',
                                icon: Icons.email_outlined,
                                keyboardType: TextInputType.emailAddress,
                                readOnly: !isNew,
                              ),

                              const SizedBox(height: 10),

                              TextField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                decoration: InputDecoration(
                                  labelText:
                                      isNew
                                          ? 'كلمة المرور'
                                          : 'تغيير كلمة المرور (اختياري)',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 10),

                        // ==================================================
                        // نوع المستخدم
                        // ==================================================
                        _sectionCard(
                          title: 'الصلاحيات',
                          icon: Icons.admin_panel_settings_outlined,
                          child: Column(
                            children: [
                              DropdownButtonFormField<String>(
                                value: _selectedRole,
                                decoration: InputDecoration(
                                  labelText: 'نوع المستخدم',
                                  prefixIcon: const Icon(Icons.person_outline),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                ),
                                items:
                                    _roles
                                        .map(
                                          (role) => DropdownMenuItem<String>(
                                            value: role,
                                            child: Text(_roleLabel(role)),
                                          ),
                                        )
                                        .toList(),
                                onChanged:
                                    _saving
                                        ? null
                                        : (value) {
                                          if (value == null) {
                                            return;
                                          }

                                          setState(() {
                                            _selectedRole = value;

                                            if (value == 'doctor') {
                                              _loadCenterDoctors(_centerId);
                                            } else {
                                              _currentDoctorId = null;
                                              _currentDoctorName = null;
                                              _showDoctorsList = false;
                                              _doctorSearchController.clear();
                                            }
                                          });
                                        },
                              ),

                              // ==================================================
                              // الطبيب
                              // ==================================================
                              if (_selectedRole == 'doctor') ...[
                                const SizedBox(height: 10),

                                _buildDoctorSelector(),
                              ],
                              const SizedBox(height: 12),

                              Row(
                                children: [
                                  Expanded(
                                    child: CheckboxListTile(
                                      contentPadding: EdgeInsets.zero,
                                      dense: true,
                                      activeColor: Colors.green,
                                      visualDensity: const VisualDensity(
                                        horizontal: -4,
                                        vertical: -4,
                                      ),
                                      title: const Text(
                                        'تأكيد الحجز',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      value: _canConfirmBooking,
                                      controlAffinity:
                                          ListTileControlAffinity.leading,
                                      onChanged:
                                          _saving
                                              ? null
                                              : (value) {
                                                setState(() {
                                                  _canConfirmBooking =
                                                      value ?? false;
                                                });
                                              },
                                    ),
                                  ),

                                  Expanded(
                                    child: CheckboxListTile(
                                      contentPadding: EdgeInsets.zero,
                                      dense: true,
                                      activeColor: Colors.green,
                                      visualDensity: const VisualDensity(
                                        horizontal: -4,
                                        vertical: -4,
                                      ),
                                      title: const Text(
                                        'إلغاء الحجز',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      value: _canCancelBooking,
                                      controlAffinity:
                                          ListTileControlAffinity.leading,
                                      onChanged:
                                          _saving
                                              ? null
                                              : (value) {
                                                setState(() {
                                                  _canCancelBooking =
                                                      value ?? false;
                                                });
                                              },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 14),

                        // ==================================================
                        // زر الحفظ
                        // ==================================================
                        SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed:
                                _saving
                                    ? null
                                    : (isNew ? _createUser : _saveChanges),
                            icon:
                                _saving
                                    ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                    : Icon(
                                      isNew
                                          ? Icons.person_add_alt_1
                                          : Icons.save_outlined,
                                      color: Colors.white,
                                    ),
                            label: Text(
                              isNew ? 'إنشاء المستخدم' : 'حفظ التغييرات',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryColor,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
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

  // ============================================================
  // كرت القسم
  // ============================================================

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: Colors.grey[700]),
              const SizedBox(width: 7),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  // ============================================================
  // TextField موحد
  // ============================================================

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    bool readOnly = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      readOnly: readOnly,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon:
            readOnly
                ? const Icon(Icons.lock_outline, size: 18, color: Colors.grey)
                : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        filled: readOnly,
        fillColor: readOnly ? const Color(0xFFF5F5F5) : null,
      ),
    );
  }

  // ============================================================
  // اختيار الطبيب
  // ============================================================

  Widget _buildDoctorSelector() {
    if (_loadingDoctors) {
      return Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: _borderColor),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: _primaryColor,
          ),
        ),
      );
    }

    if (_centerDoctors.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withAlpha(15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red.withAlpha(50)),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.red, size: 20),
            SizedBox(width: 8),
            Text(
              'لا يوجد أطباء في هذا المركز',
              style: TextStyle(color: Colors.red),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        TextField(
          controller: _doctorSearchController,
          onTap: () {
            setState(() {
              _showDoctorsList = true;
            });
          },
          onChanged: _filterDoctors,
          decoration: InputDecoration(
            labelText: 'الطبيب المرتبط',
            hintText: _currentDoctorName ?? 'اختر الطبيب',
            prefixIcon: const Icon(Icons.medical_services_outlined),
            suffixIcon: IconButton(
              onPressed: () {
                setState(() {
                  _showDoctorsList = !_showDoctorsList;

                  if (!_showDoctorsList) {
                    _doctorSearchController.clear();
                  }
                });
              },
              icon: Icon(
                _showDoctorsList
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
              ),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
        ),

        if (_showDoctorsList) ...[
          const SizedBox(height: 6),

          Container(
            constraints: const BoxConstraints(maxHeight: 190),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: _borderColor),
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                _filteredDoctors.isEmpty
                    ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: Text('لا توجد نتائج', textAlign: TextAlign.center),
                    )
                    : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _filteredDoctors.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final doctor = _filteredDoctors[index];

                        final String doctorId = doctor['doctorId'].toString();

                        final String doctorName =
                            doctor['doctorName'].toString();

                        final String specialization =
                            doctor['specialization'].toString();

                        final bool isSelected = doctorId == _currentDoctorId;

                        return ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: _primaryColor.withAlpha(35),
                            child: const Icon(
                              Icons.person,
                              size: 19,
                              color: _primaryColor,
                            ),
                          ),
                          title: Text(
                            doctorName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            specialization,
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing:
                              isSelected
                                  ? const Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                    size: 20,
                                  )
                                  : null,
                          onTap: () {
                            setState(() {
                              _currentDoctorId = doctorId;
                              _currentDoctorName = doctorName;

                              _doctorSearchController.text = doctorName;

                              _showDoctorsList = false;
                            });
                          },
                        );
                      },
                    ),
          ),
        ],
      ],
    );
  }

  // ============================================================
  // أسماء أنواع المستخدمين
  // ============================================================

  String _roleLabel(String value) {
    switch (value) {
      case 'admin':
        return 'مدير';

      case 'reception':
        return 'موظف استقبال';

      case 'doctor':
        return 'طبيب';

      case 'callcenter':
        return 'Call Center';

      default:
        return 'موظف استقبال';
    }
  }
}
