import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:hospital_admin_app/screens/lab_dashboard_screen.dart';

class LabToLabScreen extends StatefulWidget {
  const LabToLabScreen({super.key});

  @override
  State<LabToLabScreen> createState() => _LabToLabScreenState();
}

class _LabToLabScreenState extends State<LabToLabScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _whatsAppController = TextEditingController();
  final TextEditingController _orderController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final FocusNode _nameFocus = FocusNode();
  final FocusNode _addressFocus = FocusNode();
  final FocusNode _phoneFocus = FocusNode();
  final FocusNode _whatsAppFocus = FocusNode();
  final FocusNode _orderFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  bool _showAddForm = false;
  bool _submitting = false;
  String? _editingLabId;
  String _selectedImageUrl = '';
  File? _selectedImageFile;
  bool _isUploadingImage = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _whatsAppController.dispose();
    _orderController.dispose();
    _passwordController.dispose();
    _nameFocus.dispose();
    _addressFocus.dispose();
    _phoneFocus.dispose();
    _whatsAppFocus.dispose();
    _orderFocus.dispose();
    _passwordFocus.dispose();
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
        await _uploadImage();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في اختيار الصورة: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _uploadImage() async {
    if (_selectedImageFile == null) return;
    setState(() => _isUploadingImage = true);
    try {
      final fileName = 'labs/${DateTime.now().millisecondsSinceEpoch}_${path.basename(_selectedImageFile!.path)}';
      final storageRef = FirebaseStorage.instance.ref().child(fileName);
      final snapshot = await storageRef.putFile(_selectedImageFile!);
      final downloadUrl = await snapshot.ref.getDownloadURL();
      setState(() {
        _selectedImageUrl = downloadUrl;
        _isUploadingImage = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم رفع الصورة بنجاح'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      setState(() => _isUploadingImage = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في رفع الصورة: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _addLab() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      // Determine next order (robust for string/int values)
      final snap = await FirebaseFirestore.instance
          .collection('labToLap')
          .orderBy('order', descending: true)
          .limit(1)
          .get();
      int nextOrder = 1;
      if (snap.docs.isNotEmpty) {
        final dynamic highest = snap.docs.first.data()['order'];
        if (highest is int) {
          nextOrder = highest + 1;
        } else {
          final parsed = int.tryParse('$highest');
          nextOrder = (parsed != null ? parsed : 0) + 1;
        }
      }
      await FirebaseFirestore.instance.collection('labToLap').add({
        'name': _nameController.text.trim(),
        'address': _addressController.text.trim(),
        'phone': _phoneController.text.trim(),
        'whatsApp': _whatsAppController.text.trim().isEmpty ? null : _whatsAppController.text.trim(),
        'password': '123456',
        'available': true,
        'order': nextOrder,
        'createdAt': FieldValue.serverTimestamp(),
      });
      _clearForm();
      if (mounted) {
        // أبقِ نموذج الإضافة مفتوحاً والحقول فارغة
        setState(() => _showAddForm = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إضافة المعمل بنجاح'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في إضافة المعمل: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _updateLab() async {
    if (_editingLabId == null) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      // Keep current order unless user edits it
      final currentDoc = await FirebaseFirestore.instance.collection('labToLap').doc(_editingLabId).get();
      final currentOrderDynamic = currentDoc.data()?['order'];
      int currentOrder = 999;
      if (currentOrderDynamic is int) {
        currentOrder = currentOrderDynamic;
      } else {
        currentOrder = int.tryParse('${currentOrderDynamic ?? ''}') ?? 999;
      }
      int newOrder = currentOrder;
      if (_orderController.text.trim().isNotEmpty) {
        final parsed = int.tryParse(_orderController.text.trim());
        if (parsed != null && parsed > 0) newOrder = parsed;
      }
      final currentImage = currentDoc.data()?['imageUrl'];
      await FirebaseFirestore.instance.collection('labToLap').doc(_editingLabId).update({
        'name': _nameController.text.trim(),
        'address': _addressController.text.trim(),
        'phone': _phoneController.text.trim(),
        'whatsApp': _whatsAppController.text.trim(),
        'password': _passwordController.text.trim(),
        'order': newOrder,
        'imageUrl': _selectedImageUrl.isNotEmpty ? _selectedImageUrl : currentImage,
      });
      _clearForm();
      if (mounted) {
        setState(() {
          _editingLabId = null;
          _showAddForm = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تحديث المعمل بنجاح'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحديث المعمل: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _clearForm() {
    _nameController.clear();
    _addressController.clear();
    _phoneController.clear();
    _whatsAppController.clear();
    _orderController.clear();
    _passwordController.clear();
    _selectedImageUrl = '';
    _selectedImageFile = null;
  }

  void _startEdit(String id, Map<String, dynamic> data) {
    setState(() {
      _editingLabId = id;
      _nameController.text = data['name']?.toString() ?? '';
      _addressController.text = data['address']?.toString() ?? '';
      _phoneController.text = data['phone']?.toString() ?? '';
      _whatsAppController.text = data['whatsApp']?.toString() ?? '';
      _passwordController.text = data['password']?.toString() ?? '';
      _showAddForm = true;
      _selectedImageUrl = data['imageUrl']?.toString() ?? '';
      _selectedImageFile = null;
      final dynamic ord = data['order'];
      _orderController.text = ord == null ? '' : '$ord';
    });
  }

  Future<void> _toggleAvailability(String id, bool available) async {
    try {
      await FirebaseFirestore.instance.collection('labToLap').doc(id).update({'available': !available});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(!available ? 'تم تفعيل المعمل' : 'تم إلغاء تفعيل المعمل'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحديث حالة المعمل: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  

  List<QueryDocumentSnapshot> _sortAndFilter(List<QueryDocumentSnapshot> docs) {
    final list = List<QueryDocumentSnapshot>.from(docs);
    list.sort((a, b) {
      try {
        final aData = a.data() as Map<String, dynamic>;
        final bData = b.data() as Map<String, dynamic>;
        final aAvail = aData['available'] as bool? ?? false;
        final bAvail = bData['available'] as bool? ?? false;
        if (aAvail != bAvail) return aAvail ? -1 : 1;
        final dynamic aOrderDyn = aData['order'];
        final dynamic bOrderDyn = bData['order'];
        final int aOrder = aOrderDyn is int ? aOrderDyn : int.tryParse('${aOrderDyn ?? ''}') ?? 999;
        final int bOrder = bOrderDyn is int ? bOrderDyn : int.tryParse('${bOrderDyn ?? ''}') ?? 999;
        return aOrder.compareTo(bOrder);
      } catch (_) {
        return 0;
      }
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المعامل', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF0D47A1),
          centerTitle: true,
          actions: [
            IconButton(
              onPressed: () {
                if (_showAddForm) {
                  // Close form
                  setState(() {
                    _showAddForm = false;
                    _editingLabId = null;
                  });
                  _clearForm();
                } else {
                  // Open add-only form
                  setState(() {
                    _editingLabId = null;
                    _showAddForm = true;
                  });
                  _clearForm();
                }
              },
              icon: Icon(_showAddForm ? Icons.close : Icons.add, color: Colors.white),
              tooltip: _showAddForm ? 'إغلاق النموذج' : 'إضافة معمل جديد',
            ),
          ],
        ),
        resizeToAvoidBottomInset: true,
        body: Column(
          children: [
            if (_showAddForm)
              Expanded(
                child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                child: Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(_editingLabId != null ? Icons.edit : Icons.add_business, color: const Color(0xFF0D47A1)),
                              const SizedBox(width: 8),
                              Text(
                                _editingLabId != null ? 'تعديل المعمل' : 'إضافة معمل جديد',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (_editingLabId != null) ...[
                            Center(
                              child: Column(
                                children: [
                                  Container(
                                    width: 120,
                                    height: 120,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: const Color(0xFF0D47A1), width: 3),
                                    ),
                                    child: ClipOval(
                                      child: _isUploadingImage
                                          ? const Center(child: CircularProgressIndicator())
                                          : _selectedImageUrl.isNotEmpty
                                              ? Image.network(
                                                  _selectedImageUrl,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error, stackTrace) {
                                                    return Icon(Icons.science, size: 48, color: Colors.grey[400]);
                                                  },
                                                )
                                              : Icon(Icons.science, size: 48, color: Colors.grey[400]),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextButton.icon(
                                    onPressed: () async {
                                      final source = await showDialog<ImageSource>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: const Text('اختر مصدر الصورة'),
                                          content: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              ListTile(
                                                leading: const Icon(Icons.camera_alt),
                                                title: const Text('الكاميرا'),
                                                onTap: () => Navigator.pop(context, ImageSource.camera),
                                              ),
                                              ListTile(
                                                leading: const Icon(Icons.photo_library),
                                                title: const Text('المعرض'),
                                                onTap: () => Navigator.pop(context, ImageSource.gallery),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                      if (source != null) {
                                        await _pickImage(source);
                                      }
                                    },
                                    icon: const Icon(Icons.camera_alt),
                                    label: const Text('اختيار صورة المعمل'),
                                    style: TextButton.styleFrom(foregroundColor: const Color(0xFF0D47A1)),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          TextFormField(
                            controller: _nameController,
                            focusNode: _nameFocus,
                            decoration: const InputDecoration(labelText: 'اسم المعمل', border: OutlineInputBorder()),
                            textInputAction: TextInputAction.next,
                            onFieldSubmitted: (_) { _nameFocus.unfocus(); _addressFocus.requestFocus(); },
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'يرجى إدخال اسم المعمل' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _addressController,
                            focusNode: _addressFocus,
                            decoration: const InputDecoration(labelText: 'عنوان المعمل', border: OutlineInputBorder()),
                            textInputAction: TextInputAction.next,
                            onFieldSubmitted: (_) { _addressFocus.unfocus(); _phoneFocus.requestFocus(); },
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'يرجى إدخال عنوان المعمل' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _phoneController,
                            focusNode: _phoneFocus,
                            decoration: const InputDecoration(labelText: 'رقم هاتف للاتصال', border: OutlineInputBorder()),
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.next,
                            onFieldSubmitted: (_) { _phoneFocus.unfocus(); _whatsAppFocus.requestFocus(); },
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'يرجى إدخال رقم الهاتف' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _whatsAppController,
                            focusNode: _whatsAppFocus,
                            decoration: const InputDecoration(labelText: 'رقم هاتف واتساب', border: OutlineInputBorder()),
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.done,
                             validator: (v) => null,
                          ),
                          // كلمة المرور لا تظهر في الواجهة (تحفظ افتراضياً 123456)
                           if (_editingLabId != null) ...[
                             const SizedBox(height: 12),
                             TextFormField(
                               controller: _orderController,
                               focusNode: _orderFocus,
                               decoration: const InputDecoration(
                                 labelText: 'ترتيب المعمل (رقم)',
                                 border: OutlineInputBorder(),
                                 hintText: '1 يظهر أولاً',
                               ),
                               keyboardType: TextInputType.number,
                               textInputAction: TextInputAction.done,
                               validator: (v) {
                                 if (v == null || v.trim().isEmpty) return 'يرجى إدخال ترتيب المعمل';
                                 final n = int.tryParse(v.trim());
                                 if (n == null || n <= 0) return 'يرجى إدخال رقم صحيح موجب';
                                 return null;
                               },
                             ),
                           ],
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _submitting ? null : (_editingLabId != null ? _updateLab : _addLab),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0D47A1),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                  child: _submitting
                                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                                      : Text(_editingLabId != null ? 'تحديث المعمل' : 'إضافة المعمل'),
                                ),
                              ),
                              if (_editingLabId != null) ...[
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () {
                                      setState(() {
                                        _editingLabId = null;
                                        _showAddForm = false;
                                      });
                                      _clearForm();
                                    },
                                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                                    child: const Text('إلغاء'),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              ),
            if (!_showAddForm)
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('labToLap').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('خطأ: ${snapshot.error}'));
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = _sortAndFilter(snapshot.data?.docs ?? []);
                  if (docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.science, size: 64, color: Colors.grey),
                          const SizedBox(height: 12),
                          const Text('لا توجد معامل مضافة بعد', style: TextStyle(color: Colors.grey)),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: () => setState(() => _showAddForm = true),
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D47A1), foregroundColor: Colors.white),
                            child: const Text('إضافة معمل جديد'),
                          ),
                        ],
                      ),
                    );
                  }
                   return ListView.builder(
                    itemCount: docs.length,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemBuilder: (context, index) {
                      final d = docs[index];
                      final data = d.data() as Map<String, dynamic>;
                      final name = data['name']?.toString() ?? '';
                      final address = data['address']?.toString() ?? '';
                      final phone = data['phone']?.toString() ?? '';
                      final whats = data['whatsApp']?.toString() ?? '';
                      final available = data['available'] as bool? ?? false;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => LabDashboardScreen(
                                  labId: d.id,
                                  labName: name,
                                ),
                              ),
                            );
                          },
                          leading: const Icon(Icons.science, color: Color(0xFF0D47A1)),
                          title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('العنوان: $address'),
                              Text('هاتف: $phone'),
                              Text('واتساب: $whats'),
                              Row(
                                children: [
                                  Icon(available ? Icons.check_circle : Icons.cancel, color: available ? Colors.green : Colors.red, size: 16),
                                  const SizedBox(width: 4),
                                  Text(available ? 'مفعل' : 'غير مفعل', style: TextStyle(color: available ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 16),
                                  const Icon(Icons.sort, size: 16, color: Color(0xFF0D47A1)),
                                  const SizedBox(width: 4),
                                  Text('ترتيب: ${data['order'] ?? 999}', style: const TextStyle(color: Color(0xFF0D47A1), fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ],
                          ),
                          trailing: PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert),
                            onSelected: (value) {
                              switch (value) {
                                case 'edit':
                                  _startEdit(d.id, data);
                                  break;
                                case 'toggle':
                                  _toggleAvailability(d.id, available);
                                  break;
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem<String>(
                                value: 'edit',
                                child: Row(children: const [Icon(Icons.edit, color: Color(0xFF0D47A1), size: 20), SizedBox(width: 8), Text('تعديل')]),
                              ),
                              PopupMenuItem<String>(
                                value: 'toggle',
                                child: Row(children: [
                                  Icon(available ? Icons.block : Icons.check_circle, color: available ? Colors.orange : Colors.green, size: 20),
                                  const SizedBox(width: 8),
                                  Text(available ? 'إلغاء التفعيل' : 'تفعيل'),
                                ]),
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


