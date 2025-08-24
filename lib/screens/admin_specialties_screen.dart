import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:hospital_admin_app/widgets/optimized_loading_widget.dart';
import 'package:hospital_admin_app/services/central_data_service.dart';

class AdminSpecialtiesScreen extends StatefulWidget {
  final String centerId;
  final String? centerName;

  const AdminSpecialtiesScreen({
    super.key,
    required this.centerId,
    this.centerName,
  });

  @override
  State<AdminSpecialtiesScreen> createState() => _AdminSpecialtiesScreenState();
}

class _AdminSpecialtiesScreenState extends State<AdminSpecialtiesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isLoading = false;
  List<Map<String, dynamic>> _allSpecialties = [];
  List<Map<String, dynamic>> _availableSpecialties = [];
  List<Map<String, dynamic>> _centerSpecialties = [];
  bool _isLoadingData = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoadingData = true;
    });

    try {
      // جلب جميع التخصصات من قاعدة البيانات المركزية
      final allSpecialties = await CentralDataService.getAllSpecialties();
      
      // جلب التخصصات الموجودة في المركز
      final centerSpecialtiesSnapshot = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .get()
          .timeout(const Duration(seconds: 8));

      final centerSpecialties = centerSpecialtiesSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['specName'] ?? doc.id,
          'isActive': data['isActive'] ?? true,
        };
      }).toList();

      setState(() {
        _allSpecialties = allSpecialties;
        _centerSpecialties = centerSpecialties;
        _updateAvailableSpecialties();
        _isLoadingData = false;
      });
    } catch (e) {
      print('خطأ في تحميل البيانات: $e');
      setState(() {
        _isLoadingData = false;
      });
    }
  }

  void _updateAvailableSpecialties() {
    // التخصصات المتاحة للإضافة (غير موجودة في المركز)
    final centerSpecialtyIds = _centerSpecialties.map((spec) => spec['id']).toSet();
    _availableSpecialties = _allSpecialties
        .where((specialty) => !centerSpecialtyIds.contains(specialty['id']))
        .toList();
  }

  Future<void> addSpecialty(String specialtyId) async {
    setState(() {
      _isLoading = true;
    });

    try {
      await CentralDataService.addSpecialtyToCenter(widget.centerId, specialtyId);
      
      // إعادة تحميل البيانات
      await _loadData();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إضافة التخصص بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ في إضافة التخصص: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> toggleSpecialtyStatus(String specialtyId, bool currentStatus) async {
    setState(() {
      _isLoading = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .doc(specialtyId)
          .update({
        'isActive': !currentStatus,
      });

      // تحديث القائمة المحلية
      setState(() {
        final index = _centerSpecialties.indexWhere((spec) => spec['id'] == specialtyId);
        if (index != -1) {
          _centerSpecialties[index]['isActive'] = !currentStatus;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(!currentStatus ? 'تم تفعيل التخصص' : 'تم تعطيل التخصص'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ في تحديث حالة التخصص'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> deleteSpecialty(String specialtyId) async {
    setState(() {
      _isLoading = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .doc(specialtyId)
          .delete();

      // إعادة تحميل البيانات
      await _loadData();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حذف التخصص بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ في حذف التخصص: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showAddSpecialtyDialog() {
    if (_availableSpecialties.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد تخصصات متاحة للإضافة'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    String localQuery = '';
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('إضافة تخصص جديد'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'بحث عن تخصص...',
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
                    children: _availableSpecialties
                        .where((s) => localQuery.isEmpty || (s['name'] as String).toLowerCase().contains(localQuery.toLowerCase()))
                        .map((s) => ListTile(
                              title: Text(s['name']),
                              onTap: () {
                                Navigator.of(context).pop();
                                addSpecialty(s['id']);
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

  List<Map<String, dynamic>> filterSpecialties(List<Map<String, dynamic>> specialties) {
    if (_searchQuery.isEmpty) return specialties;
    
    return specialties.where((specialty) {
      final name = specialty['name']?.toString().toLowerCase() ?? '';
      return name.contains(_searchQuery.toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingData) {
      return const Scaffold(
        body: Center(child: OptimizedLoadingWidget()),
      );
    }

    final filteredCenterSpecialties = filterSpecialties(_centerSpecialties);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.centerName != null ? 'إدارة التخصصات - ${widget.centerName}' : 'إدارة التخصصات',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF2FBDAF),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: Column(
          children: [
            // Search and Add section
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey[50],
              child: Column(
                children: [
                  // Search bar
                  TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'البحث في التخصصات...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Add specialty button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _showAddSpecialtyDialog,
                      icon: const Icon(Icons.add),
                      label: Text(_isLoading ? 'جاري الإضافة...' : 'إضافة تخصص جديد'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2FBDAF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Specialties list
            Expanded(
              child: _isLoading
                  ? const Center(child: OptimizedLoadingWidget())
                  : filteredCenterSpecialties.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _searchQuery.isEmpty ? Icons.medical_services_outlined : Icons.search_off,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _searchQuery.isEmpty
                                    ? 'لا توجد تخصصات في هذا المركز'
                                    : 'لم يتم العثور على تخصصات تطابق البحث',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _searchQuery.isEmpty
                                    ? 'لم يتم العثور على أي تخصصات مسجلة'
                                    : 'جرب البحث بكلمات مختلفة',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: filteredCenterSpecialties.length,
                          itemBuilder: (context, index) {
                            final specialty = filteredCenterSpecialties[index];
                            final isActive = specialty['isActive'] ?? true;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: Icon(
                                  Icons.medical_services,
                                  color: isActive ? Colors.green : Colors.grey,
                                ),
                                title: Text(
                                  specialty['name'],
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isActive ? Colors.black : Colors.grey,
                                  ),
                                ),
                                subtitle: Text(
                                  isActive ? 'نشط' : 'غير نشط',
                                  style: TextStyle(
                                    color: isActive ? Colors.green : Colors.grey,
                                  ),
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) async {
                                    switch (value) {
                                      case 'toggle':
                                        await toggleSpecialtyStatus(specialty['id'], isActive);
                                        break;
                                      case 'delete':
                                        await deleteSpecialty(specialty['id']);
                                        break;
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    PopupMenuItem(
                                      value: 'toggle',
                                      child: Row(
                                        children: [
                                          Icon(
                                            isActive ? Icons.block : Icons.check_circle,
                                            color: isActive ? Colors.orange : Colors.green,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(isActive ? 'تعطيل' : 'تفعيل'),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete, color: Colors.red),
                                          SizedBox(width: 8),
                                          Text('حذف'),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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
