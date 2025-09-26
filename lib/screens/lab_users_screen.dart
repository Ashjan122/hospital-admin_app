import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class LabUsersScreen extends StatefulWidget {
  final String labId;
  final String labName;
  const LabUsersScreen({super.key, required this.labId, required this.labName});

  @override
  State<LabUsersScreen> createState() => _LabUsersScreenState();
}

class _LabUsersScreenState extends State<LabUsersScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _submitting = false;

  CollectionReference<Map<String, dynamic>> get _labUsersCol => FirebaseFirestore.instance
      .collection('labToLap')
      .doc(widget.labId)
      .collection('users');

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _openAddUserSheet() {
    _nameController.clear();
    _phoneController.clear();
    _passwordController.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: const [Icon(Icons.person_add, color: Color(0xFF0D47A1)), SizedBox(width: 8), Text('إضافة مستخدم جديد', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))]),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'اسم المستخدم', border: OutlineInputBorder()),
                    textInputAction: TextInputAction.next,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'أدخل الاسم' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(labelText: 'رقم الهاتف', border: OutlineInputBorder()),
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'أدخل الهاتف' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(labelText: 'كلمة المرور', border: OutlineInputBorder()),
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'أدخل كلمة المرور' : null,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : () async { await _addUser(); if (mounted) Navigator.pop(context); },
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D47A1), foregroundColor: Colors.white),
                      child: _submitting
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                          : const Text('إضافة'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _addUser() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final name = _nameController.text.trim();
      final phone = _phoneController.text.trim();
      final password = _passwordController.text.trim();

      // Create user doc in global users collection
      final userDoc = await FirebaseFirestore.instance.collection('users').add({
        'userName': name,
        'userPhone': phone,
        'userPassword': password,
        'userType': 'labUser',
        'labId': widget.labId,
        'labName': widget.labName,
        'createdAt': FieldValue.serverTimestamp(),
        'lastLoginAt': null,
        'lastSeenAt': null,
      });

      // Also add to lab subcollection for quick management
      await _labUsersCol.doc(userDoc.id).set({
        'userName': name,
        'userPhone': phone,
        'userType': 'labUser',
        'userId': userDoc.id,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        _nameController.clear();
        _phoneController.clear();
        _passwordController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تمت إضافة المستخدم'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _editUser(String userId) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final name = _nameController.text.trim();
      final phone = _phoneController.text.trim();
      final password = _passwordController.text.trim();

      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'userName': name,
        'userPhone': phone,
        'userPassword': password,
        'userType': 'labUser',
        'labId': widget.labId,
        'labName': widget.labName,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _labUsersCol.doc(userId).set({
        'userName': name,
        'userPhone': phone,
        'userType': 'labUser',
        'userId': userId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تحديث المستخدم'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _deleteUser(String userId, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل تريد حذف المستخدم "$name"؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف'), style: TextButton.styleFrom(foregroundColor: Colors.red)),
        ],
      ),
    );
    if (ok == true) {
      try {
        await _labUsersCol.doc(userId).delete();
        await FirebaseFirestore.instance.collection('users').doc(userId).delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم حذف المستخدم'), backgroundColor: Colors.green),
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
  }

  void _openEditUserSheet(String userId, Map<String, dynamic> data) {
    _nameController.text = data['userName']?.toString() ?? '';
    _phoneController.text = data['userPhone']?.toString() ?? '';
    // password from global users; leave empty to avoid showing hash; require new one or keep?
    _passwordController.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: const [Icon(Icons.edit, color: Color(0xFF0D47A1)), SizedBox(width: 8), Text('تعديل المستخدم', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))]),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'اسم المستخدم', border: OutlineInputBorder()),
                    textInputAction: TextInputAction.next,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'أدخل الاسم' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(labelText: 'رقم الهاتف', border: OutlineInputBorder()),
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'أدخل الهاتف' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(labelText: 'كلمة المرور', border: OutlineInputBorder()),
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    validator: (v) => null,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : () async {
                        // If password left empty, fetch old password
                        if (_passwordController.text.trim().isEmpty) {
                          final userSnap = await FirebaseFirestore.instance.collection('users').doc(userId).get();
                          final oldPwd = userSnap.data()?['userPassword']?.toString() ?? '';
                          _passwordController.text = oldPwd;
                        }
                        await _editUser(userId);
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D47A1), foregroundColor: Colors.white),
                      child: _submitting
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                          : const Text('تحديث'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('مستخدمون ${widget.labName}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF0D47A1),
          centerTitle: true,
          actions: [
            IconButton(
              onPressed: _openAddUserSheet,
              icon: const Icon(Icons.add, color: Colors.white),
              tooltip: 'إضافة مستخدم',
            ),
          ],
        ),
        body: Column(
          children: [
            const Divider(height: 0),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _labUsersCol.snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) return Center(child: Text('خطأ: ${snap.error}'));
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  final users = snap.data!.docs;
                  if (users.isEmpty) {
                    return const Center(child: Text('لا يوجد مستخدمون بعد'));
                  }
                  return ListView.separated(
                    itemCount: users.length,
                    padding: const EdgeInsets.all(16),
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final d = users[i];
                      final data = d.data();
                      final name = data['userName']?.toString() ?? '';
                      final phone = data['userPhone']?.toString() ?? '';
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.person, color: Color(0xFF0D47A1)),
                          title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('الهاتف: $phone'),
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) async {
                              if (v == 'edit') {
                                _openEditUserSheet(d.id, data);
                              } else if (v == 'delete') {
                                await _deleteUser(d.id, name);
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18, color: Color(0xFF0D47A1)), SizedBox(width: 8), Text('تعديل')])),
                              PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 18, color: Colors.red), SizedBox(width: 8), Text('حذف')])),
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


