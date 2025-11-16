import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:hospital_admin_app/widgets/optimized_loading_widget.dart';
import 'package:hospital_admin_app/screens/callcenter_booking_screen.dart';



class CallcenterDoctorsScreen extends StatefulWidget {
  final String centerId;
  final String specId;
  final String specializationName;
  final String? subSpecialtyId; // معرف التخصص الفرعي (اختياري)

  const CallcenterDoctorsScreen({
    super.key,
    required this.centerId,
    required this.specId,
    required this.specializationName,
    this.subSpecialtyId,
  });

  @override
  State<CallcenterDoctorsScreen> createState() => _CallcenterDoctorsScreenState();
}

class _CallcenterDoctorsScreenState extends State<CallcenterDoctorsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<QueryDocumentSnapshot> _allDoctors = [];
  bool _isSearching = false;
  Stream<QuerySnapshot>? _doctorsStream;

  Future<List<QueryDocumentSnapshot>> fetchDoctorsOnce() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .doc(widget.specId)
          .collection('doctors')
          .get()
          .timeout(const Duration(seconds: 8));
      _allDoctors = snapshot.docs;
      return snapshot.docs;
    } catch (e) {
      print('خطأ في تحميل الأطباء: $e');
      return [];
    }
  }

  @override
  void initState() {
    super.initState();
    _doctorsStream = FirebaseFirestore.instance
        .collection('medicalFacilities')
        .doc(widget.centerId)
        .collection('specializations')
        .doc(widget.specId)
        .collection('doctors')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  List<QueryDocumentSnapshot> getFilteredDoctors() {
    // تصفية الأطباء المفعلين أولاً
    final activeDoctors = _allDoctors.where((doctor) {
      final data = doctor.data() as Map<String, dynamic>;
      final isActive = data['isActive'];
      // فقط الأطباء الذين لديهم isActive = true صراحة
      if (isActive != true) return false;
      
      // إذا كان هناك تخصص فرعي محدد، فلتر الأطباء حسب التخصص الفرعي
      if (widget.subSpecialtyId != null) {
        final doctorSubSpecialty = data['subSpecialization']?.toString();
        return doctorSubSpecialty == widget.subSpecialtyId;
      }
      
      return true;
    }).toList();
    
    // ترتيب الأطباء حسب أقرب يوم عمل قادم: غداً أولاً ثم بعد غد وهكذا
    final listToSort = List<QueryDocumentSnapshot>.from(activeDoctors);
    listToSort.sort((a, b) {
      final aData = a.data() as Map<String, dynamic>;
      final bData = b.data() as Map<String, dynamic>;

      final aWorkingDays = _getWorkingDaysList(aData['workingSchedule'] ?? {});
      final bWorkingDays = _getWorkingDaysList(bData['workingSchedule'] ?? {});

      final aOffset = _getNextWorkingOffset(aWorkingDays);
      final bOffset = _getNextWorkingOffset(bWorkingDays);
      if (aOffset != bOffset) return aOffset.compareTo(bOffset);

      // تعادل: أولوية غداً ثم اليوم ثم بقية الأيام
      final aPriority = _getWorkingDaysPriority(aWorkingDays);
      final bPriority = _getWorkingDaysPriority(bWorkingDays);
      if (aPriority != bPriority) return aPriority.compareTo(bPriority);

      // تعادل نهائي: الاسم الأبجدي
      final aName = (aData['docName'] ?? '').toString();
      final bName = (bData['docName'] ?? '').toString();
      return aName.compareTo(bName);
    });
    
    if (_searchQuery.isEmpty) {
      return listToSort;
    }
    
    return listToSort.where((doctor) {
      final data = doctor.data() as Map<String, dynamic>;
      final doctorName = data['docName']?.toString().toLowerCase() ?? '';
      final searchLower = _searchQuery.toLowerCase();
      
      return doctorName.contains(searchLower);
    }).toList();
  }

  // دالة لاستخراج قائمة أيام العمل
  List<String> _getWorkingDaysList(dynamic workingSchedule) {
    if (workingSchedule == null || workingSchedule.isEmpty) {
      return [];
    }

    Map<String, dynamic> scheduleMap;
    if (workingSchedule is Map) {
      scheduleMap = Map<String, dynamic>.from(workingSchedule);
    } else {
      return [];
    }

    List<String> workingDays = [];
    
    scheduleMap.forEach((day, value) {
      if (day == 'الأحد' || day == 'الاثنين' || day == 'الثلاثاء' || 
          day == 'الأربعاء' || day == 'الخميس' || day == 'الجمعة' || day == 'السبت') {
        workingDays.add(day);
      }
    });

    return workingDays;
  }

  // دالة لحساب أولوية أيام العمل (غداً أولاً ثم اليوم)
  int _getWorkingDaysPriority(List<String> workingDays) {
    if (workingDays.isEmpty) {
      return 999; // أقل أولوية للأطباء بدون أيام عمل
    }

    final now = DateTime.now();
    final today = _getArabicDayName(now.weekday);
    final tomorrow = _getArabicDayName(now.weekday == 7 ? 1 : now.weekday + 1);

    // أولوية 1: يعمل غداً
    if (workingDays.contains(tomorrow)) {
      return 1;
    }

    // أولوية 2: يعمل اليوم
    if (workingDays.contains(today)) {
      return 2;
    }

    // أولوية 3: يعمل في الأيام القادمة
    return 3;
  }

  // دالة لتحويل رقم اليوم إلى اسم عربي
  String _getArabicDayName(int weekday) {
    switch (weekday) {
      case 1: return 'الاثنين';
      case 2: return 'الثلاثاء';
      case 3: return 'الأربعاء';
      case 4: return 'الخميس';
      case 5: return 'الجمعة';
      case 6: return 'السبت';
      case 7: return 'الأحد';
      default: return '';
    }
  }

  String _getWorkingDaysText(dynamic workingSchedule) {
    if (workingSchedule == null || workingSchedule.isEmpty) {
      return 'أيام العمل: غير محدد';
    }

    // تحويل إلى Map إذا لم يكن كذلك
    Map<String, dynamic> scheduleMap;
    if (workingSchedule is Map) {
      scheduleMap = Map<String, dynamic>.from(workingSchedule);
    } else {
      return 'أيام العمل: غير محدد';
    }

    List<String> workingDays = [];
    
    scheduleMap.forEach((day, value) {
      // التحقق من أن اليوم موجود في قائمة الأيام العربية
      if (day == 'الأحد' || day == 'الاثنين' || day == 'الثلاثاء' || 
          day == 'الأربعاء' || day == 'الخميس' || day == 'الجمعة' || day == 'السبت') {
        // إذا كان اليوم موجود في الجدول، فهو يوم عمل
        workingDays.add(day);
      }
    });

    if (workingDays.isEmpty) {
      return 'أيام العمل: غير محدد';
    }

    // ترتيب الأيام حسب ترتيبها في الأسبوع
    final dayOrder = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
    workingDays.sort((a, b) => dayOrder.indexOf(a).compareTo(dayOrder.indexOf(b)));

    // تقسيم الأيام على أسطر متعددة إذا كانت كثيرة
    String result;
    if (workingDays.length <= 3) {
      // 3 أيام أو أقل - سطر واحد
      result = 'أيام العمل: ${workingDays.join(' - ')}';
    } else if (workingDays.length <= 5) {
      // 4-5 أيام - سطرين
      final firstLine = workingDays.take(3).join(' - ');
      final secondLine = workingDays.skip(3).join(' - ');
      result = 'أيام العمل: $firstLine\n$secondLine';
    } else {
      // 6-7 أيام - ثلاثة أسطر
      final firstLine = workingDays.take(3).join(' - ');
      final secondLine = workingDays.skip(3).take(3).join(' - ');
      final thirdLine = workingDays.skip(6).join(' - ');
      result = 'أيام العمل: $firstLine\n$secondLine';
      if (thirdLine.isNotEmpty) {
        result += '\n$thirdLine';
      }
    }
    
    return result;
  }

  // يحسب أقرب يوم عمل قادم للطبيب بالنسبة لليوم الحالي (1 = غداً، 2 = بعد غد، ... حتى 7)
  int _getNextWorkingOffset(List<String> workingDays) {
    if (workingDays.isEmpty) return 999;
    final now = DateTime.now();
    for (int offset = 1; offset <= 7; offset++) {
      final next = now.add(Duration(days: offset));
      final name = _getArabicDayName(next.weekday);
      if (workingDays.contains(name)) return offset;
    }
    return 999;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          actions: [
            _isSearching
                ? IconButton(
                    onPressed: () {
                      setState(() {
                        _isSearching = false;
                        _searchQuery = '';
                        _searchController.clear();
                      });
                    },
                    icon: Icon(Icons.close, color: Color(0xFF2FBDAF)),
                  )
                : IconButton(
                    onPressed: () {
                      setState(() {
                        _isSearching = true;
                      });
                    },
                    icon: Icon(Icons.search, color: Color(0xFF2FBDAF)),
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
                    hintText: 'البحث عن طبيب...',
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
                  "أطباء ${widget.specializationName}",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2FBDAF),
                    fontSize: 20,
                  ),
                ),
        ),
        body: SafeArea(
          child: StreamBuilder<QuerySnapshot>(
            stream: _doctorsStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const OptimizedLoadingWidget(
                  message: 'جاري تحميل الأطباء...',
                  color: Color(0xFF2FBDAF),
                );
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
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
                        'لا يوجد أطباء حالياً',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              }

              _allDoctors = snapshot.data!.docs;
              final doctors = getFilteredDoctors();
              
              // إذا لم يكن هناك أطباء مفعلين
              if (doctors.isEmpty) {
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
                        'لا يوجد أطباء حالياً',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              }
              
              if (_searchQuery.isNotEmpty && doctors.isEmpty) {
                return Center(
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
                        'لا يوجد أطباء تطابق البحث',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                itemCount: doctors.length,
                itemBuilder: (context, index) {
                  final doc = doctors[index];
                  final doctorData = doc.data() as Map<String, dynamic>;
                  final doctorName = doctorData['docName'] ?? 'طبيب غير معروف';
                  final dynamic rawPhoto = doctorData['photoUrl'];
                  final String photoUrl = (rawPhoto is String) ? rawPhoto.trim() : '';
                  final bool hasValidPhoto = photoUrl.startsWith('http');
                  const String fallbackUrl = 'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQupVHd_oeqnkds0k3EjT1SX4ctwwblwYP2Uw&s';
                  final String effectiveUrl = hasValidPhoto ? photoUrl : fallbackUrl;
                  // حالة العمل غداً وإتاحة الحجز
                  final List<String> workingDays = _getWorkingDaysList(doctorData['workingSchedule'] ?? {});
                  final String tomorrow = _getArabicDayName(DateTime.now().weekday == 7 ? 1 : DateTime.now().weekday + 1);
                  final bool worksTomorrow = workingDays.contains(tomorrow);
                  final bool isBookingEnabled = (doctorData['isBookingEnabled'] != false);
                  final Color statusColor = !isBookingEnabled
                      ? Colors.red
                      : (worksTomorrow ? Colors.green : Colors.red);
                  

                  


                  return GestureDetector(
                    key: ValueKey(doc.id),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (context) => BookingScreen(
                                centerId: widget.centerId,
                                specializationId: widget.specId,
                                doctorId: doc.id,
                                name: doctorName,
                                workingSchedule: Map<String, dynamic>.from(
                                  (doc.data() as Map<String, dynamic>)['workingSchedule'] ?? {},
                                ),
                              ),
                        ),
                      );
                    },
                    child: Card(
                      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      elevation: 6,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 60,
                              height: 60,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(50),
                                      child: Image.network(
                                        effectiveUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stack) {
                                          return Container(
                                            color: Colors.grey[300],
                                            child: const Icon(Icons.person, color: Colors.grey),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: 2,
                                    top: 2,
                                    child: Container(
                                      width: 12,
                                      height: 12,
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: statusColor,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(width: 16),

                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    doctorName,
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    _getWorkingDaysText(doctorData['workingSchedule'] ?? {}),
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios,
                              color: Colors.grey[600],
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
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
