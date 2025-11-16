import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hospital_admin_app/services/central_data_service.dart';

class CentralDoctorsScreen extends StatefulWidget {
  const CentralDoctorsScreen({super.key});

  @override
  State<CentralDoctorsScreen> createState() => _CentralDoctorsScreenState();
}

class _CentralDoctorsScreenState extends State<CentralDoctorsScreen> {
  String _searchQuery = '';
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'إدارة الأطباء',
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
                    hintText: 'البحث في الأطباء...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),
              // Doctors list
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('allDoctors')
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

                    final doctors = snapshot.data?.docs ?? [];
                    
                    // Filter doctors based on search query
                    final filteredDoctors = doctors.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final name = data['name']?.toString().toLowerCase() ?? '';
                      final specialization = data['specialization']?.toString().toLowerCase() ?? '';
                      final phone = data['phoneNumber']?.toString().toLowerCase() ?? '';
                      return name.contains(_searchQuery.toLowerCase()) ||
                             specialization.contains(_searchQuery.toLowerCase()) ||
                             phone.contains(_searchQuery.toLowerCase());
                    }).toList();

                    if (filteredDoctors.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _searchQuery.isEmpty ? Icons.people : Icons.search_off,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty 
                                  ? 'لا يوجد أطباء'
                                  : 'لم يتم العثور على أطباء يطابقون البحث',
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
                      itemCount: filteredDoctors.length,
                      itemBuilder: (context, index) {
                        final doc = filteredDoctors[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final name = data['name'] ?? 'طبيب غير معروف';
                        final specializationId = data['specialization'] ?? '';
                        final phone = data['phoneNumber'] ?? '';

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(10),
                            
                            title: Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (specializationId.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  FutureBuilder<DocumentSnapshot>(
                                    future: FirebaseFirestore.instance
                                        .collection('medicalSpecialties')
                                        .doc(specializationId)
                                        .get(),
                                    builder: (context, specSnapshot) {
                                      if (specSnapshot.hasData && specSnapshot.data!.exists) {
                                        final specData = specSnapshot.data!.data() as Map<String, dynamic>?;
                                        final specName = specData?['name'] ?? 'تخصص غير معروف';
                                        return Text('التخصص: $specName');
                                      }
                                      return const Text('التخصص: غير محدد');
                                    },
                                  ),
                                ],
                                if (phone.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.phone, size: 14),
                                      const SizedBox(width: 4),
                                      Text(phone),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _showEditDoctorDialog(
                                doc.id,
                                name,
                                specializationId,
                                phone,
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
          onPressed: () => _showAddDoctorDialog(),
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

  void _showSpecializationPickerDialog(Function(String?) onSelected) {
    String searchQuery = '';
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('اختر التخصص'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'بحث في التخصصات...',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => searchQuery = value),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: FutureBuilder<QuerySnapshot>(
                    future: FirebaseFirestore.instance
                        .collection('medicalSpecialties')
                        .get(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final specialties = snapshot.data?.docs ?? [];
                      
                      // Filter specialties based on search query
                      final filteredSpecialties = specialties.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final name = data['name']?.toString().toLowerCase() ?? '';
                        return name.contains(searchQuery.toLowerCase());
                      }).toList();

                      if (filteredSpecialties.isEmpty) {
                        return const Center(
                          child: Text('لا توجد تخصصات تطابق البحث'),
                        );
                      }

                      return ListView.builder(
                        itemCount: filteredSpecialties.length,
                        itemBuilder: (context, index) {
                          final doc = filteredSpecialties[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final name = data['name'] ?? 'تخصص غير معروف';
                          
                          return ListTile(
                            title: Text(name),
                            onTap: () {
                              onSelected(doc.id);
                              Navigator.of(context).pop();
                            },
                          );
                        },
                      );
                    },
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

  void _showAddDoctorDialog() {
  final nameController = TextEditingController();
  final phoneController = TextEditingController();

  String? selectedSpecializationId;
  String? selectedSubSpecializationId;
  List<QueryDocumentSnapshot>? subSpecialties;

  showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('إضافة طبيب جديد'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'اسم الطبيب',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // اختيار التخصص الرئيسي
              GestureDetector(
                onTap: () => _showSpecializationPickerDialog((value) async {
                  setDialogState(() {
                    selectedSpecializationId = value;
                    selectedSubSpecializationId = null;
                    subSpecialties = null;
                  });

                  // تحميل التخصصات الفرعية إن وجدت
                  final snap = await FirebaseFirestore.instance
                      .collection('medicalSpecialties')
                      .doc(value)
                      .collection('subSpecialties')
                      .get();

                  if (snap.docs.isNotEmpty) {
                    setDialogState(() {
                      subSpecialties = snap.docs;
                    });
                  }
                }),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: selectedSpecializationId == null
                            ? const Text('اختر التخصص', style: TextStyle(color: Colors.grey))
                            : FutureBuilder<DocumentSnapshot>(
                                future: FirebaseFirestore.instance
                                    .collection('medicalSpecialties')
                                    .doc(selectedSpecializationId)
                                    .get(),
                                builder: (context, snapshot) {
                                  if (!snapshot.hasData) return const Text("...");
                                  final data = snapshot.data!.data() as Map<String, dynamic>;
                                  return Text(data['name']);
                                },
                              ),
                      ),
                      const Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ),

              // اختيار التخصص الفرعي إذا وجد
              if (subSpecialties != null && subSpecialties!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("اختر التخصص الفرعي"),
                      const SizedBox(height: 8),
                      DropdownButton<String>(
                        isExpanded: true,
                        value: selectedSubSpecializationId,
                        hint: const Text("اختيار تخصص فرعي"),
                        items: subSpecialties!.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return DropdownMenuItem(
                            value: doc.id,
                            child: Text(data['name']),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setDialogState(() {
                            selectedSubSpecializationId = value;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),

              TextField(
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: 'رقم الهاتف',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isNotEmpty && selectedSpecializationId != null) {
                Navigator.pop(context);
                await _addDoctor(
                  nameController.text.trim(),
                  selectedSpecializationId!,
                  selectedSubSpecializationId,
                  phoneController.text.trim(),
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
    ),
  );
}

  void _showEditDoctorDialog(String id, String currentName, String currentSpecializationId, String currentPhone) {
  final nameController = TextEditingController(text: currentName);
  final phoneController = TextEditingController(text: currentPhone);

  String? selectedSpecializationId = currentSpecializationId;
  String? selectedSubSpecializationId;
  List<QueryDocumentSnapshot>? subSpecialties;

  // تحميل التخصصات الفرعية الحالية
  FirebaseFirestore.instance
      .collection('medicalSpecialties')
      .doc(currentSpecializationId)
      .collection('subSpecialties')
      .get()
      .then((snap) {
    if (snap.docs.isNotEmpty) {
      setState(() {
        subSpecialties = snap.docs;
      });
    }
  });

  showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('تعديل الطبيب'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'اسم الطبيب',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              GestureDetector(
                onTap: () => _showSpecializationPickerDialog((value) async {
                  setDialogState(() {
                    selectedSpecializationId = value;
                    selectedSubSpecializationId = null;
                    subSpecialties = null;
                  });

                  final snap = await FirebaseFirestore.instance
                      .collection('medicalSpecialties')
                      .doc(value)
                      .collection('subSpecialties')
                      .get();

                  if (snap.docs.isNotEmpty) {
                    setDialogState(() {
                      subSpecialties = snap.docs;
                    });
                  }
                }),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: FutureBuilder<DocumentSnapshot>(
                          future: FirebaseFirestore.instance
                              .collection('medicalSpecialties')
                              .doc(selectedSpecializationId)
                              .get(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) return const Text("...");
                            final data = snapshot.data!.data() as Map<String, dynamic>;
                            return Text(data['name']);
                          },
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ),

              if (subSpecialties != null && subSpecialties!.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButton<String>(
                  isExpanded: true,
                  value: selectedSubSpecializationId,
                  hint: const Text("اختيار تخصص فرعي"),
                  items: subSpecialties!.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return DropdownMenuItem(
                      value: doc.id,
                      child: Text(data['name']),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedSubSpecializationId = value;
                    });
                  },
                ),
              ],

              const SizedBox(height: 12),

              TextField(
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: 'رقم الهاتف',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isNotEmpty && selectedSpecializationId != null) {
                Navigator.pop(context);
                await _updateDoctor(
                  id,
                  nameController.text.trim(),
                  selectedSpecializationId!,
                  selectedSubSpecializationId,
                  phoneController.text.trim(),
                );
              }
            },
            child: const Text('تحديث'),
          ),
        ],
      ),
    ),
  );
}


  Future<void> _addDoctor(String name, String specializationId, String? subSpecializationId, String phone) async {
  setState(() {
    _isLoading = true;
  });

  try {
    final id = await _getNextNumericId('allDoctors');

    await FirebaseFirestore.instance
        .collection('allDoctors')
        .doc(id)
        .set({
      'id': int.tryParse(id) ?? id,
      'name': name,
      'specialization': specializationId,
      'subSpecialization': subSpecializationId ?? '',
      'phoneNumber': phone,
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم إضافة الطبيب "$name" بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في إضافة الطبيب: $e'),
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


  Future<void> _updateDoctor(String id, String name, String specializationId, String? subSpecializationId, String phone) async {
  setState(() {
    _isLoading = true;
  });

  try {
    await FirebaseFirestore.instance
        .collection('allDoctors')
        .doc(id)
        .update({
      'name': name,
      'specialization': specializationId,
      'subSpecialization': subSpecializationId ?? '',
      'phoneNumber': phone,
    });

    await CentralDataService.propagateDoctorUpdate(
      doctorId: id,
      name: name,
      phoneNumber: phone,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تحديث الطبيب "$name" بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في تحديث الطبيب: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  } finally {
    setState(() {
      _isLoading = false;
    });
  }
}}

