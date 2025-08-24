import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hospital_admin_app/services/app_update_service.dart';
import 'package:hospital_admin_app/widgets/app_update_dialog.dart';

import 'package:hospital_admin_app/screens/central_specialties_screen.dart';
import 'package:hospital_admin_app/screens/central_doctors_screen.dart';
import 'package:hospital_admin_app/screens/central_insurance_screen.dart';
import 'package:hospital_admin_app/screens/dashboard_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:path/path.dart' as path;

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
  bool _isLoading = false;
  bool _isAddingCenter = false;
  bool _showAddForm = false;
  String? _editingCenterId;
  String _searchQuery = '';
  bool _showSearchField = false;
  
  // Image handling variables
  String _selectedImageUrl = '';
  File? _selectedImageFile;
  bool _isUploadingImage = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    final userType = prefs.getString('userType');
    
    if (!isLoggedIn || userType != 'control') {
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
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

  Future<void> _testUpdate() async {
    try {
      final updateInfo = await AppUpdateService.checkForUpdate();
      
      if (updateInfo != null) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AppUpdateDialog(updateInfo: updateInfo),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لا يوجد تحديث متاح حالياً'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في اختبار التحديث: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _updateExistingCentersOrder() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // جلب جميع المراكز الموجودة
      final snapshot = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .get();

      int order = 1;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        if (data['order'] == null) {
          // إضافة حقل order للمراكز التي لا تحتوي عليه
          await FirebaseFirestore.instance
              .collection('medicalFacilities')
              .doc(doc.id)
              .update({
            'order': order,
          });
          order++;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تحديث ترتيب ${order - 1} مركز بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحديث ترتيب المراكز: $e'),
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

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  Future<void> _addCenter() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isAddingCenter = true;
      });

      try {
        final centerData = {
          'name': _centerNameController.text.trim(),
          'address': _centerAddressController.text.trim(),
          'phone': _centerPhoneController.text.trim(),
          'order': int.tryParse(_centerOrderController.text.trim()) ?? 999,
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
        _centerOrderController.clear();
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

  Future<void> _editCenter(String centerId, Map<String, dynamic> centerData) async {
    setState(() {
      _editingCenterId = centerId;
      _centerNameController.text = centerData['name'] ?? '';
      _centerAddressController.text = centerData['address'] ?? '';
      _centerPhoneController.text = centerData['phone'] ?? '';
      _centerOrderController.text = (centerData['order'] ?? 999).toString();
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
        await FirebaseFirestore.instance
            .collection('medicalFacilities')
            .doc(_editingCenterId)
            .update({
          'name': _centerNameController.text.trim(),
          'address': _centerAddressController.text.trim(),
          'phone': _centerPhoneController.text.trim(),
          'order': int.tryParse(_centerOrderController.text.trim()) ?? 999,
          'imageUrl': _selectedImageUrl.isNotEmpty ? _selectedImageUrl : null,
        });

        _centerNameController.clear();
        _centerAddressController.clear();
        _centerPhoneController.clear();
        _centerOrderController.clear();
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
      _centerOrderController.clear();
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
      Navigator.push(  // تغيير من pushReplacement إلى push
        context,
        MaterialPageRoute(
          builder: (context) => DashboardScreen(
            centerId: centerId,
            centerName: centerName,
            fromControlPanel: true,  // إضافة هذا المعامل
          ),
        ),
      );
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
          backgroundColor: const Color(0xFF2FBDAF),
          elevation: 0,
          actions: [
            IconButton(
              onPressed: () => setState(() => _showAddForm = !_showAddForm),
              icon: Icon(
                _showAddForm ? Icons.close : Icons.add,
                color: Colors.white,
              ),
              tooltip: _showAddForm ? 'إغلاق النموذج' : 'إضافة مركز جديد',
            ),
            IconButton(
              onPressed: _testUpdate,
              icon: const Icon(Icons.system_update, color: Colors.white),
              tooltip: 'اختبار التحديث',
            ),
            IconButton(
              onPressed: _updateExistingCentersOrder,
              icon: const Icon(Icons.sort, color: Colors.white),
              tooltip: 'تحديث ترتيب المراكز',
            ),
            IconButton(
              onPressed: _logout,
              icon: const Icon(Icons.logout, color: Colors.white),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                
                // Central Data Management Section
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.storage,
                              color: const Color(0xFF2FBDAF),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'إدارة البيانات المركزية',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => _showSpecialtiesList(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: const Color(0xFF2FBDAF),
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  side: const BorderSide(
                                    color: Color(0xFF2FBDAF),
                                    width: 2,
                                  ),
                                  elevation: 2,
                                ),
                                child: const Text(
                                  'التخصصات',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => _showDoctorsList(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: const Color(0xFF2FBDAF),
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  side: const BorderSide(
                                    color: Color(0xFF2FBDAF),
                                    width: 2,
                                  ),
                                  elevation: 2,
                                ),
                                child: const Text(
                                  'الأطباء',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => _showInsuranceList(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: const Color(0xFF2FBDAF),
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  side: const BorderSide(
                                    color: Color(0xFF2FBDAF),
                                    width: 2,
                                  ),
                                  elevation: 2,
                                ),
                                child: const Text(
                                  'التأمين',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                
                // Add Center Section
                if (_showAddForm)
                  Card(
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
                                color: const Color(0xFF2FBDAF),
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
                                              color: const Color(0xFF2FBDAF),
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
                                          foregroundColor: const Color(0xFF2FBDAF),
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
                                          backgroundColor: const Color(0xFF2FBDAF),
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
                const SizedBox(height: 24),
                
                // Centers List Section
                if (!_showSearchField)
                  Row(
                    children: [
                      const Text(
                        'المراكز الطبية',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _showSearchField = true;
                          });
                        },
                        icon: const Icon(Icons.search),
                        tooltip: 'البحث في المراكز',
                      ),
                    ],
                  )
                else
                  TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'البحث باسم المركز...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            _showSearchField = false;
                            _searchQuery = '';
                            _searchController.clear();
                          });
                        },
                        icon: const Icon(Icons.close),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    autofocus: true,
                  ),
                const SizedBox(height: 12),
                Container(
                  height: 400,
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
                                  backgroundColor: const Color(0xFF2FBDAF),
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('إضافة مركز جديد'),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.builder(
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
                              leading: const Icon(Icons.business, color: Color(0xFF2FBDAF)),
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
                                        color: const Color(0xFF2FBDAF),
                                        size: 16,
                                      ),
                                      const SizedBox(width: 4),
                                                                              Text(
                                          'ترتيب: ${centerData['order'] ?? 999}',
                                          style: const TextStyle(
                                            color: const Color(0xFF2FBDAF),
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
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      PopupMenuItem<String>(
                                        value: 'edit',
                                        child: Row(
                                          children: [
                                            const Icon(Icons.edit, color: Color(0xFF2FBDAF), size: 20),
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
        ),
      ),
    );
  }
}
