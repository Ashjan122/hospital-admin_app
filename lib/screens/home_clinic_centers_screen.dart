import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HomeClinicCentersScreen extends StatefulWidget {
  const HomeClinicCentersScreen({super.key});

  @override
  State<HomeClinicCentersScreen> createState() => _HomeClinicCentersScreenState();
}

class _HomeClinicCentersScreenState extends State<HomeClinicCentersScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _addCenterToHomeClinic(String centerId, String centerName, String? imageUrl) async {
    try {
      // التحقق من وجود المركز في العيادة المنزلية
      final existingDoc = await FirebaseFirestore.instance
          .collection('homeClinic')
          .where('centerId', isEqualTo: centerId)
          .get();

      if (existingDoc.docs.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('هذا المركز موجود بالفعل في العيادة المنزلية'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // إضافة المركز إلى العيادة المنزلية
      await FirebaseFirestore.instance.collection('homeClinic').add({
        'centerId': centerId,
        'centerName': centerName,
        'imageUrl': imageUrl,
        'addedAt': FieldValue.serverTimestamp(),
        'isActive': true,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إضافة المركز إلى العيادة المنزلية بنجاح'),
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
    }
  }

  Future<void> _removeCenterFromHomeClinic(String docId, String centerName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف "$centerName" من العيادة المنزلية؟'),
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
            .collection('homeClinic')
            .doc(docId)
            .delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم حذف المركز من العيادة المنزلية'),
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

  Future<void> _toggleCenterStatus(String docId, bool currentStatus) async {
    try {
      await FirebaseFirestore.instance
          .collection('homeClinic')
          .doc(docId)
          .update({
        'isActive': !currentStatus,
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

  void _showAddCenterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة مركز للعيادة المنزلية'),
        content: SizedBox(
          width: double.maxFinite,
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
                      const Icon(Icons.error, color: Colors.red, size: 48),
                      const SizedBox(height: 16),
                      const Text('خطأ في تحميل المراكز'),
                      const SizedBox(height: 8),
                      Text(
                        '${snapshot.error}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final allCenters = snapshot.data?.docs ?? [];
              
              // تصفية المراكز المفعلة فقط وترتيبها
              final centers = allCenters.where((center) {
                final data = center.data() as Map<String, dynamic>;
                return data['available'] == true;
              }).toList();
              
              // ترتيب المراكز حسب الحقل order
              centers.sort((a, b) {
                final aData = a.data() as Map<String, dynamic>;
                final bData = b.data() as Map<String, dynamic>;
                final aOrder = aData['order'] as int? ?? 999;
                final bOrder = bData['order'] as int? ?? 999;
                return aOrder.compareTo(bOrder);
              });
              
              if (centers.isEmpty) {
                return const Center(
                  child: Text('لا توجد مراكز متاحة'),
                );
              }

              return ListView.builder(
                itemCount: centers.length,
                itemBuilder: (context, index) {
                   final center = centers[index];
                   final centerData = center.data() as Map<String, dynamic>;
                   final centerId = center.id;
                   final centerName = centerData['name'] ?? '';
                   final imageUrl = centerData['imageUrl'];

                   return Card(
                     margin: const EdgeInsets.only(bottom: 8),
                     child: ListTile(
                       title: Text(
                         centerName,
                         style: const TextStyle(fontWeight: FontWeight.bold),
                       ),
                       onTap: () async {
                         Navigator.pop(context);
                         await _addCenterToHomeClinic(centerId, centerName, imageUrl);
                       },
                     ),
                   );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  List<QueryDocumentSnapshot> _filterHomeClinicCenters(List<QueryDocumentSnapshot> centers) {
    if (_searchQuery.isEmpty) return centers;
    
    return centers.where((center) {
      final data = center.data() as Map<String, dynamic>;
      final name = data['centerName']?.toString().toLowerCase() ?? '';
      final searchLower = _searchQuery.toLowerCase();
      
      return name.contains(searchLower);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'مراكز العيادة المنزلية',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF0D47A1),
          elevation: 0,
          centerTitle: true,
          actions: [
            IconButton(
              onPressed: _showAddCenterDialog,
              icon: const Icon(Icons.add, color: Colors.white),
              tooltip: 'إضافة مركز جديد',
            ),
          ],
        ),
        body: Column(
          children: [
            // شريط البحث
            Container(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'البحث في مراكز العيادة المنزلية...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              ),
            ),
            
            // قائمة مراكز العيادة المنزلية
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('homeClinic')
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
                  
                  // ترتيب المراكز حسب تاريخ الإضافة (الأحدث أولاً)
                  allCenters.sort((a, b) {
                    final aData = a.data() as Map<String, dynamic>;
                    final bData = b.data() as Map<String, dynamic>;
                    final aAddedAt = aData['addedAt'] as Timestamp?;
                    final bAddedAt = bData['addedAt'] as Timestamp?;
                    
                    if (aAddedAt == null && bAddedAt == null) return 0;
                    if (aAddedAt == null) return 1;
                    if (bAddedAt == null) return -1;
                    
                    return bAddedAt.compareTo(aAddedAt); // ترتيب تنازلي
                  });
                  
                  final centers = _filterHomeClinicCenters(allCenters);

                  if (centers.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.home_work, color: Colors.grey, size: 64),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isEmpty
                                ? 'لا توجد مراكز في العيادة المنزلية'
                                : 'لا توجد نتائج للبحث',
                            style: const TextStyle(fontSize: 18, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _searchQuery.isEmpty
                                ? 'قم بإضافة مراكز جديدة باستخدام زر الإضافة'
                                : 'جرب البحث بكلمات مختلفة',
                            style: const TextStyle(fontSize: 14, color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _showAddCenterDialog,
                            icon: const Icon(Icons.add),
                            label: const Text('إضافة مركز جديد'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0D47A1),
                              foregroundColor: Colors.white,
                            ),
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
                      final docId = center.id;
                      final centerName = centerData['centerName'] ?? '';
                      final imageUrl = centerData['imageUrl'];
                      final isActive = centerData['isActive'] ?? true;
                      final addedAt = centerData['addedAt'] as Timestamp?;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            radius: 30,
                            backgroundColor: const Color(0xFF0D47A1),
                            backgroundImage: imageUrl != null 
                                ? NetworkImage(imageUrl) 
                                : null,
                            child: imageUrl == null 
                                ? const Icon(Icons.business, color: Colors.white, size: 30)
                                : null,
                          ),
                          title: Text(
                            centerName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    isActive ? Icons.check_circle : Icons.cancel,
                                    color: isActive ? Colors.green : Colors.red,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isActive ? 'مفعل' : 'غير مفعل',
                                    style: TextStyle(
                                      color: isActive ? Colors.green : Colors.red,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              if (addedAt != null)
                                Text(
                                  'تم الإضافة: ${addedAt.toDate().toString().split(' ')[0]}',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                            ],
                          ),
                          trailing: PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert),
                            onSelected: (value) {
                              switch (value) {
                                case 'toggle':
                                  _toggleCenterStatus(docId, isActive);
                                  break;
                                case 'delete':
                                  _removeCenterFromHomeClinic(docId, centerName);
                                  break;
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem<String>(
                                value: 'toggle',
                                child: Row(
                                  children: [
                                    Icon(
                                      isActive ? Icons.block : Icons.check_circle,
                                      color: isActive ? Colors.orange : Colors.green,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(isActive ? 'إلغاء التفعيل' : 'تفعيل'),
                                  ],
                                ),
                              ),
                              PopupMenuItem<String>(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    const Icon(Icons.delete, color: Colors.red, size: 20),
                                    const SizedBox(width: 8),
                                    const Text('حذف من العيادة المنزلية'),
                                  ],
                                ),
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
