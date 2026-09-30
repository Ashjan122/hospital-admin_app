import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'admin_doctor_details_screen.dart';
import 'doctor_bookings_screen.dart';

class MyDoctorsScreen extends StatefulWidget {
  final String centerId;
  final String centerName;

  const MyDoctorsScreen({
    super.key,
    required this.centerId,
    required this.centerName,
  });

  @override
  State<MyDoctorsScreen> createState() => _MyDoctorsScreenState();
}

class _MyDoctorsScreenState extends State<MyDoctorsScreen> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _myDoctors = [];
  Map<String, int> _doctorTodayBookingsCount = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMyDoctors();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMyDoctors() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId');

    if (userId == null || userId.isEmpty) {
      if (!mounted) return;

      setState(() {
        _myDoctors = [];
        _doctorTodayBookingsCount = {};
        _isLoading = false;
      });

      return;
    }

    final now = DateTime.now();

    final today =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';

    final results = await Future.wait([
      // أطباء المستخدم الحالي فقط
      FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('myDoctors')
          .doc(userId)
          .collection('doctors')
          .get(),

      // حجوزات اليوم للمركز
      FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('appointments')
          .where('date', isEqualTo: today)
          .get(),
    ]);

    if (!mounted) return;

    final doctorsSnapshot =
        results[0] as QuerySnapshot<Map<String, dynamic>>;

    final bookingsSnapshot =
        results[1] as QuerySnapshot<Map<String, dynamic>>;

    // حساب حجوزات اليوم لكل طبيب
    final Map<String, int> bookingsCount = {};

    for (final bookingDoc in bookingsSnapshot.docs) {
      final data = bookingDoc.data();

      final doctorId = data['doctorId']?.toString();

      if (doctorId == null || doctorId.isEmpty) {
        continue;
      }

      bookingsCount[doctorId] = (bookingsCount[doctorId] ?? 0) + 1;
    }

    final doctors =
        doctorsSnapshot.docs.map((doc) {
          final data = doc.data();

          return {
            'doctorId': data['doctorId'] ?? doc.id,
            'name': data['name'] ?? 'طبيب غير معروف',
            'photoUrl': data['photoUrl'] ?? '',
            'specialization': data['specialization'] ?? 'غير محدد',
            'specializationId': data['specializationId'] ?? '',
            'phoneNumber': data['phoneNumber'] ?? '',
            'isBookingEnabled': data['isBookingEnabled'] ?? true,
            'isActive': data['isActive'] ?? true,
          };
        }).toList();

    doctors.sort((a, b) {
      final nameA = a['name']?.toString() ?? '';
      final nameB = b['name']?.toString() ?? '';

      return nameA.compareTo(nameB);
    });

    setState(() {
      _myDoctors = doctors;
      _doctorTodayBookingsCount = bookingsCount;
      _isLoading = false;
    });
  } catch (e) {
    debugPrint('Error loading my doctors: $e');

    if (!mounted) return;

    setState(() {
      _myDoctors = [];
      _doctorTodayBookingsCount = {};
      _isLoading = false;
    });
  }
}
  List<Map<String, dynamic>> _filterDoctors() {
    if (_searchQuery.trim().isEmpty) {
      return _myDoctors;
    }

    final query = _searchQuery.trim().toLowerCase();

    return _myDoctors.where((doctor) {
      final name = doctor['name']?.toString().toLowerCase() ?? '';
      final specialization =
          doctor['specialization']?.toString().toLowerCase() ?? '';
      final phone = doctor['phoneNumber']?.toString().toLowerCase() ?? '';

      return name.contains(query) ||
          specialization.contains(query) ||
          phone.contains(query);
    }).toList();
  }

  void _openDoctorDetails(String doctorId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => AdminDoctorDetailsScreen(
              doctorId: doctorId,
              centerId: widget.centerId!,
              centerName: widget.centerName,
            ),
      ),
    ).then((_) {
      if (mounted) {
        _loadMyDoctors();
      }
    });
  }

  void _openDoctorBookings(String doctorId, String doctorName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => DoctorBookingsScreen(
              doctorId: doctorId,
              centerId: widget.centerId!,
              doctorName: doctorName,
              centerName: widget.centerName,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            children: [
              const Text(
                'أطبائي',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                '${widget.centerName}',
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
            ],
          ),
          centerTitle: true,
          backgroundColor: const Color.fromARGB(255, 34, 96, 129),
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              onPressed: _loadMyDoctors,
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث',
            ),
          ],
        ),
        body: SafeArea(
          child: Container(
            color: Colors.grey[50],
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: Container(
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
                      },
                      decoration: InputDecoration(
                        hintText: 'البحث عن طبيب...',
                        prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                ),

                Expanded(child: _buildDoctorsList()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDoctorsList() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color.fromARGB(255, 34, 96, 129)),
            SizedBox(height: 16),
            Text(
              'جاري تحميل أطبائك...',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final doctors = _filterDoctors();

    if (_myDoctors.isEmpty) {
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
              'لم يتم اختيار أي أطباء',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    if (doctors.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'لم يتم العثور على طبيب يطابق البحث',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: doctors.length,
      itemBuilder: (context, index) {
        final doctorData = doctors[index];

        final doctorName = doctorData['name'] ?? 'طبيب غير معروف';

        final specialization = doctorData['specialization'] ?? 'غير محدد';

        final photoUrl =
            doctorData['photoUrl'] ??
            'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQupVHd_oeqnkds0k3EjT1SX4ctwwblwYP2Uw&s';

        final doctorId = doctorData['doctorId'] ?? '';
        final todayBookings =
            _doctorTodayBookingsCount[doctorId.toString()] ?? 0;

        final isBookingEnabled = doctorData['isBookingEnabled'] ?? true;

        final isActive = doctorData['isActive'] ?? true;

        return Card(
          color: Colors.white,
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 6,
            ),

            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 6),

                // الصورة فقط تفتح تفاصيل الطبيب
                GestureDetector(
                  onTap: () {
                    _openDoctorDetails(doctorId);
                  },
                  child: CircleAvatar(
                    radius: 28,
                    backgroundImage:
                        photoUrl.startsWith('http')
                            ? NetworkImage(photoUrl)
                            : null,
                    backgroundColor:
                        photoUrl.startsWith('http') ? null : Colors.grey[300],
                    child:
                        photoUrl.startsWith('http')
                            ? null
                            : Icon(
                              Icons.person,
                              size: 20,
                              color: Colors.grey[600],
                            ),
                    onBackgroundImageError: (exception, stackTrace) {},
                  ),
                ),
              ],
            ),

            title: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        doctorName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),

                      const SizedBox(height: 4),

                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color.fromARGB(
                            255,
                            156,
                            208,
                            235,
                          ).withAlpha(26),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          specialization,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color.fromARGB(255, 34, 96, 129),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 6),

                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (!isActive)
                      const Text(
                        'غير نشط',
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                    if (!isBookingEnabled)
                      const Text(
                        'الحجز متوقف',
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ],
            ),

            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(255, 34, 96, 129).withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$todayBookings حجز ',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color.fromARGB(255, 34, 96, 129),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.grey[400],
                  size: 15,
                ),
              ],
            ),
            // الضغط على الكارد يفتح حجوزات الطبيب
            onTap: () {
              _openDoctorBookings(doctorId, doctorName);
            },
          ),
        );
      },
    );
  }
}
