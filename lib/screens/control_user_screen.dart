import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ControlUsersScreen extends StatefulWidget {
  const ControlUsersScreen({super.key});

  @override
  State<ControlUsersScreen> createState() => _ControlUsersScreenState();
}

class _ControlUsersScreenState extends State<ControlUsersScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  String _searchQuery = '';

  bool _isLoading = true;
  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _filteredUsers = [];

  @override
  void initState() {
    super.initState();
    _loadControlUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // =========================================================
  // تحميل مستخدمي superadmin فقط
  // =========================================================
  Future<void> _loadControlUsers() async {
    try {
      setState(() => _isLoading = true);

      final snap =
          await FirebaseFirestore.instance
              .collection('users')
              .where('role', isEqualTo: 'superadmin')
              .get();

      final users =
          snap.docs.map((doc) {
            final data = doc.data();

            return {
              'uid': doc.id,
              'userName': data['displayName'] ?? '',
              'email': data['email'] ?? '',
              'profileImageUrl': data['profileImageUrl'] ?? '',
            };
          }).toList();

      if (!mounted) return;

      setState(() {
        _allUsers = users;
        _filteredUsers = users;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('خطأ في تحميل المستخدمين: $e');

      if (!mounted) return;

      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ في تحميل المستخدمين: $e')),
      );
    }
  }

  // =========================================================
  // البحث
  // =========================================================
  void _filterUsers(String query) {
    setState(() {
      _searchQuery = query;

      if (query.trim().isEmpty) {
        _filteredUsers = _allUsers;
        return;
      }

      final q = query.toLowerCase().trim();

      _filteredUsers =
          _allUsers.where((u) {
            return u['userName'].toString().toLowerCase().contains(q) ||
                u['email'].toString().toLowerCase().contains(q);
          }).toList();
    });
  }

  // =========================================================
  // إضافة Super Admin
  // =========================================================
  void _showAddUserDialog() {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passController = TextEditingController();

    File? image;
    bool isCreating = false;
    bool obscurePassword = true;

    showDialog(
      context: context,
      barrierDismissible: !isCreating,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('إضافة مشرف عام', textAlign: TextAlign.center),

              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // الاسم
                    TextField(
                      controller: nameController,
                      enabled: !isCreating,
                      textDirection: TextDirection.rtl,
                      decoration: const InputDecoration(
                        labelText: 'الاسم',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // الإيميل
                    TextField(
                      controller: emailController,
                      enabled: !isCreating,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'الإيميل',
                        prefixIcon: Icon(Icons.email),
                        border: OutlineInputBorder(),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // كلمة المرور
                    TextField(
                      controller: passController,
                      enabled: !isCreating,
                      obscureText: obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'كلمة المرور',
                        prefixIcon: const Icon(Icons.lock),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: () {
                            setStateDialog(() {
                              obscurePassword = !obscurePassword;
                            });
                          },
                          icon: Icon(
                            obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // الدور ثابت
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.admin_panel_settings),
                          SizedBox(width: 10),
                          Text(
                            'الدور: مشرف عام',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    // اختيار الصورة
                    TextButton.icon(
                      onPressed:
                          isCreating
                              ? null
                              : () async {
                                final picked = await _picker.pickImage(
                                  source: ImageSource.gallery,
                                );

                                if (picked != null) {
                                  setStateDialog(() {
                                    image = File(picked.path);
                                  });
                                }
                              },
                      icon: const Icon(Icons.image),
                      label: Text(
                        image == null ? 'اختيار صورة' : 'تم اختيار الصورة',
                      ),
                    ),

                    if (image != null) ...[
                      const SizedBox(height: 8),
                      ClipOval(
                        child: Image.file(
                          image!,
                          width: 70,
                          height: 70,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              actions: [
                TextButton(
                  onPressed:
                      isCreating ? null : () => Navigator.pop(dialogContext),
                  child: const Text('إلغاء'),
                ),

                ElevatedButton(
                  onPressed:
                      isCreating
                          ? null
                          : () async {
                            final name = nameController.text.trim();
                            final email = emailController.text.trim();
                            final password = passController.text.trim();

                            if (name.isEmpty ||
                                email.isEmpty ||
                                password.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'الاسم والإيميل وكلمة المرور مطلوبة',
                                  ),
                                ),
                              );
                              return;
                            }

                            if (password.length < 6) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'كلمة المرور يجب أن تكون 6 أحرف على الأقل',
                                  ),
                                ),
                              );
                              return;
                            }

                            setStateDialog(() {
                              isCreating = true;
                            });

                            try {
                              // =========================================
                              // 1. إنشاء المستخدم في Firebase Authentication
                              // =========================================
                              final credential = await FirebaseAuth.instance
                                  .createUserWithEmailAndPassword(
                                    email: email,
                                    password: password,
                                  );

                              final uid = credential.user!.uid;

                              // =========================================
                              // 2. تحديث اسم المستخدم في Auth
                              // =========================================
                              await credential.user!.updateDisplayName(name);

                              // =========================================
                              // 3. رفع الصورة
                              // =========================================
                              String imageUrl = '';

                              if (image != null) {
                                final ref = FirebaseStorage.instance
                                    .ref()
                                    .child('profile_images/$uid.jpg');

                                await ref.putFile(image!);

                                imageUrl = await ref.getDownloadURL();
                              }

                              // =========================================
                              // 4. حفظ نفس بيانات مستخدم المنصة
                              //    users/{uid}
                              // =========================================
                              await FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(uid)
                                  .set({
                                    'uid': uid,
                                    'facilityId': null,
                                    'facilityName': null,
                                    'role': 'superadmin',
                                    'email': email,
                                    'displayName': name,
                                    'profileImageUrl': imageUrl,
                                    'createdAt': FieldValue.serverTimestamp(),
                                  });

                              if (!mounted) return;

                              Navigator.pop(dialogContext);

                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('تم إنشاء المشرف العام بنجاح'),
                                ),
                              );

                              await _loadControlUsers();
                            } on FirebaseAuthException catch (e) {
                              String message;

                              switch (e.code) {
                                case 'email-already-in-use':
                                  message = 'هذا الإيميل مستخدم بالفعل';
                                  break;

                                case 'invalid-email':
                                  message = 'الإيميل غير صحيح';
                                  break;

                                case 'weak-password':
                                  message = 'كلمة المرور ضعيفة';
                                  break;

                                default:
                                  message =
                                      e.message ??
                                      'حدث خطأ أثناء إنشاء المستخدم';
                              }

                              if (!mounted) return;

                              setStateDialog(() {
                                isCreating = false;
                              });

                              ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(SnackBar(content: Text(message)));
                            } catch (e) {
                              debugPrint('خطأ في إنشاء المستخدم: $e');

                              if (!mounted) return;

                              setStateDialog(() {
                                isCreating = false;
                              });

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('حدث خطأ: $e')),
                              );
                            }
                          },
                  child:
                      isCreating
                          ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Text('إضافة'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // =========================================================
  // تعديل الاسم
  // =========================================================
  void _editUserDialog(Map<String, dynamic> user) {
    final nameController = TextEditingController(text: user['userName']);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('تعديل المستخدم'),

          content: TextField(
            controller: nameController,
            textDirection: TextDirection.rtl,
            decoration: const InputDecoration(
              labelText: 'الاسم',
              border: OutlineInputBorder(),
            ),
          ),

          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),

            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();

                if (name.isEmpty) return;

                try {
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(user['uid'])
                      .update({'displayName': name});

                  if (!mounted) return;

                  Navigator.pop(context);
                  await _loadControlUsers();
                } catch (e) {
                  if (!mounted) return;

                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('حدث خطأ: $e')));
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        );
      },
    );
  }

  // =========================================================
  // تغيير الصورة
  // =========================================================
  Future<void> _changeUserImage(Map<String, dynamic> user) async {
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);

      if (picked == null) return;

      final file = File(picked.path);

      final ref = FirebaseStorage.instance.ref().child(
        'profile_images/${user['uid']}.jpg',
      );

      await ref.putFile(file);

      final url = await ref.getDownloadURL();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user['uid'])
          .update({'profileImageUrl': url});

      await _loadControlUsers();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('حدث خطأ في تغيير الصورة: $e')));
    }
  }

  // =========================================================
  // UI
  // =========================================================
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,

      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'مستخدمي الكنترول',
            style: TextStyle(color: Colors.white),
          ),
          centerTitle: true,
          backgroundColor: const Color(0xFF0D47A1),

          actions: [
            IconButton(
              icon: const Icon(Icons.add, color: Colors.white),
              onPressed: _showAddUserDialog,
            ),
          ],
        ),

        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),

              child: TextField(
                controller: _searchController,
                onChanged: _filterUsers,

                decoration: InputDecoration(
                  hintText: 'بحث...',
                  prefixIcon: const Icon(Icons.search),

                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            Expanded(
              child:
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _filteredUsers.isEmpty
                      ? const Center(
                        child: Text(
                          'لا يوجد مستخدمون',
                          style: TextStyle(fontSize: 16),
                        ),
                      )
                      : ListView.builder(
                        itemCount: _filteredUsers.length,

                        itemBuilder: (context, i) {
                          final user = _filteredUsers[i];

                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),

                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundImage:
                                    user['profileImageUrl'] != ''
                                        ? NetworkImage(user['profileImageUrl'])
                                        : null,

                                child:
                                    user['profileImageUrl'] == ''
                                        ? const Icon(Icons.person)
                                        : null,
                              ),

                              title: Text(user['userName']),

                              subtitle: Text(user['email']),

                              trailing: PopupMenuButton(
                                itemBuilder:
                                    (context) => [
                                      PopupMenuItem(
                                        value: 'edit',
                                        child: const Text('تعديل الاسم'),
                                        onTap:
                                            () => Future.delayed(
                                              Duration.zero,
                                              () => _editUserDialog(user),
                                            ),
                                      ),

                                      PopupMenuItem(
                                        value: 'img',
                                        child: const Text('تغيير الصورة'),
                                        onTap:
                                            () => Future.delayed(
                                              Duration.zero,
                                              () => _changeUserImage(user),
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
