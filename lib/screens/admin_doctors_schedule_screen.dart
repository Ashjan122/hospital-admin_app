import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

class AdminDoctorsScheduleScreen extends StatefulWidget {
  final String centerId;
  final String? centerName;
  final String? selectedDoctorId; // معامل جديد لاختيار طبيب محدد

  const AdminDoctorsScheduleScreen({
    super.key,
    required this.centerId,
    this.centerName,
    this.selectedDoctorId,
  });

  @override
  State<AdminDoctorsScheduleScreen> createState() => _AdminDoctorsScheduleScreenState();
}

class _AdminDoctorsScheduleScreenState extends State<AdminDoctorsScheduleScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Cache keys and duration
  late final String _cacheKey;
  late final String _cacheTimestampKey;
  final Duration _cacheValidDuration = const Duration(hours: 6); // Cache for 6 hours

  @override
  void initState() {
    super.initState();
    // تهيئة Cache keys
    _cacheKey = 'doctors_schedule_${widget.centerId}';
    _cacheTimestampKey = 'doctors_schedule_timestamp_${widget.centerId}';
    
    // تجديد Cache تلقائياً عند فتح الشاشة إذا كان قديم
    _checkAndRefreshCache();
  }

  // دالة للتحقق من Cache وتجديده تلقائياً إذا كان قديم
  Future<void> _checkAndRefreshCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_cacheTimestampKey);
      
      if (timestamp != null) {
        final cacheAge = DateTime.now().millisecondsSinceEpoch - timestamp;
        final isExpired = cacheAge >= _cacheValidDuration.inMilliseconds;
        
        if (isExpired) {
          print('Cache expired, will refresh on next load');
          await _clearCache();
        }
      }
    } catch (e) {
      print('Error checking cache: $e');
    }
  }

  Future<List<Map<String, dynamic>>> fetchAllDoctors() async {
    try {
      // محاولة تحميل البيانات من Cache أولاً
      final cachedData = await _loadFromCache();
      if (cachedData != null) {
        print('Loading doctors from cache - ${cachedData.length} doctors');
        return cachedData;
      }
      
      print('Cache miss - fetching doctors from Firestore...');
      
      // جلب جميع التخصصات
      final specializationsSnapshot = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .get();

      List<Map<String, dynamic>> allDoctors = [];
      
      // تحميل الأطباء بالتوازي بدلاً من متسلسل
      List<Future<void>> futures = [];
      
      for (var specDoc in specializationsSnapshot.docs) {
        futures.add(_loadDoctorsFromSpecialization(specDoc, allDoctors));
      }
      
      // انتظار اكتمال جميع الطلبات
      await Future.wait(futures);
      
      // حفظ البيانات في Cache
      if (allDoctors.isNotEmpty) {
        await _saveToCache(allDoctors);
        print('Cached ${allDoctors.length} doctors for 6 hours');
      }
      
      return allDoctors;
    } catch (e) {
      print('Error fetching doctors: $e');
      return [];
    }
  }

  // دالة منفصلة لتحميل الأطباء من تخصص واحد
  Future<void> _loadDoctorsFromSpecialization(
    DocumentSnapshot specDoc,
    List<Map<String, dynamic>> allDoctors,
  ) async {
    try {
      final specializationData = specDoc.data() as Map<String, dynamic>? ?? {};
      final specializationName = specializationData['specName'] ?? specDoc.id;
      
      final doctorsSnapshot = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .doc(specDoc.id)
          .collection('doctors')
          .get();
      
      for (var doctorDoc in doctorsSnapshot.docs) {
        final doctorData = doctorDoc.data();
        
        // التحقق من أن الطبيب نشط (غير معطل)
        final isActive = doctorData['isActive'] ?? true;
        if (!isActive) {
          continue; // تخطي الأطباء المعطلين
        }
        
        // إضافة معلومات إضافية لكل طبيب
        doctorData['specialization'] = specializationName;
        doctorData['doctorId'] = doctorDoc.id;
        doctorData['specializationId'] = specDoc.id;
        allDoctors.add(doctorData);
      }
    } catch (e) {
      print('Error loading doctors from specialization ${specDoc.id}: $e');
    }
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
      
      // حفظ البيانات بالتوازي
      await Future.wait([
        prefs.setString(_cacheKey, encodedData),
        prefs.setInt(_cacheTimestampKey, DateTime.now().millisecondsSinceEpoch),
      ]);
      
      print('Doctors schedule data cached successfully - ${doctors.length} doctors');
    } catch (e) {
      print('Error saving to cache: $e');
    }
  }

  // دالة حذف Cache
  Future<void> _clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_cacheTimestampKey);
      print('Schedule cache cleared successfully');
    } catch (e) {
      print('Error clearing cache: $e');
    }
  }

  List<Map<String, dynamic>> filterDoctors(List<Map<String, dynamic>> doctors) {
    // إذا كان هناك طبيب محدد، اعرضه فقط
    if (widget.selectedDoctorId != null) {
      return doctors.where((doctorData) {
        return doctorData['doctorId'] == widget.selectedDoctorId;
      }).toList();
    }
    
    // إذا كان هناك بحث، طبق الفلتر
    if (_searchQuery.isNotEmpty) {
      return doctors.where((doctorData) {
        final doctorName = doctorData['docName']?.toString().toLowerCase() ?? '';
        final specialization = doctorData['specialization']?.toString().toLowerCase() ?? '';
        
        return doctorName.contains(_searchQuery.toLowerCase()) ||
               specialization.contains(_searchQuery.toLowerCase());
      }).toList();
    }
    
    return doctors;
  }

  String formatWorkingSchedule(Map<String, dynamic>? workingSchedule) {
    if (workingSchedule == null) return 'غير محدد';
    
    List<String> scheduleParts = [];
    
    // أيام الأسبوع بالعربية (كما هي مخزنة في قاعدة البيانات)
    final days = [
      'الأحد',
      'الاثنين', 
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
      'السبت',
    ];
    
    days.forEach((arabicDay) {
      final daySchedule = workingSchedule[arabicDay];
      if (daySchedule != null) {
        final morning = daySchedule['morning'];
        final evening = daySchedule['evening'];
        
        if (morning != null) {
          final startTime = morning['start'] ?? '';
          final endTime = morning['end'] ?? '';
          if (startTime.isNotEmpty && endTime.isNotEmpty) {
            scheduleParts.add('$arabicDay (صباحاً): $startTime - $endTime');
          }
        }
        
        if (evening != null) {
          final startTime = evening['start'] ?? '';
          final endTime = evening['end'] ?? '';
          if (startTime.isNotEmpty && endTime.isNotEmpty) {
            scheduleParts.add('$arabicDay (مساءً): $startTime - $endTime');
          }
        }
      }
    });
    
    return scheduleParts.isEmpty ? 'غير محدد' : scheduleParts.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title:Column(children: [ Text(
            widget.selectedDoctorId != null 
                ? 'جدول الطبيب'
                : (widget.centerName != null ? 'جدول الأطباء' : 'جدول الأطباء'),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text('${widget.centerName}',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white,
            ),
            ),
          ]),
          centerTitle: true,
          backgroundColor: const Color(0xFF2FBDAF),
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              onPressed: () async {
                // إظهار رسالة تحديث
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('جاري تحديث البيانات...'),
                    duration: Duration(seconds: 1),
                  ),
                );
                
                // حذف الكاش وإعادة تحميل البيانات
                await _clearCache();
                setState(() {
                  // إعادة بناء الواجهة لتحميل البيانات الجديدة
                });
                
                // إظهار رسالة نجاح
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تم تحديث البيانات بنجاح'),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث البيانات',
            ),
          ],
        ),
        body: Column(
          children: [
            // Search section - مخفي إذا كان هناك طبيب محدد
            if (widget.selectedDoctorId == null)
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
                    hintText: 'البحث في الأطباء...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),
            
            // Weekly schedule table
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: fetchAllDoctors(),
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
                            'حدث خطأ في تحميل جدول الأطباء',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final doctors = snapshot.data ?? [];
                  final filteredDoctors = filterDoctors(doctors);

                  if (filteredDoctors.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _searchQuery.isEmpty ? Icons.medical_services : Icons.search_off,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isEmpty 
                                ? 'لا يوجد أطباء حالياً'
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

                  return SingleChildScrollView(
                    scrollDirection: widget.selectedDoctorId != null ? Axis.vertical : Axis.horizontal,
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: widget.selectedDoctorId != null 
                            ? Center(child: _buildWeeklyScheduleTable(filteredDoctors))
                            : _buildWeeklyScheduleTable(filteredDoctors),
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

  Widget _buildWeeklyScheduleTable(List<Map<String, dynamic>> doctors) {
    final days = [
      'الأحد',
      'الاثنين', 
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
      'السبت',
    ];

    return Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                spreadRadius: 1,
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: DataTable(
        headingTextStyle: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Color(0xFF2FBDAF),
          fontSize: 12,
        ),
        dataTextStyle: const TextStyle(fontSize: 10),
        dataRowMinHeight: 80,
        dataRowMaxHeight: 80,
        headingRowHeight: 60,
                                   columns: [
            const DataColumn(label: Text('اليوم')),
            ...doctors.map((doctor) {
              final doctorName = doctor['docName'] ?? 'طبيب غير معروف';
              final specialization = doctor['specialization'] ?? 'تخصص غير معروف';
              return DataColumn(
                label: Container(
                  constraints: const BoxConstraints(maxWidth: 100),
                  child: Column(
                    children: [
                      Text(
                        doctorName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        specialization,
                        style: TextStyle(
                          fontSize: 8,
                          color: Colors.grey[600],
                        ),
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: () => _exportDoctorScheduleToPDF(doctor),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2FBDAF).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(
                            Icons.picture_as_pdf,
                            size: 12,
                            color: Color(0xFF2FBDAF),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ],
        rows: days.map((day) {
          return DataRow(
            cells: [
              DataCell(
                Container(
                  padding: const EdgeInsets.all(8),
                                     child: Text(
                     day,
                     style: const TextStyle(
                       fontWeight: FontWeight.bold,
                       fontSize: 12,
                       color: Color(0xFF2FBDAF),
                     ),
                   ),
                ),
              ),
              ...doctors.map((doctor) {
                final workingSchedule = doctor['workingSchedule'] as Map<String, dynamic>?;
                final daySchedule = workingSchedule?[day];
                String scheduleText = 'لا يوجد دوام';
                Color cellColor = Colors.grey[100]!;
                Color textColor = Colors.grey[600]!;

                if (daySchedule != null) {
                  final morning = daySchedule['morning'];
                  final evening = daySchedule['evening'];
                  List<String> periods = [];

                  if (morning != null) {
                    final startTime = morning['start'] ?? '';
                    final endTime = morning['end'] ?? '';
                    if (startTime.isNotEmpty && endTime.isNotEmpty) {
                      periods.add('صباحاً: $startTime-$endTime');
                    }
                  }

                  if (evening != null) {
                    final startTime = evening['start'] ?? '';
                    final endTime = evening['end'] ?? '';
                    if (startTime.isNotEmpty && endTime.isNotEmpty) {
                      periods.add('مساءً: $startTime-$endTime');
                    }
                  }

                  if (periods.isNotEmpty) {
                    scheduleText = periods.join('\n');
                    cellColor = const Color(0xFF2FBDAF).withOpacity(0.1);
                    textColor = const Color(0xFF2FBDAF);
                  }
                }

                return DataCell(
                  GestureDetector(
                    onTap: () => _showEditScheduleDialog(doctor, day),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: cellColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.grey[300]!,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            scheduleText,
                            style: TextStyle(
                              fontSize: 9,
                              color: textColor,
                              height: 1.1,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Icon(
                            Icons.edit,
                            size: 12,
                            color: Colors.grey[500],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ],
          );
        }).toList(),
      ),
    );
  }

  void _showEditScheduleDialog(Map<String, dynamic> doctor, String day) {
    final doctorName = doctor['docName'] ?? 'طبيب غير معروف';
    final workingSchedule = doctor['workingSchedule'] as Map<String, dynamic>? ?? {};
    final daySchedule = workingSchedule[day] ?? {};
    
    // تحديد الأوقات الافتراضية
    final morningStartController = TextEditingController(
      text: daySchedule['morning']?['start'] ?? '09:00'
    );
    final morningEndController = TextEditingController(
      text: daySchedule['morning']?['end'] ?? '12:00'
    );
    final eveningStartController = TextEditingController(
      text: daySchedule['evening']?['start'] ?? '18:00'
    );
    final eveningEndController = TextEditingController(
      text: daySchedule['evening']?['end'] ?? '23:00'
    );
    
    // تفعيل الفترات تلقائياً إذا لم تكن موجودة
    bool hasMorning = daySchedule['morning'] != null;
    bool hasEvening = daySchedule['evening'] != null;
    bool isSaving = false; // متغير لتتبع حالة الحفظ
    
    // إذا لم تكن هناك فترات محددة، تفعيل الفترة الصباحية تلقائياً
    if (!hasMorning && !hasEvening) {
      hasMorning = true;
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('تعديل جدول $doctorName - $day'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Morning shift
                Row(
                  children: [
                    Checkbox(
                      value: hasMorning,
                      onChanged: (value) {
                        setState(() {
                          hasMorning = value ?? false;
                          if (!hasMorning) {
                            morningStartController.clear();
                            morningEndController.clear();
                          } else {
                            // إعادة تعيين الأوقات الافتراضية إذا كانت فارغة
                            if (morningStartController.text.isEmpty) {
                              morningStartController.text = '09:00';
                            }
                            if (morningEndController.text.isEmpty) {
                              morningEndController.text = '12:00';
                            }
                          }
                        });
                      },
                    ),
                    const Text('الفترة الصباحية'),
                  ],
                ),
                if (hasMorning) ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: morningStartController,
                          decoration: const InputDecoration(
                            labelText: 'وقت البداية',
                            hintText: 'مثال: 09:00',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: morningEndController,
                          decoration: const InputDecoration(
                            labelText: 'وقت النهاية',
                            hintText: 'مثال: 12:00',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                
                // Evening shift
                Row(
                  children: [
                    Checkbox(
                      value: hasEvening,
                      onChanged: (value) {
                        setState(() {
                          hasEvening = value ?? false;
                          if (!hasEvening) {
                            eveningStartController.clear();
                            eveningEndController.clear();
                          } else {
                            // إعادة تعيين الأوقات الافتراضية إذا كانت فارغة
                            if (eveningStartController.text.isEmpty) {
                              eveningStartController.text = '18:00';
                            }
                            if (eveningEndController.text.isEmpty) {
                              eveningEndController.text = '23:00';
                            }
                          }
                        });
                      },
                    ),
                    const Text('الفترة المسائية'),
                  ],
                ),
                if (hasEvening) ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: eveningStartController,
                          decoration: const InputDecoration(
                            labelText: 'وقت البداية',
                            hintText: 'مثال: 18:00',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: eveningEndController,
                          decoration: const InputDecoration(
                            labelText: 'وقت النهاية',
                            hintText: 'مثال: 23:00',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: isSaving ? null : () async {
                setState(() {
                  isSaving = true;
                });
                
                // تحديث البيانات المحلية فوراً
                final workingSchedule = doctor['workingSchedule'] as Map<String, dynamic>? ?? {};
                Map<String, dynamic> daySchedule = {};
                
                if (hasMorning && morningStartController.text.isNotEmpty && morningEndController.text.isNotEmpty) {
                  daySchedule['morning'] = {
                    'start': morningStartController.text,
                    'end': morningEndController.text,
                  };
                }
                
                if (hasEvening && eveningStartController.text.isNotEmpty && eveningEndController.text.isNotEmpty) {
                  daySchedule['evening'] = {
                    'start': eveningStartController.text,
                    'end': eveningEndController.text,
                  };
                }
                
                // تحديث الجدول المحلي
                workingSchedule[day] = daySchedule.isEmpty ? null : daySchedule;
                workingSchedule.removeWhere((key, value) => value == null);
                doctor['workingSchedule'] = Map<String, dynamic>.from(workingSchedule);
                
                // إغلاق النافذة فوراً
                Navigator.of(context).pop();
                
                // تحديث Firestore في الخلفية
                _updateDoctorSchedule(
                  doctor,
                  day,
                  hasMorning,
                  hasEvening,
                  morningStartController.text,
                  morningEndController.text,
                  eveningStartController.text,
                  eveningEndController.text,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2FBDAF),
                foregroundColor: Colors.white,
              ),
              child: isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateDoctorSchedule(
    Map<String, dynamic> doctor,
    String day,
    bool hasMorning,
    bool hasEvening,
    String morningStart,
    String morningEnd,
    String eveningStart,
    String eveningEnd,
  ) async {
    try {
      final doctorId = doctor['doctorId'];
      final specializationId = doctor['specializationId'];
      
      // Update in Firestore
      await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .doc(specializationId)
          .collection('doctors')
          .doc(doctorId)
          .update({
        'workingSchedule': doctor['workingSchedule'],
      });

      // مسح Cache بعد التحديث لضمان البيانات الحديثة
      await _clearCache();
      
      // عرض رسالة نجاح فقط
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تحديث جدول $day بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ في تحديث الجدول: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // دالة تصدير جدول الطبيب إلى PDF
  Future<void> _exportDoctorScheduleToPDF(Map<String, dynamic> doctor) async {
    try {
      // إظهار مؤشر التحميل
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(
            color: Color(0xFF2FBDAF),
          ),
        ),
      );

      // إنشاء مستند PDF جديد
      final PdfDocument document = PdfDocument();
      
      // إضافة صفحة جديدة
      final PdfPage page = document.pages.add();
      final PdfGraphics graphics = page.graphics;
      final Size pageSize = page.getClientSize();
      
      // تحميل صورة الشعار
      final ByteData logoData = await rootBundle.load('assets/images/logo.png');
      final PdfBitmap logoImage = PdfBitmap(logoData.buffer.asUint8List());
      
      // علامة مائية شفافة في منتصف الصفحة
      graphics.save();
      graphics.setTransparency(0.08);
      final double watermarkWidth = pageSize.width * 0.8;
      final double watermarkHeight = watermarkWidth; // مربع لتبسيط الوضع
      final double watermarkX = (pageSize.width - watermarkWidth) / 2;
      final double watermarkY = (pageSize.height - watermarkHeight) / 2;
      graphics.drawImage(
        logoImage,
        Rect.fromLTWH(watermarkX, watermarkY, watermarkWidth, watermarkHeight),
      );
      graphics.restore();
      
      // تحميل خط Noto Naskh Arabic المحلي
      final ByteData fontData = await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf');
      final List<int> fontBytes = fontData.buffer.asUint8List();
      final PdfFont font = PdfTrueTypeFont(fontBytes, 16, style: PdfFontStyle.bold);
      final PdfFont titleFont = PdfTrueTypeFont(fontBytes, 20, style: PdfFontStyle.bold);
      final PdfFont headerFont = PdfTrueTypeFont(fontBytes, 18, style: PdfFontStyle.bold);
      
      // معلومات الطبيب
      final doctorName = doctor['docName'] ?? 'طبيب غير معروف';
      final specialization = doctor['specialization'] ?? 'تخصص غير معروف';
      final centerName = widget.centerName ?? 'المركز الطبي';
      
      // العنوان الرئيسي - اسم المركز مع شعار أعلى يمين
      // رسم الشعار أعلى يمين بمقاس صغير
      const double topPadding = 20;
      const double rightPadding = 20;
      const double logoWidth = 40;
      const double logoHeight = 40;
      final double logoX = pageSize.width - rightPadding - logoWidth;
      final double logoY = topPadding;
      graphics.drawImage(logoImage, Rect.fromLTWH(logoX, logoY, logoWidth, logoHeight));

      // اسم المركز في المنتصف
      graphics.drawString(
        centerName,
        titleFont,
        bounds: Rect.fromLTWH(0, 20, pageSize.width, 40),
        format: PdfStringFormat(alignment: PdfTextAlignment.center, textDirection: PdfTextDirection.rightToLeft),
      );
      
      // معلومات الطبيب (اسم الطبيب وبجانبه التخصص بين قوسين)
      graphics.drawString(
        'الطبيب: $doctorName ($specialization)',
        headerFont,
        bounds: Rect.fromLTWH(0, 70, pageSize.width, 35),
        format: PdfStringFormat(alignment: PdfTextAlignment.center, textDirection: PdfTextDirection.rightToLeft),
      );
      
      // إنشاء جدول الأيام
      final workingSchedule = doctor['workingSchedule'] as Map<String, dynamic>? ?? {};
      final days = [
        'الأحد',
        'الاثنين', 
        'الثلاثاء',
        'الأربعاء',
        'الخميس',
        'الجمعة',
        'السبت',
      ];
      
      // عنوان الجدول
      graphics.drawString(
        'جدول الدوام الأسبوعي',
        headerFont,
        bounds: Rect.fromLTWH(0, 115, pageSize.width, 35),
        format: PdfStringFormat(alignment: PdfTextAlignment.center, textDirection: PdfTextDirection.rightToLeft),
      );
      
      // رسم الجدول - تكبير الجدول ليملأ الصفحة
      double yPosition = 160;
      const double rowHeight = 50;
      const double dayColumnWidth = 120;
      const double scheduleColumnWidth = 360;
      
      // رؤوس الجدول - الأيام في اليمين
      graphics.drawRectangle(
        bounds: Rect.fromLTWH(380, yPosition, dayColumnWidth, rowHeight),
        pen: PdfPen(PdfColor(47, 189, 175)),
      );
      graphics.drawString(
        'اليوم',
        headerFont,
        bounds: Rect.fromLTWH(380, yPosition + 15, dayColumnWidth, rowHeight),
        format: PdfStringFormat(alignment: PdfTextAlignment.center, textDirection: PdfTextDirection.rightToLeft),
      );
      
      graphics.drawRectangle(
        bounds: Rect.fromLTWH(20, yPosition, scheduleColumnWidth, rowHeight),
        pen: PdfPen(PdfColor(47, 189, 175)),
      );
      graphics.drawString(
        'أوقات الدوام',
        headerFont,
        bounds: Rect.fromLTWH(20, yPosition + 15, scheduleColumnWidth, rowHeight),
        format: PdfStringFormat(alignment: PdfTextAlignment.center, textDirection: PdfTextDirection.rightToLeft),
      );
      
      yPosition += rowHeight;
      
      // بيانات الجدول
      for (String day in days) {
        final daySchedule = workingSchedule[day];
        String scheduleText = 'لا يوجد دوام';

        if (daySchedule != null) {
          final morning = daySchedule['morning'];
          final evening = daySchedule['evening'];
          List<String> periods = [];

          if (morning != null) {
            periods.add('صباح');
          }

          if (evening != null) {
            periods.add('مساء');
          }

          if (periods.isNotEmpty) {
            scheduleText = periods.join(' - ');
          }
        }

        // رسم صف الجدول - الأيام في اليمين
        graphics.drawRectangle(
          bounds: Rect.fromLTWH(380, yPosition, dayColumnWidth, rowHeight),
          pen: PdfPen(PdfColor(200, 200, 200)),
        );
        graphics.drawString(
          day,
          font,
          bounds: Rect.fromLTWH(380, yPosition + 15, dayColumnWidth, rowHeight),
          format: PdfStringFormat(alignment: PdfTextAlignment.center, textDirection: PdfTextDirection.rightToLeft),
        );
        
        graphics.drawRectangle(
          bounds: Rect.fromLTWH(20, yPosition, scheduleColumnWidth, rowHeight),
          pen: PdfPen(PdfColor(200, 200, 200)),
        );
        graphics.drawString(
          scheduleText,
          font,
          bounds: Rect.fromLTWH(20, yPosition + 15, scheduleColumnWidth, rowHeight),
          format: PdfStringFormat(alignment: PdfTextAlignment.center, textDirection: PdfTextDirection.rightToLeft),
        );
        
        yPosition += rowHeight;
      }
      
      // حفظ الملف
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'جدول_${doctorName.replaceAll(' ', '_')}_${specialization.replaceAll(' ', '_')}.pdf';
      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(await document.save());
      document.dispose();
      
      // إغلاق مؤشر التحميل
      if (mounted) {
        Navigator.of(context).pop();
      }
      
      // فتح الملف
      await OpenFilex.open(file.path);
      
      // عرض رسالة نجاح
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تصدير جدول $doctorName بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
      
    } catch (e) {
      // إغلاق مؤشر التحميل في حالة الخطأ
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ في تصدير PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
