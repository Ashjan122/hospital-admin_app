import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hospital_admin_app/screens/patient_visit_tests_screen.dart';
import 'package:intl/intl.dart' as intl;



class TodaySamplesScreen extends StatefulWidget {
  
  const TodaySamplesScreen({super.key});

  @override
  State<TodaySamplesScreen> createState() => _TodaySamplesScreenState();
}

class _TodaySamplesScreenState extends State<TodaySamplesScreen> {
  List<dynamic> allSamples = [];
  List<dynamic> filteredSamples = [];
  bool isLoading = true;
  String errorMessage = '';
  bool _isGrid = false;

  final TextEditingController _searchController = TextEditingController();
  final Color _color1 = const Color.fromARGB(255, 215, 213, 219);
  final Color _color2 = const  Color(0xFF2FBDAF);

  int? currentShiftId;
  int? latestShiftId;

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetchSamples();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String _extractErrorMessage(dynamic e) {
    if (e is DioException) {
      if (e.response != null && e.response!.data != null) {
        final data = e.response!.data;
        
        // محاولة استخراج الرسالة من حقول مختلفة
        if (data is Map) {
          // محاولة الحصول على message
          if (data['message'] != null) {
            return data['message'].toString();
          }
          // محاولة الحصول على error
          if (data['error'] != null) {
            if (data['error'] is String) {
              return data['error'];
            } else if (data['error'] is Map && data['error']['message'] != null) {
              return data['error']['message'].toString();
            }
          }
          // محاولة الحصول على errors (قائمة)
          if (data['errors'] != null) {
            if (data['errors'] is Map) {
              final errors = data['errors'] as Map;
              if (errors.isNotEmpty) {
                final firstError = errors.values.first;
                if (firstError is List && firstError.isNotEmpty) {
                  return firstError.first.toString();
                } else if (firstError is String) {
                  return firstError;
                }
              }
            }
          }
        }
        
        // إذا لم نجد رسالة واضحة، نعيد status code
        return 'خطأ ${e.response!.statusCode}: ${e.response!.statusMessage ?? 'حدث خطأ'}';
      }
      
      // إذا لم يكن هناك response، نعيد رسالة الاتصال
      return 'خطأ في الاتصال بالسيرفر: ${e.message ?? 'يرجى التحقق من الاتصال بالإنترنت'}';
    }
    
    return 'حدث خطأ غير متوقع: $e';
  }

  Future<void> _fetchSamples({int? shiftId, bool onlyToday = true}) async {
    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    try {
      final dio =
          Dio()
            ..options.headers['Accept'] = 'application/json';

      final url = 
        'https://alroomylab.a.pinggy.link/jawda-medical/public/api/lab/pending-queue';
      

      final response = await dio.get(
        url,
        queryParameters: {
          'search': '',
          'page': 1,
          'per_page': 50,
          'shift_id': shiftId,
          'result_status_filter': 'pending',
        },
      );
      print('================= 📦 RESPONSE FROM SERVER =================');
      print(response.data);
      print('===========================================================');

      List<dynamic> data = [];
      if (response.statusCode == 200 && response.data != null) {
        if (response.data is List) {
          data = response.data;
        } else if (response.data is Map && response.data.containsKey('data')) {
          data = response.data['data'];
        }

        currentShiftId =
            data.isNotEmpty
                ? (data.first['shift_id'] ?? shiftId)
                : (shiftId ?? currentShiftId);

        if (onlyToday && data.isNotEmpty) latestShiftId = currentShiftId;
        print(' رقم الوردية: $currentShiftId');

        setState(() {
          allSamples = data;
          filteredSamples = data;
          isLoading = false;
          errorMessage = data.isEmpty ? 'لا توجد عينات' : '';
        });
      } else {
        // محاولة استخراج رسالة الخطأ من response
        String errorMsg = 'فشل تحميل البيانات (${response.statusCode})';
        if (response.data != null && response.data is Map) {
          final responseData = response.data as Map;
          if (responseData['message'] != null) {
            errorMsg = responseData['message'].toString();
          } else if (responseData['error'] != null) {
            if (responseData['error'] is String) {
              errorMsg = responseData['error'];
            } else if (responseData['error'] is Map && responseData['error']['message'] != null) {
              errorMsg = responseData['error']['message'].toString();
            }
          } else if (responseData['errors'] != null && responseData['errors'] is Map) {
            final errors = responseData['errors'] as Map;
            if (errors.isNotEmpty) {
              final firstError = errors.values.first;
              if (firstError is List && firstError.isNotEmpty) {
                errorMsg = firstError.first.toString();
              } else if (firstError is String) {
                errorMsg = firstError;
              }
            }
          }
        }
        
        setState(() {
          errorMessage = errorMsg;
          isLoading = false;
        });
      }
    } on DioException catch (e) {
      setState(() {
        errorMessage = _extractErrorMessage(e);
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'حدث خطأ غير متوقع: $e';
        isLoading = false;
      });
    }
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      final query = _searchController.text.trim();
      if (query.isEmpty) {
        setState(() {
          filteredSamples = allSamples;
          errorMessage = '';
        });
      } else {
        _searchPatients(query);
      }
    });
  }

  Future<void> _searchPatients(String query) async {
    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    try {
      final dio =
          Dio()
            ..options.headers['Accept'] = 'application/json';

      final url =
        'https://alroomylab.a.pinggy.link/jawda-medical/public/api/doctor-visits/search-by-patient';
      

      final response = await dio.get(
        url,
        queryParameters: {'patient_name_search': query, 'limit': 15},
      );

      List<dynamic> data = [];
      if (response.statusCode == 200 && response.data != null) {
        if (response.data is List) {
          data = response.data;
        } else if (response.data is Map && response.data.containsKey('data')) {
          data = response.data['data'];
        }

        setState(() {
          filteredSamples = data;
          isLoading = false;
          errorMessage = data.isEmpty ? 'لا توجد نتائج مطابقة' : '';
        });
      } else {
        // محاولة استخراج رسالة الخطأ من response
        String errorMsg = 'فشل تحميل نتائج البحث (${response.statusCode})';
        if (response.data != null && response.data is Map) {
          final responseData = response.data as Map;
          if (responseData['message'] != null) {
            errorMsg = responseData['message'].toString();
          } else if (responseData['error'] != null) {
            if (responseData['error'] is String) {
              errorMsg = responseData['error'];
            } else if (responseData['error'] is Map && responseData['error']['message'] != null) {
              errorMsg = responseData['error']['message'].toString();
            }
          } else if (responseData['errors'] != null && responseData['errors'] is Map) {
            final errors = responseData['errors'] as Map;
            if (errors.isNotEmpty) {
              final firstError = errors.values.first;
              if (firstError is List && firstError.isNotEmpty) {
                errorMsg = firstError.first.toString();
              } else if (firstError is String) {
                errorMsg = firstError;
              }
            }
          }
        }
        
        setState(() {
          errorMessage = errorMsg;
          isLoading = false;
        });
      }
    } on DioException catch (e) {
      setState(() {
        errorMessage = _extractErrorMessage(e);
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'حدث خطأ غير متوقع: $e';
        isLoading = false;
      });
    }
  }

  void _previousShift() {
    if (currentShiftId != null)
      _fetchSamples(shiftId: currentShiftId! - 1, onlyToday: false);
  }

  void _nextShift() {
    if (currentShiftId != null)
      _fetchSamples(shiftId: currentShiftId! + 1, onlyToday: false);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'عينات اليوم',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          backgroundColor: const  Color(0xFF2FBDAF),
        
          actions: [
            IconButton(
              icon: Icon(_isGrid ? Icons.view_list : Icons.grid_view),
              color: Colors.white,
              tooltip: _isGrid ? 'عرض قائمة' : 'عرض شبكة',
              onPressed: () {
                setState(() {
                  _isGrid = !_isGrid;
                });
              },
            ),
            
            IconButton(
              icon: const Icon(Icons.arrow_back_ios),
              color:
                  (currentShiftId != null &&
                          latestShiftId != null &&
                          currentShiftId != latestShiftId)
                      ? Colors.white
                      : Colors.grey,
              onPressed:
                  (currentShiftId != null &&
                          latestShiftId != null &&
                          currentShiftId != latestShiftId)
                      ? _nextShift
                      : null,
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward_ios),
              color: Colors.white,
              onPressed: _previousShift,
            ),
          ],
        ),
        body:  SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'البحث باسم المريض...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh:
                        () => _fetchSamples(
                          shiftId: currentShiftId,
                          onlyToday: currentShiftId == null,
                        ),
                    color: const Color(0xFF0A7179),
                    child:
                        isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : errorMessage.isNotEmpty
                            ? Center(child: Text(errorMessage))
                            : filteredSamples.isEmpty
                            ? const Center(child: Text('لا توجد بيانات'))
                            : _isGrid
                            ? _buildGridView(context)
                            : _buildListView(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      
    );
  }

  Widget _buildListView(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: filteredSamples.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final sample = filteredSamples[index];
        final visitId = sample['visit_id'] ?? 0;
        final patientName = sample['patient_name'] ?? 'بدون اسم';

        // جلب معرف المريض من السطر
        final dynamic rawPid = sample['pid'] ?? sample['patient_id'];
        final int? patientId =
            rawPid is int ? rawPid : (rawPid is String ? int.tryParse(rawPid) : null);

        return SampleListTile(
          visitId: visitId,
          sample: {
            'patient_name': patientName,
            'test_count': sample['test_count'] ?? 0,
            'is_printed': sample['is_printed'] ?? false,
            'pending_result_count': sample['pending_result_count'] ?? 0,
            'total_result_count': sample['total_result_count'] ?? 0,
            'patient_id': patientId,
            'lab_to_lab_object_id': sample['lab_to_lab_object_id'],
            'company': sample['company'],
            'lab_number': sample['lab_number'],
            'auth_date': sample['auth_date'],
          },
          onTap: () {
           /* if (visitId != 0) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PatientVisitTestsScreen(
                    patientId: visitId,
                    patientPhone: patientPhone,
                  ),
                ),
              );
            }*/
          },
        );
      },
    );
  }

  Widget _buildGridView(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width > 600 ? 5 : 4; // أربعة أو خمسة حسب الحجم

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: filteredSamples.length,
      itemBuilder: (context, index) {
        final sample = filteredSamples[index];
        final visitId = sample['visit_id'] ?? 0;

        return SampleGridTile(
          visitId: visitId,
          sample: {
            'test_count': sample['test_count'] ?? 0,
            'is_printed': sample['is_printed'] ?? false,
            'pending_result_count': sample['pending_result_count'] ?? 0,
            'lab_to_lab_object_id': sample['lab_to_lab_object_id'],
            'company': sample['company'],
            'lab_number': sample['lab_number'],
            'auth_date': sample['auth_date'],
          },
          onTap: () {
            if (visitId != 0) {
              var patientPhone;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PatientVisitTestsScreen(
                    patientId: visitId,
                    patientPhone: patientPhone,
                  ),
                ),
              );
            }
          },
        );
      },
    );
  }
}

class SampleListTile extends StatefulWidget {
  final int visitId;
  final Map<String, dynamic> sample;
  final VoidCallback onTap;

  const SampleListTile({
    super.key,
    required this.visitId,
    required this.sample,
    required this.onTap,
  });

  @override
  State<SampleListTile> createState() => _SampleListTileState();
}

class _SampleListTileState extends State<SampleListTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  final Color appColor = const Color(0xFF0A7179);
  bool isLoadingDetails = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _animation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    if (widget.sample['pending_result_count'] == 1) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _kvTile(String title, String value) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(
          title,
          textAlign: TextAlign.right,
          style: const TextStyle(color: Colors.black54),
        ),
        trailing: Text(
          value,
          textAlign: TextAlign.left,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        visualDensity: const VisualDensity(vertical: -3),
      ),
    );
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.trim().isEmpty) return '-';
    try {
      final parsed = DateTime.parse(iso);
      final local = parsed.toLocal();
      return intl.DateFormat('d-M-yyyy hh:mm a').format(local).toLowerCase();
    } catch (_) {
      return iso;
    }
  }

  String _formatAge(dynamic value) {
    final str = (value ?? '').toString().trim();
    if (str.isEmpty || str == '-' || str.toLowerCase() == 'n/a') return '0';
    return str;
  }

  Future<void> _showPatientDetails(int patientId) async {
    final dio =
        Dio()
          ..options.headers['Accept'] = 'application/json';

    try {
      final url = 
        'https://alroomylab.a.pinggy.link/jawda-medical/public/api/patients/$patientId';
      
      final response = await dio.get(url);

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        final patient =
            (data is Map && data.containsKey('data')) ? data['data'] : data;

        showDialog(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text(
                  'معلومات المريض',
                  textDirection: TextDirection.rtl,
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _kvTile('الاسم', (patient['name'] ?? 'N/A').toString()),
                      _kvTile('الهاتف', (patient['phone'] ?? 'N/A').toString()),
                      _kvTile('العمر', _formatAge(patient['full_age'])),
                      _kvTile(
                        'سجل بواسطة',
                        (patient['user']?['name'] ?? 'N/A').toString(),
                      ),
                      _kvTile(
                        'الطبيب',
                        (patient['primary_doctor']?['name'] ?? 'N/A')
                            .toString(),
                      ),
                      _kvTile(
                        'التاريخ',
                        _formatDate((patient['created_at'] ?? '').toString()),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('إغلاق'),
                  ),
                ],
              ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشل تحميل بيانات المريض')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('حدث خطأ: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPrinted = widget.sample['is_printed'] == true;
    final int totalCount = widget.sample['total_result_count'] ?? 0;
    final int pendingCount = widget.sample['pending_result_count'] ?? 0;
    final int? testCount = widget.sample['test_count'];
    final bool hasTests = testCount != null && testCount > 0;

    double progress = 0;
    if (totalCount > 0) {
      progress = (totalCount - pendingCount) / totalCount;
      progress = progress.clamp(0.0, 1.0);
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Row(
                children: [
                  // رقم الزيارة مع أيقونات
                  AnimatedBuilder(
                    animation: _animation,
                    builder: (context, child) {
                      final hasLabToLabObjectId =
                          widget.sample['lab_to_lab_object_id'] != null;
                      final hasCompany = widget.sample['company'] != null;
                      final hasAuthDate = widget.sample['auth_date'] != null;

                      return Transform.scale(
                        scale:
                            widget.sample['pending_result_count'] == 1
                                ? _animation.value
                                : 1.0,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // مستطيل الرقم
                            Container(
                              width: 50,
                              height: 50,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isPrinted ? Colors.blue : Colors.white,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: appColor, width: 2),
                              ),
                              child: Text(
                                (widget.sample['lab_number'] ?? '').toString(),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isPrinted ? Colors.white : appColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),

                            // أيقونة lab_to_lab بدون خط البوردر تحته
                            if (hasLabToLabObjectId)
                              Positioned(
                                top: -4,
                                left: -4,
                                child: Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),

                                  child: Icon(
                                    Icons.language,
                                    color: Colors.grey.shade600,
                                    size: 14,
                                  ),
                                ),
                              ),

                            
                            if (hasAuthDate || hasCompany)
                              Positioned(
                                bottom: -2,
                                right: -2,
                                child:Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),

                                  child:  Icon(
                                  hasAuthDate ? Icons.shield_outlined : Icons.favorite,
                                  color:
                                      hasAuthDate
                                          ? Colors.grey.shade600
                                          : Colors.red.shade600,
                                  size: 14,
                                ),
                              ),),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(width: 8),

                  // بيانات المريض + شريط التقدم
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.sample['patient_name'] ?? 'بدون اسم',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),

                        if (totalCount > 0)
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final maxWidth = constraints.maxWidth * 0.7;
                              return Container(
                                width: maxWidth,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade300,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Stack(
                                  children: [
                                    FractionallySizedBox(
                                      alignment: Alignment.centerRight,
                                      widthFactor: progress,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              appColor,
                                              appColor.withOpacity(0.7),
                                            ],
                                            begin: Alignment.centerRight,
                                            end: Alignment.centerLeft,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned.fill(
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: List.generate(5, (i) {
                                          return Container(
                                            width: 1,
                                            color: Colors.white.withOpacity(
                                              0.2,
                                            ),
                                          );
                                        }),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),

                  // أيقونة المعلومات
                  isLoadingDetails
                      ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.teal,
                        ),
                      )
                      :Column(
        mainAxisSize: MainAxisSize.min,
        children: [ IconButton(
                        icon: const Icon(
                          Icons.info_outline,
                          color: Colors.teal,
                        ),
                        tooltip: 'معلومات المريض',
                        onPressed: () async {
                          final dynamic pid = widget.sample['patient_id'];
                          final int? patientId =
                              pid is int
                                  ? pid
                                  : (pid is String ? int.tryParse(pid) : null);
                          if (patientId != null) {
                            setState(() => isLoadingDetails = true);
                            await _showPatientDetails(patientId);
                            setState(() => isLoadingDetails = false);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('لا يوجد معرف مريض صالح'),
                              ),
                            );
                          }
                        },
                      ),
                      
                      Text(
            widget.visitId.toString(),
            style: const TextStyle(
              fontSize: 10,
              color: Colors.grey,
            ),
          ),
                ],),],
              ),
            ),
          ),
        ),

        // عدد التحاليل أعلى البطاقة
        if (hasTests)
          Positioned(
            top: -3,
            left: -3,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 6.0,
                vertical: 2.0,
              ),
              decoration: BoxDecoration(
                color: appColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${widget.sample['test_count']}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class SampleGridTile extends StatefulWidget {
  final int visitId;
  final Map<String, dynamic> sample;
  final VoidCallback onTap;

  const SampleGridTile({
    super.key,
    required this.visitId,
    required this.sample,
    required this.onTap,
  });

  @override
  State<SampleGridTile> createState() => _SampleGridTileState();
}

class _SampleGridTileState extends State<SampleGridTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  final Color appColor = const Color(0xFF0A7179);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _animation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    if (widget.sample['pending_result_count'] == 1) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int testCount = widget.sample['test_count'] ?? 0;
    final bool isPrinted = widget.sample['is_printed'] == true;
    final bool hasLabToLabObjectId = widget.sample['lab_to_lab_object_id'] != null;
    final bool hasCompany = widget.sample['company'] != null;
    final bool hasAuthDate = widget.sample['auth_date'] != null;
    final String labNumber = (widget.sample['lab_number'] ?? '').toString();

    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return Transform.scale(
            scale: widget.sample['pending_result_count'] == 1 ? _animation.value : 1.0,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isPrinted ? Colors.blue : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: appColor, width: 2),
                    ),
                    child: Center(
                      child: Text(
                        labNumber,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isPrinted ? Colors.white : appColor,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                if (hasLabToLabObjectId)
                  Positioned(
                    top: 2,
                    left: 2,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.language,
                        color: Colors.grey.shade600,
                        size: 16,
                      ),
                    ),
                  ),
                if (hasAuthDate || hasCompany)
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        hasAuthDate ? Icons.shield_outlined : Icons.favorite,
                        color: hasAuthDate ? Colors.grey.shade600 : Colors.red.shade600,
                        size: 16,
                      ),
                    ),
                  ),
                if (testCount > 0)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: appColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$testCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
