import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hospital_admin_app/services/central_data_service.dart';

class AdminInsuranceCompaniesScreen extends StatefulWidget {
  final String centerId;
  final String? centerName;

  const AdminInsuranceCompaniesScreen({
    super.key,
    required this.centerId,
    this.centerName,
  });

  @override
  State<AdminInsuranceCompaniesScreen> createState() => _AdminInsuranceCompaniesScreenState();
}

class _AdminInsuranceCompaniesScreenState extends State<AdminInsuranceCompaniesScreen> {
  String _searchQuery = '';
  bool _isLoading = false;
  List<Map<String, dynamic>> _allInsuranceCompanies = [];
  List<Map<String, dynamic>> _availableInsuranceCompanies = [];
  List<Map<String, dynamic>> _centerInsuranceCompanies = [];
  bool _isLoadingData = true;

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
      // جلب جميع شركات التأمين من قاعدة البيانات المركزية
      final allInsuranceCompanies = await CentralDataService.getAllInsuranceCompanies();
      
      // جلب شركات التأمين الموجودة في المركز
      final centerInsuranceSnapshot = await FirebaseFirestore.instance
            .collection('medicalFacilities')
            .doc(widget.centerId)
            .collection('insuranceCompanies')
          .get()
          .timeout(const Duration(seconds: 8));

      final centerInsuranceCompanies = centerInsuranceSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name'] ?? doc.id,
          'description': data['description'] ?? '',
          'phone': data['phone'] ?? '',
          'isActive': data['isActive'] ?? true,
        };
      }).toList();

      setState(() {
        _allInsuranceCompanies = allInsuranceCompanies;
        _centerInsuranceCompanies = centerInsuranceCompanies;
        _updateAvailableInsuranceCompanies();
        _isLoadingData = false;
      });
    } catch (e) {
      print('خطأ في تحميل البيانات: $e');
      setState(() {
        _isLoadingData = false;
      });
    }
  }

  void _updateAvailableInsuranceCompanies() {
    // شركات التأمين المتاحة للإضافة (غير موجودة في المركز)
    final centerInsuranceIds = _centerInsuranceCompanies.map((insurance) => insurance['id']).toSet();
    _availableInsuranceCompanies = _allInsuranceCompanies
        .where((insurance) => !centerInsuranceIds.contains(insurance['id']))
        .toList();
  }

  Future<void> addInsuranceCompany(String insuranceId) async {
    setState(() {
      _isLoading = true;
    });

    try {
      await CentralDataService.addInsuranceCompanyToCenter(widget.centerId, insuranceId);
      
      // إعادة تحميل البيانات
      await _loadData();
      
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم إضافة شركة التأمين بنجاح'),
              backgroundColor: Colors.green,
            ),
          );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ في إضافة شركة التأمين: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> toggleInsuranceStatus(String insuranceId, bool currentStatus) async {
    setState(() {
      _isLoading = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('insuranceCompanies')
          .doc(insuranceId)
          .update({
        'isActive': !currentStatus,
      });

      // تحديث القائمة المحلية
      setState(() {
        final index = _centerInsuranceCompanies.indexWhere((insurance) => insurance['id'] == insuranceId);
        if (index != -1) {
          _centerInsuranceCompanies[index]['isActive'] = !currentStatus;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(!currentStatus ? 'تم تفعيل شركة التأمين' : 'تم تعطيل شركة التأمين'),
          backgroundColor: Colors.green,
        ),
      );
      } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
          content: Text('حدث خطأ في تحديث حالة شركة التأمين'),
              backgroundColor: Colors.red,
            ),
          );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> deleteInsuranceCompany(String insuranceId) async {
    setState(() {
      _isLoading = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('insuranceCompanies')
          .doc(insuranceId)
          .delete();

      // إعادة تحميل البيانات
      await _loadData();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حذف شركة التأمين بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ في حذف شركة التأمين: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showAddDialog() {
    if (_availableInsuranceCompanies.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد شركات تأمين متاحة للإضافة'),
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
        title: const Text('إضافة شركة تأمين جديدة'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'بحث عن شركة...',
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
                    children: _availableInsuranceCompanies
                        .where((c) => localQuery.isEmpty || (c['name'] as String).toLowerCase().contains(localQuery.toLowerCase()))
                        .map((c) => ListTile(
                              title: Text(c['name']),
                              onTap: () {
                                Navigator.of(context).pop();
                                addInsuranceCompany(c['id']);
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

  List<Map<String, dynamic>> filterInsuranceCompanies(List<Map<String, dynamic>> insuranceCompanies) {
    if (_searchQuery.isEmpty) return insuranceCompanies;
    
    return insuranceCompanies.where((insurance) {
      final name = insurance['name']?.toString().toLowerCase() ?? '';
      final description = insurance['description']?.toString().toLowerCase() ?? '';
      return name.contains(_searchQuery.toLowerCase()) ||
             description.contains(_searchQuery.toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingData) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final filteredCenterInsuranceCompanies = filterInsuranceCompanies(_centerInsuranceCompanies);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title:Column(children: [ Text(
            'إدارة شركات التأمين',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text('${widget.centerName}',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white,
            ),
            ),
          ]),
          centerTitle: true,
          backgroundColor: const Color(0xFF2FBDAF),
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              onPressed: _isLoading ? null : _showAddDialog,
              icon: const Icon(Icons.add),
              tooltip: 'إضافة شركة تأمين جديدة',
            ),
          ],
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
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'البحث في شركات التأمين...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  ],
                ),
              ),
              // Insurance companies list
              Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filteredCenterInsuranceCompanies.isEmpty
                      ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                                _searchQuery.isEmpty ? Icons.business_outlined : Icons.search_off,
                                size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                                _searchQuery.isEmpty
                                    ? 'لا توجد شركات تأمين في هذا المركز'
                                    : 'لم يتم العثور على شركات تأمين تطابق البحث',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                                ),
                              ),
                            const SizedBox(height: 8),
                            Text(
                                _searchQuery.isEmpty
                                    ? 'لم يتم العثور على أي شركات تأمين مسجلة'
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
                          itemCount: filteredCenterInsuranceCompanies.length,
                          itemBuilder: (context, index) {
                            final insurance = filteredCenterInsuranceCompanies[index];
                            final isActive = insurance['isActive'] ?? true;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                                leading: Text(
                                  '${index + 1}',
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                            title: Text(
                                  insurance['name'],
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                    color: isActive ? Colors.black : Colors.grey,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                    if (insurance['description']?.isNotEmpty == true)
                                      Text(
                                        insurance['description'],
                                        style: TextStyle(
                                          color: isActive ? Colors.grey[600] : Colors.grey,
                                          fontSize: 12,
                                        ),
                                      ),
                                    Text(
                                      isActive ? 'نشط' : 'غير نشط',
                                      style: TextStyle(
                                        color: isActive ? Colors.green : Colors.grey,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) async {
                                    switch (value) {
                                      case 'toggle':
                                        await toggleInsuranceStatus(insurance['id'], isActive);
                                        break;
                                      case 'delete':
                                        await deleteInsuranceCompany(insurance['id']);
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
