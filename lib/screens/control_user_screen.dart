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
  String _searchQuery = '';
  final ImagePicker _picker = ImagePicker();

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

  // ============================
  // تحميل المستخدمين control فقط
  // ============================
  Future<void> _loadControlUsers() async {
    try {
      setState(() => _isLoading = true);

      final snap =
          await FirebaseFirestore.instance
              .collection('users')
              .where('role', isEqualTo: 'control')
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

      setState(() {
        _allUsers = users;
        _filteredUsers = users;
        _isLoading = false;
      });
    } catch (e) {
      print(e);
      setState(() => _isLoading = false);
    }
  }

  // ============================
  // بحث
  // ============================
  void _filterUsers(String query) {
    setState(() {
      _searchQuery = query;

      if (query.isEmpty) {
        _filteredUsers = _allUsers;
      } else {
        final q = query.toLowerCase();
        _filteredUsers =
            _allUsers.where((u) {
              return u['userName'].toString().toLowerCase().contains(q) ||
                  u['email'].toString().toLowerCase().contains(q);
            }).toList();
      }
    });
  }

  // ============================
  // إضافة مستخدم (Auth + Firestore)
  // ============================
  void _showAddUserDialog() {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passController = TextEditingController();
    File? image;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text("إضافة مستخدم"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: "الاسم"),
                  ),
                  TextField(
                    controller: emailController,
                    decoration: const InputDecoration(labelText: "الإيميل"),
                  ),
                  TextField(
                    controller: passController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: "كلمة المرور"),
                  ),
                  const SizedBox(height: 10),

                  TextButton.icon(
                    onPressed: () async {
                      final picked = await ImagePicker().pickImage(
                        source: ImageSource.gallery,
                      );
                      if (picked != null) {
                        setStateDialog(() {
                          image = File(picked.path);
                        });
                      }
                    },
                    icon: const Icon(Icons.image),
                    label: const Text("صورة"),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("إلغاء"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      final cred = await FirebaseAuth.instance
                          .createUserWithEmailAndPassword(
                            email: emailController.text.trim(),
                            password: passController.text.trim(),
                          );

                      final uid = cred.user!.uid;

                      String imageUrl = '';

                      if (image != null) {
                        final ref = FirebaseStorage.instance.ref().child(
                          'profile_images/$uid.jpg',
                        );

                        await ref.putFile(image!);
                        imageUrl = await ref.getDownloadURL();
                      }

                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(uid)
                          .set({
                            'uid': uid,
                            'displayName': nameController.text.trim(),
                            'email': emailController.text.trim(),
                            'role': 'control',
                            'profileImageUrl': imageUrl,
                            'createdAt': FieldValue.serverTimestamp(),
                          });

                      Navigator.pop(context);
                      _loadControlUsers();
                    } catch (e) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(e.toString())));
                    }
                  },
                  child: const Text("إضافة"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ============================
  // تعديل الاسم فقط
  // ============================
  void _editUserDialog(Map<String, dynamic> user) {
    final nameController = TextEditingController(text: user['userName']);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("تعديل المستخدم"),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: "الاسم"),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("إلغاء"),
            ),
            ElevatedButton(
              onPressed: () async {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(user['uid'])
                    .update({'displayName': nameController.text.trim()});

                Navigator.pop(context);
                _loadControlUsers();
              },
              child: const Text("حفظ"),
            ),
          ],
        );
      },
    );
  }

  // ============================
  // تغيير الصورة
  // ============================
  Future<void> _changeUserImage(Map<String, dynamic> user) async {
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

    _loadControlUsers();
  }

  // ============================
  // UI
  // ============================
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            "مستخدمي الكنترول",
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
                  hintText: "بحث...",
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
                      : ListView.builder(
                        itemCount: _filteredUsers.length,
                        itemBuilder: (context, i) {
                          final user = _filteredUsers[i];

                          return Card(
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
