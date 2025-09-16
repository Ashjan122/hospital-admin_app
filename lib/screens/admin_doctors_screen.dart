import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_doctor_details_screen.dart';
import 'add_doctor_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class AdminDoctorsScreen extends StatefulWidget {
  final String? centerId;
  final String? centerName;

  const AdminDoctorsScreen({
    super.key,
    required this.centerId,
    required this.centerName,
  });

  @override
  State<AdminDoctorsScreen> createState() => _AdminDoctorsScreenState();
}

class _AdminDoctorsScreenState extends State<AdminDoctorsScreen> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _allDoctors = [];
  bool _isLoadingMore = false;
  bool _hasMoreData = true;
  bool _isInitialLoading = true; // متغير لتتبع التحميل الأولي
  int _currentPage = 0;
  static const int _pageSize = 10;

  // Cache keys and duration
  static const String _cacheKey = 'allDoctorsCache';
  static const String _cacheTimestampKey = 'doctorsCacheTimestamp';
  static const Duration _cacheValidDuration = Duration(hours: 1); // Cache for 1 hour

  @override
  void initState() {
    super.initState();
    _loadDataWithCache();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // دالة تحميل البيانات مع Cache
  Future<void> _loadDataWithCache() async {
    // محاولة تحميل البيانات من Cache أولاً
    final cachedData = await _loadFromCache();
    if (cachedData != null) {
      setState(() {
        _allDoctors = cachedData;
        _currentPage = 0;
        _hasMoreData = cachedData.length > _pageSize;
        _isLoadingMore = false;
        _isInitialLoading = false;
      });
    }
    
    // تحميل البيانات الجديدة من Firebase في الخلفية
    _fetchDataInBackground();
  }

  // دالة تحميل البيانات من Cache
  Future<List<Map<String, dynamic>>?> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString(_cacheKey);
      final timestamp = prefs.getInt(_cacheTimestampKey);
      
      if (cachedData != null && timestamp != null) {
        final cacheAge = DateTime.now().millisecondsSinceEpoch - timestamp;
        final isValid = cacheAge < _cacheValidDuration.inMilliseconds;
        
        if (isValid) {
          final List<dynamic> decoded = jsonDecode(cachedData);
          return decoded.cast<Map<String, dynamic>>();
        }
      }
      return null;
    } catch (e) {
      print('Error loading from cache: $e');
      return null;
    }
  }

  // دالة حفظ البيانات في Cache
  Future<void> _saveToCache(List<Map<String, dynamic>> doctors) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encodedData = jsonEncode(doctors);
      await prefs.setString(_cacheKey, encodedData);
      await prefs.setInt(_cacheTimestampKey, DateTime.now().millisecondsSinceEpoch);
      print('Doctors data cached successfully');
    } catch (e) {
      print('Error saving to cache: $e');
    }
  }


  // دالة تحميل البيانات في الخلفية
  Future<void> _fetchDataInBackground() async {
    try {
      final newData = await _fetchDoctorsFromFirebase();
      if (newData.isNotEmpty) {
        setState(() {
          _allDoctors = newData;
          _currentPage = 0;
          _hasMoreData = newData.length > _pageSize;
          _isLoadingMore = false;
          _isInitialLoading = false;
        });
        // حفظ البيانات الجديدة في Cache
        await _saveToCache(newData);
      }
    } catch (e) {
      print('Background fetch error: $e');
    }
  }

  // دالة جلب البيانات من Firebase
  Future<List<Map<String, dynamic>>> _fetchDoctorsFromFirebase() async {
    if (widget.centerId == null) {
      return [];
    }

    try {
      final specializationsSnapshot = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .get()
          .timeout(const Duration(seconds: 8));

      List<Map<String, dynamic>> allDoctors = [];
      List<Future<void>> futures = [];
      
      for (var specDoc in specializationsSnapshot.docs) {
        futures.add(_fetchDoctorsFromSpecialization(specDoc, allDoctors));
      }
      
      await Future.wait(futures);
      return allDoctors;
    } catch (e) {
      print('Error fetching doctors from Firebase: $e');
      return [];
    }
  }

  Future<void> fetchAllDoctors() async {
    if (widget.centerId == null) {
      setState(() {
        _allDoctors = [];
        _currentPage = 0;
        _hasMoreData = false;
        _isLoadingMore = false;
      });
      return;
    }

    try {
      // جلب جميع التخصصات مع timeout
      final specializationsSnapshot = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .get()
          .timeout(const Duration(seconds: 8));

      List<Map<String, dynamic>> allDoctors = [];
      List<Future<void>> futures = [];
      
      // البحث في كل تخصص بشكل متوازي
      for (var specDoc in specializationsSnapshot.docs) {
        futures.add(_fetchDoctorsFromSpecialization(specDoc, allDoctors));
      }
      
      await Future.wait(futures);
      
      setState(() {
        _allDoctors = allDoctors;
        _currentPage = 0;
        _hasMoreData = allDoctors.length > _pageSize;
        _isLoadingMore = false;
        _isInitialLoading = false; // انتهاء التحميل الأولي
      });
    } catch (e) {
      print('Error fetching doctors: $e');
      setState(() {
        _allDoctors = [];
        _currentPage = 0;
        _hasMoreData = false;
        _isLoadingMore = false;
        _isInitialLoading = false; // انتهاء التحميل الأولي حتى في حالة الخطأ
      });
    }
  }

  Future<void> _fetchDoctorsFromSpecialization(QueryDocumentSnapshot specDoc, List<Map<String, dynamic>> allDoctors) async {
    try {
      final specializationData = specDoc.data() as Map<String, dynamic>?;
      final specializationName = specializationData?['specName'] ?? specDoc.id;
      
      final doctorsSnapshot = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .doc(specDoc.id)
          .collection('doctors')
          .get()
          .timeout(const Duration(seconds: 5));
      
      for (var doctorDoc in doctorsSnapshot.docs) {
        final doctorData = doctorDoc.data();
        final doctorId = doctorDoc.id;
        
        // جلب معلومات الطبيب من قاعدة البيانات المركزية
        String doctorName = 'طبيب غير معروف';
        String doctorPhone = '';
        String photoUrl = 'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQupVHd_oeqnkds0k3EjT1SX4ctwwblwYP2Uw&s';
        
        try {
          final centralDoctorDoc = await FirebaseFirestore.instance
              .collection('allDoctors')
              .doc(doctorId)
              .get()
              .timeout(const Duration(seconds: 3));
          
          if (centralDoctorDoc.exists) {
            final centralDoctorData = centralDoctorDoc.data()!;
            doctorName = centralDoctorData['name'] ?? 'طبيب غير معروف';
            doctorPhone = centralDoctorData['phoneNumber'] ?? '';
            photoUrl = centralDoctorData['photoUrl'] ?? photoUrl;
          }
        } catch (e) {
          // إذا فشل في جلب البيانات من المركزية، استخدم المعرف
          doctorName = doctorId;
        }
        
        // إضافة معلومات إضافية لكل طبيب
        doctorData['name'] = doctorName;
        doctorData['phoneNumber'] = doctorPhone;
        doctorData['photoUrl'] = photoUrl;
        doctorData['specialization'] = specializationName;
        doctorData['doctorId'] = doctorId;
        doctorData['specializationId'] = specDoc.id;
        allDoctors.add(doctorData);
      }
    } catch (e) {
      // Error loading doctors from specialization
    }
  }

  // دالة جلب الأطباء على دفعات (10 أطباء في كل مرة)
  List<Map<String, dynamic>> getPaginatedDoctors() {
    final filteredDoctors = filterDoctors();
    final startIndex = 0;
    final endIndex = (_currentPage + 1) * _pageSize;
    
    // إذا وصلنا لنهاية القائمة، نرجع جميع الأطباء
    if (endIndex >= filteredDoctors.length) {
      return filteredDoctors;
    }
    
    // نرجع الأطباء من البداية حتى النقطة الحالية
    return filteredDoctors.sublist(startIndex, endIndex);
  }

  // دالة إعادة تعيين الصفحة عند تغيير البحث
  void _resetPagination() {
    setState(() {
      _currentPage = 0;
      final filteredDoctors = filterDoctors();
      _hasMoreData = filteredDoctors.length > _pageSize;
      _isLoadingMore = false;
    });
  }

  // دالة تحميل المزيد من الأطباء (10 أطباء إضافية)
  Future<void> loadMoreDoctors() async {
    if (_isLoadingMore || !_hasMoreData) return;
    
    setState(() {
      _isLoadingMore = true;
    });
    
    // محاكاة تأخير للعرض (500 مللي ثانية)
    await Future.delayed(const Duration(milliseconds: 500));
    
    setState(() {
      _currentPage++; // زيادة رقم الصفحة
      final filteredDoctors = filterDoctors();
      // التحقق من وجود المزيد من الأطباء
      final nextPageEnd = (_currentPage + 1) * _pageSize;
      _hasMoreData = nextPageEnd < filteredDoctors.length;
      _isLoadingMore = false;
    });
  }

  List<Map<String, dynamic>> filterDoctors() {
    if (_searchQuery.isEmpty) return _allDoctors;
    
    return _allDoctors.where((doctor) {
      final name = doctor['name']?.toString().toLowerCase() ?? '';
      final specialization = doctor['specialization']?.toString().toLowerCase() ?? '';
      final phone = doctor['phoneNumber']?.toString().toLowerCase() ?? '';
      return name.contains(_searchQuery.toLowerCase()) ||
             specialization.contains(_searchQuery.toLowerCase()) ||
             phone.contains(_searchQuery.toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'إدارة الأطباء - ${widget.centerName ?? 'المركز الطبي'}',
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
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AddDoctorScreen(
                      centerId: widget.centerId!,
                      centerName: widget.centerName!,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.add),
              tooltip: 'إضافة طبيب جديد',
            ),
          ],
        ),
        body: SafeArea(
          child: Container(
            color: Colors.grey[50],
            child: Column(
              children: [
                // Search and Add section
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: Column(
                    children: [
                      // Search bar
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (value) {
                            setState(() {
                              _searchQuery = value;
                            });
                            _resetPagination(); // إعادة تعيين الصفحة عند تغيير البحث
                          },
                          decoration: InputDecoration(
                            hintText: 'البحث عن طبيب...',
                            prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Doctors list
                Expanded(
                  child: _buildDoctorsList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDoctorsList() {
    if (_isInitialLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: Color(0xFF2FBDAF),
            ),
            SizedBox(height: 16),
            Text(
              'جاري تحميل الأطباء...',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    // في حالة وجود خطأ في التحميل أو عدم وجود بيانات
    if (_allDoctors.isEmpty && !_isInitialLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد أطباء في هذا المركز',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'لم يتم العثور على أي أطباء مسجلين',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _isInitialLoading = true;
                });
                fetchAllDoctors();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2FBDAF),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    final filteredDoctors = filterDoctors();
    
    if (filteredDoctors.isEmpty && !_isInitialLoading) {
      return Center(
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
                  ? 'لا يوجد أطباء في هذا المركز'
                  : 'لم يتم العثور على أطباء يطابقون البحث',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    final paginatedDoctors = getPaginatedDoctors();
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: paginatedDoctors.length + (_hasMoreData ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == paginatedDoctors.length) {
          // Loading more indicator
          if (_isLoadingMore) {
            return Container(
              padding: const EdgeInsets.all(16.0),
              child: const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 8),
                    Text(
                      'جاري تحميل المزيد من الأطباء...',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            );
          } else if (_hasMoreData) {
            // Load more automatically when reaching the end
            WidgetsBinding.instance.addPostFrameCallback((_) {
              loadMoreDoctors();
            });
            return const SizedBox.shrink();
          }
          return const SizedBox.shrink();
        }

        final doctorData = paginatedDoctors[index];
        final doctorName = doctorData['name'] ?? 'طبيب غير معروف';
        final specialization = doctorData['specialization'] ?? 'غير محدد';
        final photoUrl = doctorData['photoUrl'] ?? 
            'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQupVHd_oeqnkds0k3EjT1SX4ctwwblwYP2Uw&s';
        final doctorId = doctorData['doctorId'] ?? '';
        final isBookingEnabled = doctorData['isBookingEnabled'] ?? true;

        return Card(
          color: isBookingEnabled ? Colors.white : Colors.orange[50],
          margin: EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            contentPadding: EdgeInsets.all(16),
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(width: 12),
                CircleAvatar(
                  radius: 30,
                  backgroundImage: photoUrl.startsWith('http') 
                      ? NetworkImage(photoUrl)
                      : null,
                  backgroundColor: photoUrl.startsWith('http') 
                      ? null 
                      : Colors.grey[300],
                  child: photoUrl.startsWith('http') 
                      ? null 
                      : Icon(
                          Icons.person,
                          size: 30,
                          color: Colors.grey[600],
                        ),
                  onBackgroundImageError: (exception, stackTrace) {
                    // Handle image error
                  },
                ),
              ],
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doctorName,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2FBDAF).withAlpha(26),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    specialization,
                    style: TextStyle(
                      fontSize: 12,
                      color: const Color(0xFF2FBDAF),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            trailing: Icon(
              Icons.arrow_forward_ios,
              color: Colors.grey[400],
              size: 20,
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AdminDoctorDetailsScreen(
                    doctorId: doctorId,
                    centerId: widget.centerId!,
                    centerName: widget.centerName,
                  ),
                ),
              ).then((result) {
                // تحديث القائمة عند العودة من تفاصيل الطبيب
                if (mounted) {
                  fetchAllDoctors();
                }
              });
            },
          ),
        );
      },
    );
  }

}
