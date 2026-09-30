import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:hospital_admin_app/screens/facility_details_screen.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:hospital_admin_app/widgets/optimized_loading_widget.dart';

class HospitalScreen extends StatefulWidget {
  const HospitalScreen({super.key});

  @override
  State<HospitalScreen> createState() => _HospitalScreenState();
}

class _HospitalScreenState extends State<HospitalScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<QueryDocumentSnapshot> _allFacilities = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    
    // اختبار الاتصال بـ Firebase
    _testFirebaseConnection();

    
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('📩 رسالة أثناء فتح التطبيق');
      print('🔹 البيانات: ${message.data}');

      if (message.notification != null) {
        print('🔔 إشعار: ${message.notification!.title}');
      }
    });

    
    FirebaseMessaging.instance.getToken().then((token) {
      print('📱 توكن الجهاز: $token');
      
    });
  }
  
  Future<void> _testFirebaseConnection() async {
    try {
      print('🔥 اختبار الاتصال بـ Firebase...');
      final testQuery = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 5));
      
      print('✅ نجح الاتصال بـ Firebase - عدد المستندات: ${testQuery.docs.length}');
      
      if (testQuery.docs.isNotEmpty) {
        final firstDoc = testQuery.docs.first.data();
        print('📄 أول مستند: ${firstDoc.keys.toList()}');
      }
    } catch (e) {
      print('❌ فشل الاتصال بـ Firebase: $e');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<QueryDocumentSnapshot>> fetchFacilities() async {
    try {
      print('بدء تحميل المرافق الطبية...');
      
      // جلب جميع المرافق أولاً
      final snapshot = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .get()
          .timeout(const Duration(seconds: 15));

      print('تم جلب البيانات من Firebase: ${snapshot.docs.length} مستند');

      // إذا كانت القائمة فارغة، أرجع المستندات كما هي
      if (snapshot.docs.isEmpty) {
        _allFacilities = [];
        print('لا توجد مرافق في قاعدة البيانات');
        return [];
      }

              // ترتيب المرافق محلياً - المراكز المفعلة فقط
        final sortedDocs = List<QueryDocumentSnapshot>.from(snapshot.docs);
        
        try {
          sortedDocs.sort((a, b) {
            try {
              final aData = a.data() as Map<String, dynamic>;
              final bData = b.data() as Map<String, dynamic>;
              
              // التحقق من حالة التفعيل أولاً
              final aAvailable = aData['available'] as bool? ?? false;
              final bAvailable = bData['available'] as bool? ?? false;
              
              // إذا كان أحدهما مفعل والآخر غير مفعل، المفعل يأتي أولاً
              if (aAvailable != bAvailable) {
                return aAvailable ? -1 : 1;
              }
              
              // إذا كان كلاهما مفعل، ترتيب حسب order
              if (aAvailable && bAvailable) {
                final aOrder = aData['order'] as int? ?? 999;
                final bOrder = bData['order'] as int? ?? 999;
                return aOrder.compareTo(bOrder);
              }
              
              // إذا كان كلاهما غير مفعل، ترتيب حسب order
              final aOrder = aData['order'] as int? ?? 999;
              final bOrder = bData['order'] as int? ?? 999;
              return aOrder.compareTo(bOrder);
            } catch (e) {
              print('خطأ في ترتيب المستند: $e');
              return 0;
            }
          });
        } catch (e) {
          print('خطأ في الترتيب، استخدام الترتيب الافتراضي: $e');
        }

      _allFacilities = sortedDocs;
      print('تم تحميل وترتيب ${sortedDocs.length} مرفق طبي');
      
              // طباعة أسماء المرافق للتأكد
        print('📋 ترتيب المرافق بعد الفرز:');
        for (int i = 0; i < sortedDocs.length && i < 10; i++) {
          final data = sortedDocs[i].data() as Map<String, dynamic>;
          final isAvailable = data['available'] as bool? ?? false;
          final order = data['order'] as int? ?? 999;
          final status = isAvailable ? '✅ مفعل' : '❌ غير مفعل';
          print('${i + 1}. ${data['name']} - $status - ترتيب: $order');
        }
      
      return sortedDocs;
    } catch (e) {
      print('خطأ في تحميل المرافق الطبية: $e');
      print('نوع الخطأ: ${e.runtimeType}');
      rethrow; // إعادة رمي الخطأ ليتم التعامل معه في FutureBuilder
    }
  }

  List<QueryDocumentSnapshot> getFilteredFacilities() {
    if (_searchQuery.isEmpty) {
      return _allFacilities;
    }
    
    return _allFacilities.where((facility) {
      final name = facility['name']?.toString().toLowerCase() ?? '';
      final searchLower = _searchQuery.toLowerCase();
      
      return name.contains(searchLower);
    }).toList();
  }

  bool _hasValidImageUrl(QueryDocumentSnapshot doc) {
    try {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) return false;
      
      final imageUrl = data['imageUrl'] as String?;
      return imageUrl != null && imageUrl.trim().isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: _isSearching
            ? IconButton(
                onPressed: () {
                  setState(() {
                    _isSearching = false;
                    _searchQuery = '';
                    _searchController.clear();
                  });
                },
                icon: Icon(Icons.close, color: Color.fromARGB(255, 34, 96, 129),),
              )
            : IconButton(
                onPressed: () {
                  setState(() {
                    _isSearching = true;
                  });
                },
                icon: Icon(Icons.search, color: Color.fromARGB(255, 34, 96, 129),),
              ),
        actions: [
          if (!_isSearching)
            IconButton(
              onPressed: () {
                Navigator.pop(context);
              },
              icon: Icon(Icons.arrow_back, color: Color.fromARGB(255, 34, 96, 129),),
            ),
        ],
        title: _isSearching
            ? TextField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'البحث عن مرافق طبية...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 16,
                  ),
                ),
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 16,
                ),
              )
            : Text(
                "المرافق الطبية",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: const Color.fromARGB(255, 34, 96, 129),
                  fontSize: 30,
                ),
              ),
      ),
                    body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            setState(() {
              // إعادة تحميل البيانات
            });
          },
          child: FutureBuilder<List<QueryDocumentSnapshot>>(
            future: fetchFacilities(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const OptimizedLoadingWidget(
                  message: 'جاري تحميل المرافق الطبية...',
                  color: Color.fromARGB(255, 34, 96, 129),
                );
              }
              
              if (snapshot.hasError) {
                print('خطأ في FutureBuilder: ${snapshot.error}');
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
                        'حدث خطأ في تحميل البيانات',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.red[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${snapshot.error}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            // إعادة تحميل البيانات
                          });
                        },
                        child: Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                );
              }
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              print('لا توجد بيانات في snapshot: hasData=${snapshot.hasData}, isEmpty=${snapshot.data?.isEmpty}');
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.medical_services_outlined,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'لا توجد مرافق طبية حالياً',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          // إعادة تحميل البيانات
                        });
                      },
                      child: Text('إعادة تحميل'),
                    ),
                  ],
                ),
              );
            }

            final facilities = _searchQuery.isEmpty ? snapshot.data! : getFilteredFacilities();
            print('عدد المرافق المعروضة: ${facilities.length}');

            return Padding(
              padding: const EdgeInsets.all(12.0),
              child: _searchQuery.isNotEmpty && facilities.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'لا يوجد مرافق تطابق البحث',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: facilities.length,
                      itemBuilder: (context, index) {
                        final doc = facilities[index];
                        final name = doc['name'] ?? '';
                        final isAvailable = doc['available'] ?? false;

                        return InkWell(
                          onTap: () {
                            if (isAvailable) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => FacilityDetailsScreen(
                                    facilityId: doc.id,
                                    facilityName: name,
                                  ),
                                ),
                              );
                            }
                          },
                          child: Container(
                            margin: EdgeInsets.symmetric(vertical: 10),
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.withOpacity(0.3),
                                  blurRadius: 10,
                                  offset: Offset(0, 5),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                // Facility name and status
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        name,
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: isAvailable ? Colors.black : Colors.grey,
                                        ),
                                        textAlign: TextAlign.right,
                                      ),
                                      if (!isAvailable) ...[
                                        SizedBox(height: 2),
                                        Text(
                                          'قريبا',
                                          style: TextStyle(
                                            color: Colors.grey,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          textAlign: TextAlign.right,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                SizedBox(width: 15),
                                // Facility image
                                Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isAvailable
                                          ? Color.fromARGB(255, 34, 96, 129)
                                          : Colors.grey,
                                      width: 2,
                                    ),
                                  ),
                                  child: ClipOval(
                                    child: _hasValidImageUrl(doc)
                                        ? Image.network(
                                            doc['imageUrl'],
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, error, stackTrace) {
                                              return Image.asset(
                                                'assets/images/center.png',
                                                fit: BoxFit.cover,
                                              );
                                            },
                                          )
                                        : Image.asset(
                                            'assets/images/center.png',
                                            fit: BoxFit.cover,
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            );
          },
        ),
        ),
      ),
    );
  }
}
