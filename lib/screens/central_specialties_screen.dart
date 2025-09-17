import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hospital_admin_app/services/central_data_service.dart';

class CentralSpecialtiesScreen extends StatefulWidget {
  const CentralSpecialtiesScreen({super.key});

  @override
  State<CentralSpecialtiesScreen> createState() => _CentralSpecialtiesScreenState();
}

class _CentralSpecialtiesScreenState extends State<CentralSpecialtiesScreen> {
  String _searchQuery = '';
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'إدارة التخصصات',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF0D47A1),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Search bar
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.grey[50],
                child: TextField(
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
              ),
              // Specialties list
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('medicalSpecialties')
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

                    final specialties = snapshot.data?.docs ?? [];
                    
                    // Filter specialties based on search query
                    final filteredSpecialties = specialties.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final name = data['name']?.toString().toLowerCase() ?? '';
                      final description = data['description']?.toString().toLowerCase() ?? '';
                      return name.contains(_searchQuery.toLowerCase()) ||
                             description.contains(_searchQuery.toLowerCase());
                    }).toList();

                    if (filteredSpecialties.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _searchQuery.isEmpty ? Icons.medical_services : Icons.search_off,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty 
                                  ? 'لا توجد تخصصات'
                                  : 'لم يتم العثور على تخصصات تطابق البحث',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredSpecialties.length,
                      itemBuilder: (context, index) {
                        final doc = filteredSpecialties[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final name = data['name'] ?? 'تخصص غير معروف';
                        final description = data['description'] ?? '';

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0D47A1).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.medical_services,
                                color: Color(0xFF0D47A1),
                              ),
                            ),
                            title: Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            subtitle: description.isNotEmpty
                                ? Text(description)
                                : null,
                            trailing: IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _showEditSpecialtyDialog(
                                doc.id,
                                name,
                                description,
                              ),
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
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showAddSpecialtyDialog(),
          backgroundColor: const Color(0xFF0D47A1),
          foregroundColor: Colors.white,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Future<String> _getNextNumericId(String collectionPath) async {
    final snapshot = await FirebaseFirestore.instance.collection(collectionPath).get();
    int maxId = 0;
    for (final doc in snapshot.docs) {
      int? idNum = int.tryParse(doc.id);
      if (idNum == null) {
        final data = doc.data() as Map<String, dynamic>;
        final dynamic fieldId = data['id'];
        if (fieldId is int) {
          idNum = fieldId;
        } else if (fieldId is String) {
          idNum = int.tryParse(fieldId);
        }
      }
      if (idNum != null && idNum > maxId) maxId = idNum;
    }
    return (maxId + 1).toString();
  }

  void _showAddSpecialtyDialog() {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة تخصص جديد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'اسم التخصص',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(
                labelText: 'وصف التخصص (اختياري)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isNotEmpty) {
                Navigator.pop(context);
                await _addSpecialty(
                  nameController.text.trim(),
                  descriptionController.text.trim(),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D47A1),
              foregroundColor: Colors.white,
            ),
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
  }

  void _showEditSpecialtyDialog(String id, String currentName, String currentDescription) {
    final nameController = TextEditingController(text: currentName);
    final descriptionController = TextEditingController(text: currentDescription);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تعديل التخصص'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'اسم التخصص',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(
                labelText: 'وصف التخصص (اختياري)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isNotEmpty) {
                Navigator.pop(context);
                await _updateSpecialty(
                  id,
                  nameController.text.trim(),
                  descriptionController.text.trim(),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D47A1),
              foregroundColor: Colors.white,
            ),
            child: const Text('تحديث'),
          ),
        ],
      ),
    );
  }

  Future<void> _addSpecialty(String name, String description) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Prevent duplicates (case-insensitive)
      final existingSnap = await FirebaseFirestore.instance
          .collection('medicalSpecialties')
          .get();
      final lower = name.trim().toLowerCase();
      final bool exists = existingSnap.docs.any((d) {
        final data = d.data() as Map<String, dynamic>;
        final existingName = (data['name']?.toString() ?? '').trim().toLowerCase();
        return existingName == lower;
      });

      if (exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('هذا التخصص موجود بالفعل'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final id = await _getNextNumericId('medicalSpecialties');
      
      await FirebaseFirestore.instance
          .collection('medicalSpecialties')
          .doc(id)
          .set({
        'id': int.tryParse(id) ?? id,
        'name': name,
        'description': description,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم إضافة التخصص "$name" بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في إضافة التخصص: $e'),
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

  Future<void> _updateSpecialty(String id, String name, String description) async {
    setState(() {
      _isLoading = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('medicalSpecialties')
          .doc(id)
          .update({
        'name': name,
        'description': description,
      });

      // مزامنة الاسم إلى جميع المراكز التي تستخدم هذا التخصص
      await CentralDataService.propagateSpecialtyUpdate(
        specialtyId: id,
        name: name,
        description: description,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تحديث التخصص "$name" بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحديث التخصص: $e'),
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
}
