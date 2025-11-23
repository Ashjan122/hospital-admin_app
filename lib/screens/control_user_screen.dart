import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

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
  //  جلب المستخدمين من controlUsers
  // ============================

  Future<void> _loadControlUsers() async {
    try {
      setState(() => _isLoading = true);

      final snap =
          await FirebaseFirestore.instance.collection('controlUsers').get();

      List<Map<String, dynamic>> users = [];

      for (var doc in snap.docs) {
        final data = doc.data();
        users.add({
          'docId': doc.id,
          'userId': data['userId'] ?? '',
          'userName': data['userName'] ?? '',
          'userPassword': data['userPassword'] ?? '',
          'profileImageUrl': data['profileImageUrl'] ?? '',
          'isOnline': data['isOnline'] ?? false,
        });
      }

      setState(() {
        _allUsers = users;
        _filteredUsers = users;
        _isLoading = false;
      });
    } catch (e) {
      print("❌ خطأ في تحميل مستخدمي الكنترول: $e");
      setState(() => _isLoading = false);
    }
  }

  // ============================
  //   البحث
  // ============================

  void _filterUsers(String query) {
    setState(() {
      _searchQuery = query;

      if (query.isEmpty) {
        _filteredUsers = _allUsers;
      } else {
        final lower = query.toLowerCase();
        _filteredUsers = _allUsers.where((u) {
          return u['userName'].toString().toLowerCase().contains(lower) ||
              u['userId'].toString().toLowerCase().contains(lower);
        }).toList();
      }
    });
  }

  

  void _editUserDialog(Map<String, dynamic> user) {
    final TextEditingController nameController =
        TextEditingController(text: user['userName']);
    final TextEditingController passController =
        TextEditingController(text: user['userPassword']);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("تعديل بيانات المستخدم"),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: nameController,
                  decoration:
                      const InputDecoration(labelText: "اسم المستخدم"),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passController,
                  obscureText: true,
                  decoration:
                      const InputDecoration(labelText: "كلمة المرور"),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () => _changeUserImage(user),
                  icon: const Icon(Icons.image),
                  label: const Text("تغيير الصورة"),
                  style: ElevatedButton.styleFrom(
                    
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text("إلغاء"),
              onPressed: () => Navigator.pop(context),
            ),
            ElevatedButton(
              child: const Text("حفظ"),
              onPressed: () async {
                await FirebaseFirestore.instance
                    .collection('controlUsers')
                    .doc(user['docId'])
                    .update({
                  'userName': nameController.text.trim(),
                  'userPassword': passController.text.trim(),
                });

                Navigator.pop(context);
                _loadControlUsers();
              },
            ),
          ],
        );
      },
    );
  }
  void _showAddUserDialog() {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController passController = TextEditingController();
  File? pickedImage;

  showDialog(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text("إضافة مستخدم كنترول"),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: "اسم المستخدم",
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: passController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: "كلمة المرور",
                  ),
                ),
                const SizedBox(height: 12),

                // اختيار صورة
                TextButton.icon(
                  onPressed: () async {
                    final picked = await ImagePicker().pickImage(
                        source: ImageSource.gallery, imageQuality: 70);
                    if (picked != null) {
                      setStateDialog(() {
                        pickedImage = File(picked.path);
                      });
                    }
                  },
                  icon: const Icon(Icons.image),
                  label: const Text("اختيار صورة (اختياري)"),
                ),

                if (pickedImage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: CircleAvatar(
                      radius: 40,
                      backgroundImage: FileImage(pickedImage!),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("إلغاء"),
            ),
            ElevatedButton(
              child: const Text("إضافة"),
              onPressed: () async {
                if (nameController.text.trim().isEmpty ||
                    passController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("الرجاء إدخال الاسم وكلمة المرور"),
                    ),
                  );
                  return;
                }

                // إنشاء userId تلقائي
                final newUserId =
                    "control_${DateTime.now().millisecondsSinceEpoch}";

                String? imageUrl;

                // رفع الصورة إن وُجدت
                if (pickedImage != null) {
                  final ref = FirebaseStorage.instance
                      .ref()
                      .child('profile_images/$newUserId.jpg');
                  await ref.putFile(pickedImage!);
                  imageUrl = await ref.getDownloadURL();
                }

                // إضافة المستخدم
                await FirebaseFirestore.instance
                    .collection('controlUsers')
                    .doc(newUserId)
                    .set({
                  'userId': newUserId,
                  'userName': nameController.text.trim(),
                  'userPassword': passController.text.trim(),
                  'profileImageUrl': imageUrl ?? '',
                  'isOnline': true,
                  'userType': 'control',
                  'lastSeen': DateTime.now(),
                });

                Navigator.pop(context);
                _loadControlUsers();
              },
            ),
          ],
        ),
      );
    },
  );
}


  

  Future<void> _changeUserImage(Map<String, dynamic> user) async {
    final picked =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked == null) return;

    final file = File(picked.path);
    final ref = FirebaseStorage.instance
        .ref()
        .child('profile_images/${user['userId']}.jpg');

    await ref.putFile(file);
    final url = await ref.getDownloadURL();

    await FirebaseFirestore.instance
        .collection('controlUsers')
        .doc(user['docId'])
        .update({'profileImageUrl': url});

    _loadControlUsers();
  }

  
  Future<void> _toggleOnline(Map<String, dynamic> user) async {
    await FirebaseFirestore.instance
        .collection('controlUsers')
        .doc(user['docId'])
        .update({'isOnline': !user['isOnline']});

    _loadControlUsers();
  }

  
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("مستخدمي الكنترول"),
          backgroundColor: const Color(0xFF0D47A1),
          centerTitle: true,
          foregroundColor: Colors.white,
          actions: [
    IconButton(
      icon: const Icon(Icons.add),
      tooltip: "إضافة مستخدم جديد",
      onPressed: _showAddUserDialog,
    ),
    
  ],
        ),

        body: Column(
          children: [
            
            Container(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                onChanged: _filterUsers,
                decoration: InputDecoration(
                  hintText: 'بحث باسم المستخدم',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _filterUsers('');
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Color(0xFF0D47A1)),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _filteredUsers.length,
                      itemBuilder: (context, index) {
                        final user = _filteredUsers[index];

                        return Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 2,
                          margin: const EdgeInsets.only(bottom: 14),
                          child: ListTile(
                            leading: CircleAvatar(
                              radius: 25,
                              backgroundImage:
                                  user['profileImageUrl'] != null &&
                                          user['profileImageUrl'] != ''
                                      ? NetworkImage(user['profileImageUrl'])
                                      : null,
                              child: user['profileImageUrl'] == null ||
                                      user['profileImageUrl'] == ''
                                  ? const Icon(Icons.person, size: 28)
                                  : null,
                            ),

                            title: Text(
                              user['userName'],
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold),
                            ),

                            trailing: PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert),
                              onSelected: (value) {
                                switch (value) {
                                  case 'edit':
                                    _editUserDialog(user);
                                    break;
                                  case 'toggle':
                                    _toggleOnline(user);
                                    break;
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem<String>(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit, color: Color(0xFF0D47A1), size: 20),
                                      SizedBox(width: 8),
                                      Text('تعديل'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem<String>(
                                  value: 'toggle',
                                  child: Row(
                                    children: [
                                      Icon(
                                        user['isOnline'] ? Icons.toggle_on : Icons.toggle_off,
                                        color: user['isOnline'] ? Colors.green : Colors.grey,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(user['isOnline'] ? 'تعطيل' : 'تفعيل'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            )
          ],
        ),
      ),
    );
  }
}
