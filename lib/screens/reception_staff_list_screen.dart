import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ReceptionStaffListScreen extends StatefulWidget {
  const ReceptionStaffListScreen({super.key});

  @override
  State<ReceptionStaffListScreen> createState() => _ReceptionStaffListScreenState();
}

class _ReceptionStaffListScreenState extends State<ReceptionStaffListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isLoading = true;
  List<Map<String, dynamic>> _allReceptionStaff = [];
  List<Map<String, dynamic>> _filteredReceptionStaff = [];

  @override
  void initState() {
    super.initState();
    _loadReceptionStaff();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadReceptionStaff() async {
    try {
    setState(() {
      _isLoading = true;
    });

      print('=== LOADING RECEPTION STAFF ===');
      
      // جلب جميع المستخدمين من نوع "reception"
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('userType', isEqualTo: 'reception')
          .get();

      print('Found ${usersSnapshot.docs.length} reception staff users');

      final List<Map<String, dynamic>> receptionStaff = [];

      for (var userDoc in usersSnapshot.docs) {
        final userData = userDoc.data();
        final userId = userDoc.id;

        // جلب اسم المركز من مجموعة medicalFacilities
        String centerName = 'مركز غير محدد';
          try {
          if (userData['centerId'] != null) {
            final centerDoc = await FirebaseFirestore.instance
                .collection('medicalFacilities')
                .doc(userData['centerId'])
                .get();

            if (centerDoc.exists) {
              centerName = centerDoc.data()?['name'] ?? 'مركز غير محدد';
            }
          }
        } catch (e) {
          print('Error fetching center name for user $userId: $e');
        }

        final staffMember = {
          'userId': userId,
          'userName': userData['userName'] ?? 'اسم غير محدد',
          'centerId': userData['centerId'] ?? '',
          'centerName': centerName,
          'confirmedBookingsCount': userData['confirmedBookingsCount'] ?? 0,
          'lastUpdated': userData['lastUpdated'],
          'createdAt': userData['createdAt'],
          'userPhone': userData['userPhone'] ?? '',
        };

        receptionStaff.add(staffMember);
        print('Added staff member: ${staffMember['userName']} - ${staffMember['centerName']}');
      }

      // ترتيب حسب عدد الحجوزات المؤكدة (تنازلياً)
      receptionStaff.sort((a, b) => (b['confirmedBookingsCount'] ?? 0).compareTo(a['confirmedBookingsCount'] ?? 0));

      if (mounted) {
        setState(() {
          _allReceptionStaff = receptionStaff;
          _filteredReceptionStaff = receptionStaff;
          _isLoading = false;
        });
      }

      print('✅ Reception staff loaded successfully: ${receptionStaff.length} members');

    } catch (e) {
      print('❌ Error loading reception staff: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _filterReceptionStaff(String query) {
    setState(() {
      _searchQuery = query;
      
      if (query.isEmpty) {
        _filteredReceptionStaff = _allReceptionStaff;
      } else {
        _filteredReceptionStaff = _allReceptionStaff.where((staff) {
          final userName = staff['userName']?.toString().toLowerCase() ?? '';
          final centerName = staff['centerName']?.toString().toLowerCase() ?? '';
          final searchLower = query.toLowerCase();
          
          return userName.contains(searchLower) || centerName.contains(searchLower);
        }).toList();
      }
    });
  }

  // _formatDate غير مستخدمة حالياً وتمت إزالتها لتفادي تحذيرات اللينتر

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'موظفي الاستقبال',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF0D47A1),
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadReceptionStaff,
              tooltip: 'تحديث القائمة',
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Search section
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.grey[50],
                child: Column(
                  children: [
                    TextField(
                  controller: _searchController,
                      onChanged: _filterReceptionStaff,
                  decoration: InputDecoration(
                    hintText: 'البحث باسم الموظف أو المركز...',
                    prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  _filterReceptionStaff('');
                                },
                              )
                            : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'عدد الموظفين: ${_filteredReceptionStaff.length}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        if (_searchQuery.isNotEmpty)
                          Text(
                            'نتائج البحث: ${_filteredReceptionStaff.length}',
                            style: TextStyle(
                              fontSize: 14,
                              color: const Color(0xFF0D47A1),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // Reception staff list
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                                color: Color(0xFF0D47A1),
                        ),
                      )
                    : _filteredReceptionStaff.isEmpty
                        ? Center(
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
                                      ? 'لا يوجد موظفي استقبال'
                                      : 'لا توجد نتائج للبحث',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _searchQuery.isEmpty
                                      ? 'سيتم عرض موظفي الاستقبال هنا عند تسجيلهم'
                                      : 'جرب البحث بكلمات مختلفة',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filteredReceptionStaff.length,
                            itemBuilder: (context, index) {
                              final staff = _filteredReceptionStaff[index];
                              // final confirmedCount = staff['confirmedBookingsCount'] ?? 0; // معلق مؤقتاً

                                                             return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                                                   child: Padding(
                                   padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                                                                                                     // Header row
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    staff['userName'] ?? 'اسم غير محدد',
                                                    style: const TextStyle(
                                                      fontSize: 18,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    staff['userPhone'] ?? 'لا يوجد رقم هاتف',
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      color: Colors.grey[600],
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    staff['centerName'] ?? 'مركز غير محدد',
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      color: Colors.grey[600],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // Confirmed bookings count badge with label - معلق مؤقتاً
                                            /*
                                            Column(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF2FBDAF),
                                                    borderRadius: BorderRadius.circular(20),
                                                  ),
                                                  child: Text(
                                                    '$confirmedCount',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'الحجوزات المؤكدة',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey[600],
                                                  ),
                                                ),
                                              ],
                                            ),
                                            */
                                          ],
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
      ),
    );
  }
}
