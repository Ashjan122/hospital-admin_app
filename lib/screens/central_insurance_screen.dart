import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hospital_admin_app/services/central_data_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

class CentralInsuranceScreen extends StatefulWidget {
  const CentralInsuranceScreen({super.key});

  @override
  State<CentralInsuranceScreen> createState() => _CentralInsuranceScreenState();
}

class _CentralInsuranceScreenState extends State<CentralInsuranceScreen> {
  String _searchQuery = '';
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'إدارة شركات التأمين',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
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
                  onChanged: (value) => setState(() => _searchQuery = value),
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
              ),
              // Insurance companies list
              Expanded(
  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance
        .collection('insuranceCompanies')
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

      final companies = snapshot.data?.docs ?? [];

      // Filter by search query only, لا نحذف المعطلة
      final filteredCompanies = companies.where((doc) {
        final data = doc.data();
        final name = (data['name']?.toString() ?? '').toLowerCase();
        final description = (data['description']?.toString() ?? '').toLowerCase();
        final phone = (data['phone']?.toString() ?? '').toLowerCase();

        return name.contains(_searchQuery.toLowerCase()) ||
            description.contains(_searchQuery.toLowerCase()) ||
            phone.contains(_searchQuery.toLowerCase());
      }).toList();

      if (filteredCompanies.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _searchQuery.isEmpty ? Icons.business : Icons.search_off,
                size: 64,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                _searchQuery.isEmpty
                    ? 'لا توجد شركات تأمين'
                    : 'لم يتم العثور على شركات تأمين تطابق البحث',
                style: TextStyle(fontSize: 18, color: Colors.grey[600]),
              ),
            ],
          ),
        );
      }

      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: filteredCompanies.length,
        itemBuilder: (context, index) {
          final doc = filteredCompanies[index];
          final data = doc.data();
          final name = data['name'] ?? 'شركة غير معروفة';
          final description = data['description'] ?? '';
          final phone = data['phone'] ?? '';
          final imageUrl = data['imageUrl'] ?? '';
          final enabled = data['enabled'] ?? true;

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.all(10),
              leading: imageUrl.isNotEmpty
                  ? CircleAvatar(
                      radius: 24,
                      backgroundImage: NetworkImage(imageUrl),
                    )
                  : CircleAvatar(
                      radius: 24,
                      child: Text(name[0]),
                    ),
              title: Text(
                name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: enabled ? Colors.black : Colors.grey,
                ),
              ),
             
              trailing: PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') {
                    _showEditInsuranceDialog(doc.id, name, description, phone, imageUrl);
                  } else if (value == 'toggle') {
                    _toggleInsuranceCompany(doc.id, enabled);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('تعديل')),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(enabled ? 'تعطيل' : 'تفعيل'),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  ),
)

            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _showAddInsuranceDialog,
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
        final fieldId = data['id'];
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

  void _showAddInsuranceDialog() {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final phoneController = TextEditingController();
    String? imageUrl;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('إضافة شركة تأمين جديدة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () async {
                    final url = await _pickAndUploadImage();
                    if (url != null) setDialogState(() => imageUrl = url);
                  },
                  child: CircleAvatar(
                    radius: 40,
                    backgroundImage:
                        imageUrl != null ? NetworkImage(imageUrl!) : null,
                    child: imageUrl == null ? const Icon(Icons.camera_alt, size: 40) : null,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                        labelText: 'اسم الشركة', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(
                        labelText: 'وصف الشركة (اختياري)',
                        border: OutlineInputBorder()),
                    maxLines: 2),
                const SizedBox(height: 12),
                TextField(
                    controller: phoneController,
                    decoration: const InputDecoration(
                        labelText: 'رقم الهاتف (اختياري)',
                        border: OutlineInputBorder()),
                    keyboardType: TextInputType.phone),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isNotEmpty) {
                  Navigator.pop(context);
                  await _addInsuranceCompany(
                      nameController.text.trim(),
                      descriptionController.text.trim(),
                      phoneController.text.trim(),
                      imageUrl);
                }
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D47A1),
                  foregroundColor: Colors.white),
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
  }
  Future<void> _toggleInsuranceCompany(String id, bool currentStatus) async {
  try {
    await FirebaseFirestore.instance.collection('insuranceCompanies').doc(id).update({
      'enabled': !currentStatus,
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(currentStatus ? 'تم تعطيل الشركة' : 'تم تفعيل الشركة'),
          backgroundColor: currentStatus ? Colors.orange : Colors.green,
        ),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
      );
    }
  }
}


  void _showEditInsuranceDialog(
      String id, String currentName, String currentDescription, String currentPhone, String? currentImageUrl) {
    final nameController = TextEditingController(text: currentName);
    final descriptionController = TextEditingController(text: currentDescription);
    final phoneController = TextEditingController(text: currentPhone);
    String? imageUrl = currentImageUrl;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('تعديل شركة التأمين'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () async {
                    final url = await _pickAndUploadImage();
                    if (url != null) setDialogState(() => imageUrl = url);
                  },
                  child: CircleAvatar(
                    radius: 40,
                    backgroundImage:
                        imageUrl != null && imageUrl!.isNotEmpty ? NetworkImage(imageUrl!) : null,
                    child: imageUrl == null || imageUrl!.isEmpty
                        ? const Icon(Icons.camera_alt, size: 40)
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                        labelText: 'اسم الشركة', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(
                        labelText: 'وصف الشركة (اختياري)', border: OutlineInputBorder()),
                    maxLines: 2),
                const SizedBox(height: 12),
                TextField(
                    controller: phoneController,
                    decoration: const InputDecoration(
                        labelText: 'رقم الهاتف (اختياري)', border: OutlineInputBorder()),
                    keyboardType: TextInputType.phone),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isNotEmpty) {
                  Navigator.pop(context);
                  await _updateInsuranceCompany(
                      id,
                      nameController.text.trim(),
                      descriptionController.text.trim(),
                      phoneController.text.trim(),
                      imageUrl);
                }
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D47A1),
                  foregroundColor: Colors.white),
              child: const Text('تحديث'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addInsuranceCompany(
      String name, String description, String phone, String? imageUrl) async {
    setState(() => _isLoading = true);
    try {
      final id = await _getNextNumericId('insuranceCompanies');
      await FirebaseFirestore.instance.collection('insuranceCompanies').doc(id).set({
        'id': int.tryParse(id) ?? id,
        'name': name,
        'description': description,
        'phone': phone,
        'imageUrl': imageUrl ?? '',
        'enabled': true,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('تم إضافة شركة التأمين "$name" بنجاح'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateInsuranceCompany(
      String id, String name, String description, String phone, String? imageUrl) async {
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('insuranceCompanies').doc(id).update({
        'name': name,
        'description': description,
        'phone': phone,
        'imageUrl': imageUrl ?? '',
      });

      await CentralDataService.propagateInsuranceUpdate(
          insuranceId: id, name: name, description: description, phone: phone, imageUrl: imageUrl);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('تم تحديث شركة التأمين "$name" بنجاح'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في التحديث: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _disableInsuranceCompany(String id) async {
    try {
      await FirebaseFirestore.instance.collection('insuranceCompanies').doc(id).update({
        'enabled': false,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تعطيل شركة التأمين'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في التعطيل: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<String?> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (pickedFile == null) return null;

    final file = await pickedFile.readAsBytes();
    final storageRef = FirebaseStorage.instance
        .ref()
        .child('insurance_images/${DateTime.now().millisecondsSinceEpoch}.jpg');

    await storageRef.putData(file);
    return await storageRef.getDownloadURL();
  }
}
