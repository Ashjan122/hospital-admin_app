import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class DoctorScheduleScreen extends StatefulWidget {
  final String doctorId;
  final String centerId;
  final String? centerName;
  final String? doctorName;

  const DoctorScheduleScreen({
    super.key,
    required this.doctorId,
    required this.centerId,
    this.centerName,
    this.doctorName,
  });

  @override
  State<DoctorScheduleScreen> createState() => _DoctorScheduleScreenState();
}

class _DoctorScheduleScreenState extends State<DoctorScheduleScreen> {
  Map<String, dynamic>? _doctorData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDoctorData();
  }

  Future<void> _loadDoctorData() async {
    try {
      // البحث عن الطبيب في جميع التخصصات
      final specializationsSnapshot = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .get()
          .timeout(const Duration(seconds: 8));

      for (var specDoc in specializationsSnapshot.docs) {
        final doctorDoc = await FirebaseFirestore.instance
            .collection('medicalFacilities')
            .doc(widget.centerId)
            .collection('specializations')
            .doc(specDoc.id)
            .collection('doctors')
            .doc(widget.doctorId)
            .get()
            .timeout(const Duration(seconds: 8));

        if (doctorDoc.exists) {
          final doctorData = doctorDoc.data()!;
          
          // جلب معلومات الطبيب من قاعدة البيانات المركزية
          try {
            final centralDoctorDoc = await FirebaseFirestore.instance
                .collection('allDoctors')
                .doc(widget.doctorId)
                .get();
            
            if (centralDoctorDoc.exists) {
              final centralDoctorData = centralDoctorDoc.data()!;
              doctorData['name'] = centralDoctorData['name'] ?? 'طبيب غير معروف';
              doctorData['phoneNumber'] = centralDoctorData['phoneNumber'] ?? '';
              doctorData['photoUrl'] = centralDoctorData['photoUrl'] ?? 
                  'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQupVHd_oeqnkds0k3EjT1SX4ctwwblwYP2Uw&s';
            }
          } catch (e) {
            // إذا فشل في جلب البيانات من المركزية، استخدم المعرف
            doctorData['name'] = widget.doctorId;
          }
          
          // إضافة اسم التخصص للبيانات
          final specializationData = specDoc.data();
          doctorData['specialization'] = specializationData['specName'] ?? specDoc.id;
          doctorData['specializationId'] = specDoc.id;
          
          setState(() {
            _doctorData = doctorData;
            _isLoading = false;
          });
          return;
        }
      }
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading doctor data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showEditScheduleDialog(String day) {
    if (_doctorData == null) return;
    
    final workingSchedule = _doctorData!['workingSchedule'] as Map<String, dynamic>? ?? {};
    final daySchedule = workingSchedule[day] ?? {};
    final doctorName = _doctorData!['name'] ?? 'طبيب غير معروف';
    
    // تحديد الأوقات الافتراضية
    final morningStartController = TextEditingController(
      text: daySchedule['morning']?['start'] ?? daySchedule['morning']?['startTime'] ?? '09:00'
    );
    final morningEndController = TextEditingController(
      text: daySchedule['morning']?['end'] ?? daySchedule['morning']?['endTime'] ?? '12:00'
    );
    final eveningStartController = TextEditingController(
      text: daySchedule['evening']?['start'] ?? daySchedule['evening']?['startTime'] ?? '18:00'
    );
    final eveningEndController = TextEditingController(
      text: daySchedule['evening']?['end'] ?? daySchedule['evening']?['endTime'] ?? '23:00'
    );
    
    // تفعيل الفترات تلقائياً إذا لم تكن موجودة
    bool hasMorning = daySchedule['morning'] != null;
    bool hasEvening = daySchedule['evening'] != null;
    
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
              onPressed: () async {
                await _updateDoctorSchedule(
                  day,
                  hasMorning,
                  hasEvening,
                  morningStartController.text,
                  morningEndController.text,
                  eveningStartController.text,
                  eveningEndController.text,
                );
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2FBDAF),
                foregroundColor: Colors.white,
              ),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateDoctorSchedule(
    String day,
    bool hasMorning,
    bool hasEvening,
    String morningStart,
    String morningEnd,
    String eveningStart,
    String eveningEnd,
  ) async {
    try {
      if (_doctorData == null) return;
      
      final workingSchedule = _doctorData!['workingSchedule'] as Map<String, dynamic>? ?? {};
      
      // Update the day schedule
      Map<String, dynamic> daySchedule = {};
      
      if (hasMorning && morningStart.isNotEmpty && morningEnd.isNotEmpty) {
        daySchedule['morning'] = {
          'start': morningStart,
          'end': morningEnd,
        };
      }
      
      if (hasEvening && eveningStart.isNotEmpty && eveningEnd.isNotEmpty) {
        daySchedule['evening'] = {
          'start': eveningStart,
          'end': eveningEnd,
        };
      }
      
      // Update the working schedule
      workingSchedule[day] = daySchedule.isEmpty ? null : daySchedule;
      
      // Remove empty days
      workingSchedule.removeWhere((key, value) => value == null);
      
      // Update in Firestore
      await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .doc(_doctorData!['specializationId'])
          .collection('doctors')
          .doc(widget.doctorId)
          .update({
        'workingSchedule': workingSchedule,
      });

      // Update local data
      setState(() {
        _doctorData!['workingSchedule'] = workingSchedule;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تحديث جدول العمل بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ في تحديث الجدول: $e'),
          backgroundColor: Colors.red,
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
          title: Text(
            'جدول ${widget.doctorName ?? 'الطبيب'}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF2FBDAF),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF2FBDAF),
                ),
              )
            : _doctorData == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        const Text(
                          'لم يتم العثور على بيانات الطبيب',
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : _buildScheduleView(),
      ),
    );
  }

  Widget _buildScheduleView() {
    final workingSchedule = _doctorData!['workingSchedule'] as Map<String, dynamic>? ?? {};
    final doctorName = _doctorData!['name'] ?? 'طبيب غير معروف';
    final specialization = _doctorData!['specialization'] ?? 'تخصص غير محدد';
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Doctor info card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    doctorName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    specialization,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // Schedule
          if (workingSchedule.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    const Icon(Icons.schedule_outlined, size: 48, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text(
                      'لا يوجد جدول محدد للطبيب',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'اضغط على "إضافة جدول" لإنشاء جدول جديد',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => _showEditScheduleDialog('الأحد'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2FBDAF),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('إضافة جدول'),
                    ),
                  ],
                ),
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'جدول العمل الأسبوعي',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _showEditScheduleDialog('الأحد'),
                      icon: const Icon(Icons.add),
                      label: const Text('إضافة يوم'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2FBDAF),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ...workingSchedule.keys.map((day) {
                  final schedule = workingSchedule[day] as Map<String, dynamic>?;
                  if (schedule == null) return const SizedBox.shrink();
                  
                  final morning = schedule['morning'] as Map<String, dynamic>?;
                  final evening = schedule['evening'] as Map<String, dynamic>?;
                  
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(
                        day,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2FBDAF),
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (morning != null && morning.isNotEmpty) ...[
                            Row(
                              children: [
                                const Icon(Icons.wb_sunny, size: 14, color: Colors.orange),
                                const SizedBox(width: 4),
                                const Text('صباحاً: '),
                                Text('${morning['start'] ?? morning['startTime'] ?? ''} - ${morning['end'] ?? morning['endTime'] ?? ''}'),
                              ],
                            ),
                            const SizedBox(height: 2),
                          ],
                          if (evening != null && evening.isNotEmpty) ...[
                            Row(
                              children: [
                                const Icon(Icons.nightlight, size: 14, color: Colors.indigo),
                                const SizedBox(width: 4),
                                const Text('مساءً: '),
                                Text('${evening['start'] ?? evening['startTime'] ?? ''} - ${evening['end'] ?? evening['endTime'] ?? ''}'),
                              ],
                            ),
                          ],
                          if ((morning == null || morning.isEmpty) && 
                              (evening == null || evening.isEmpty)) ...[
                            const Text(
                              'لا يوجد مواعيد في هذا اليوم',
                              style: TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                          ],
                        ],
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit, size: 16),
                        onPressed: () => _showEditScheduleDialog(day),
                      ),
                    ),
                  );
                }).toList(),
              ],
            ),
        ],
      ),
    );
  }
}
