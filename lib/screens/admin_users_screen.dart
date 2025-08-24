import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminUsersScreen extends StatefulWidget {
  final String centerId;
  final String centerName;
  
  const AdminUsersScreen({
    super.key,
    required this.centerId,
    required this.centerName,
  });

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  int _refreshKey = 0; // مفتاح للتحديث

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> fetchUsers() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('centerId', isEqualTo: widget.centerId)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['userId'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      print('Error fetching users: $e');
      return [];
    }
  }

  // دالة جديدة تعتمد على _refreshKey لإجبار FutureBuilder على إعادة التشغيل
  Future<List<Map<String, dynamic>>> _getUsersWithRefresh() async {
    // استخدام _refreshKey في الدالة لضمان إعادة التشغيل
    print('Refreshing users list, refresh key: $_refreshKey');
    return await fetchUsers();
  }

  List<Map<String, dynamic>> filterUsers(List<Map<String, dynamic>> users) {
    if (_searchQuery.isEmpty) return users;
    
    return users.where((user) {
      final userName = user['userName']?.toString().toLowerCase() ?? '';
      final userPhone = user['userPhone']?.toString().toLowerCase() ?? '';
      
      return userName.contains(_searchQuery.toLowerCase()) ||
             userPhone.contains(_searchQuery.toLowerCase());
    }).toList();
  }

  Future<void> deleteUser(String userId, String userName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف المستخدم "$userName"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .delete();

        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم حذف المستخدم "$userName" بنجاح'),
              backgroundColor: Colors.green,
            ),
          );
          if (mounted) {
            setState(() {
              _refreshKey++; // تحديث المفتاح لإعادة تشغيل FutureBuilder
            });
          }
        }
      } catch (e) {
        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('خطأ في حذف المستخدم: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showAddUserDialog() {
    final userNameController = TextEditingController();
    final userPhoneController = TextEditingController();
    final userPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة مستخدم جديد'),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
              controller: userNameController,
                decoration: const InputDecoration(
                  labelText: 'اسم المستخدم',
                  border: OutlineInputBorder(),
                ),
              ),
            const SizedBox(height: 12),
              TextField(
              controller: userPhoneController,
                decoration: const InputDecoration(
                  labelText: 'رقم الهاتف',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
            const SizedBox(height: 12),
              TextField(
              controller: userPasswordController,
              obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'كلمة المرور',
                  border: OutlineInputBorder(),
                ),
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
              if (userNameController.text.trim().isNotEmpty &&
                  userPhoneController.text.trim().isNotEmpty &&
                  userPasswordController.text.trim().isNotEmpty) {
                Navigator.pop(context);
                
                try {
                  await FirebaseFirestore.instance
                      .collection('users')
                      .add({
                    'userName': userNameController.text.trim(),
                    'userPhone': userPhoneController.text.trim(),
                    'userPassword': userPasswordController.text.trim(),
                    'centerId': widget.centerId,
                    'centerName': widget.centerName,
                    'userType': 'user',
                    'createdAt': FieldValue.serverTimestamp(),
                  });

                  // تحديث فوري للمفتاح
                  if (mounted) {
                    setState(() {
                      _refreshKey++; // تحديث المفتاح لإعادة تشغيل FutureBuilder
                    });
                  }

                  if (mounted && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('تم إضافة المستخدم "${userNameController.text.trim()}" بنجاح'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('خطأ في إضافة المستخدم: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2FBDAF),
              foregroundColor: Colors.white,
            ),
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'إدارة المستخدمين - ${widget.centerName}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF2FBDAF),
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                setState(() {
                  _refreshKey++; // تحديث المفتاح لإعادة تشغيل FutureBuilder
                });
              },
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
          children: [
            // Search and add user section
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey[50],
              child: Column(
                children: [
                  // Search bar
                  TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'البحث في المستخدمين...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Add user button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _showAddUserDialog,
                      icon: const Icon(Icons.person_add),
                      label: const Text('إضافة مستخدم جديد'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2FBDAF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Users list
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                key: ValueKey(_refreshKey), // استخدام المفتاح لإعادة تشغيل FutureBuilder
                future: _getUsersWithRefresh(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF2FBDAF),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 64,
                            color: Colors.red[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'حدث خطأ في تحميل المستخدمين',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final users = snapshot.data ?? [];
                  final filteredUsers = filterUsers(users);

                  if (filteredUsers.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _searchQuery.isEmpty ? Icons.people_outline : Icons.search_off,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isEmpty 
                                  ? 'لا يوجد مستخدمين في هذا المركز'
                                  : 'لم يتم العثور على مستخدمين يطابقون البحث',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _searchQuery.isEmpty 
                                  ? 'لم يتم العثور على أي مستخدمين مسجلين'
                                  : 'جرب البحث بكلمات مختلفة',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
                          ),
                          if (_searchQuery.isEmpty) ...[
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _showAddUserDialog,
                              icon: const Icon(Icons.person_add),
                              label: const Text('إضافة مستخدم جديد'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2FBDAF),
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredUsers.length,
                    itemBuilder: (context, index) {
                      final user = filteredUsers[index];
                        final userName = user['userName'] ?? 'مستخدم غير معروف';
                        final userPhone = user['userPhone'] ?? 'غير محدد';

                                             return Container(
                         margin: const EdgeInsets.only(bottom: 12),
                         decoration: BoxDecoration(
                           color: Colors.white,
                           borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[300]!),
                           boxShadow: [
                             BoxShadow(
                               color: Colors.grey.withOpacity(0.08),
                               spreadRadius: 1,
                               blurRadius: 6,
                               offset: const Offset(0, 2),
                             ),
                           ],
                         ),
                                                  child: Padding(
                           padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                           child: Row(
                             children: [
                               // User info with labels
                               Expanded(
                                 child: Column(
                                   crossAxisAlignment: CrossAxisAlignment.start,
                                   children: [
                                     Row(
                                       children: [
                                         Text(
                                           'اسم المستخدم: ',
                                           style: TextStyle(
                                             fontSize: 15,
                                             fontWeight: FontWeight.w600,
                                             color: Colors.grey[700],
                                           ),
                                         ),
                                         Text(
                                           userName,
                                           style: const TextStyle(
                                             fontSize: 15,
                                             fontWeight: FontWeight.bold,
                                             color: Colors.black87,
                                           ),
                                         ),
                                       ],
                                     ),
                                     const SizedBox(height: 8),
                                     Row(
                                       children: [
                                         Text(
                                           'رقم الهاتف: ',
                                           style: TextStyle(
                                             fontSize: 15,
                                             fontWeight: FontWeight.w600,
                                             color: Colors.grey[700],
                                           ),
                                         ),
                                         Text(
                                           userPhone,
                                           style: TextStyle(
                                             fontSize: 15,
                                             color: Colors.grey[600],
                                           ),
                                         ),
                                       ],
                                     ),
                                   ],
                                 ),
                               ),
                               
                               // Delete button
                               Container(
                                 decoration: BoxDecoration(
                                   color: Colors.red.withOpacity(0.1),
                                   borderRadius: BorderRadius.circular(8),
                                 ),
                                 child: IconButton(
                                   onPressed: () => deleteUser(user['userId'], userName),
                                   icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                   tooltip: 'حذف المستخدم',
                                   padding: const EdgeInsets.all(8),
                                   constraints: const BoxConstraints(
                                     minWidth: 36,
                                     minHeight: 36,
                                   ),
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
      ),
    );
  }
}
