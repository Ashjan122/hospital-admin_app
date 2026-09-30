import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'admin_user_profile_screen.dart';

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
      final snapshot =
          await FirebaseFirestore.instance
              .collection('users')
              .where('centerId', isEqualTo: widget.centerId)
              .get();

      final users =
          snapshot.docs.map((doc) {
            final data = doc.data();
            data['userId'] = doc.id;
            return data;
          }).toList();

      // ترتيب المستخدمين بالأحدث أولًا حسب createdAt
      users.sort((a, b) {
        final aTime = a['createdAt'] as Timestamp?;
        final bTime = b['createdAt'] as Timestamp?;
        return (bTime ?? Timestamp(0, 0)).compareTo(aTime ?? Timestamp(0, 0));
      });

      return users;
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
      builder:
          (context) => AlertDialog(
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

  Future<void> _openAddUserProfile() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder:
            (_) => AdminUserProfileScreen(
              isNewUser: true,
              centerId: widget.centerId,
              centerName: widget.centerName,
            ),
      ),
    );

    if (created == true && mounted) {
      setState(() {
        _refreshKey++;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إنشاء المستخدم بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            children: [
              Text(
                'إدارة المستخدمين ',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                ' ${widget.centerName}',
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
            ],
          ),
          backgroundColor: const Color.fromARGB(255, 34, 96, 129),
          centerTitle: true,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'إضافة مستخدم جديد',
              onPressed: _openAddUserProfile,
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // ✅ قسم البحث فقط
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.grey[50],
                child: TextField(
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
              ),

              // ✅ قائمة المستخدمين
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  key: ValueKey(_refreshKey),
                  future: _getUsersWithRefresh(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: Color.fromARGB(255, 34, 96, 129),
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
                              _searchQuery.isEmpty
                                  ? Icons.people_outline
                                  : Icons.search_off,
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

                        return InkWell(
                          onTap: () async {
                            final changed = await Navigator.of(
                              context,
                            ).push<bool>(
                              MaterialPageRoute(
                                builder:
                                    (_) => AdminUserProfileScreen(
                                      userId: user['userId'],
                                    ),
                              ),
                            );
                            if (changed == true && mounted) {
                              setState(() {
                                _refreshKey++;
                              });
                            }
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey[300]!),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.withOpacity(0.05),
                                  spreadRadius: 1,
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  // 🔢 رقم تسلسلي
                                  Text(
                                    '${filteredUsers.length - index}.',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey[700],
                                    ),
                                  ),

                                  const SizedBox(width: 10),

                                  // ✅ اسم المستخدم + النوع في سطر واحد
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            user['userName'] ??
                                                'مستخدم غير معروف',
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.black87,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _getUserTypeColor(
                                              user['userType'] ?? 'reception',
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: Text(
                                            _getUserTypeLabel(
                                              user['userType'] ?? 'reception',
                                            ),
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // 🗑️ زر الحذف الصغير
                                  IconButton(
                                    onPressed:
                                        () => deleteUser(
                                          user['userId'],
                                          user['userName'],
                                        ),
                                    icon: const Icon(
                                      Icons.delete,
                                      color: Colors.red,
                                      size: 18,
                                    ),
                                    tooltip: 'حذف المستخدم',
                                    padding: const EdgeInsets.all(6),
                                    constraints: const BoxConstraints(
                                      minWidth: 32,
                                      minHeight: 32,
                                    ),
                                  ),
                                ],
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
      ),
    );
  }

  Color _getUserTypeColor(String userType) {
    switch (userType) {
      case 'admin':
        return Colors.red;
      case 'doctor':
        return Colors.blue;
      case 'callcenter':
        return Colors.orange;
      case 'reception':
      default:
        return const Color.fromARGB(255, 34, 96, 129);
    }
  }

  String _getUserTypeLabel(String userType) {
    switch (userType) {
      case 'admin':
        return 'مدير';
      case 'doctor':
        return 'طبيب';
      case 'callcenter':
        return 'Call Center';
      case 'reception':
      default:
        return 'موظف استقبال';
    }
  }
}
