import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _currentVersion = '';
  String _firebaseVersion = '';
  String? _updateUrl;
  bool _isLoading = true;
  bool _isUpdating = false;
  double _downloadProgress = 0.0;
  String _updateStatus = '';
  bool _forceSimulation = false; // خيار إجباري للمحاكاة (غير مستخدم الآن)

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  Future<void> _loadData() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      
      // قراءة بيانات التحديث من Firebase - collection appConfig, document version2
      final doc = await FirebaseFirestore.instance
          .collection('appConfig')
          .doc('version2')
          .get();

      final data = doc.data() ?? {};
      final firebaseVersion = (data['lastVersion'] as String?) ?? '';
      final updateUrl = data['updatrUrl'] as String?;

      // طباعة بيانات التصحيح
      print('Firebase Data: $data');
      print('Firebase Version: $firebaseVersion');
      print('Update URL: $updateUrl');

      setState(() {
        _currentVersion = packageInfo.version;
        _firebaseVersion = firebaseVersion;
        _updateUrl = updateUrl;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading version data: $e');
      setState(() {
        _isLoading = false;
      });
      
      // عرض رسالة خطأ للمستخدم
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحميل بيانات التحديث: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleCheckAndUpdate() async {
    try {
      if (_firebaseVersion.isEmpty || _updateUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('بيانات التحديث غير متاحة حالياً')),
        );
        return;
      }

      // مقارنة الإصدارات بصيغة x.y.z
      int _cmp(String a, String b) {
        final ap = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
        final bp = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
        while (ap.length < bp.length) ap.add(0);
        while (bp.length < ap.length) bp.add(0);
        for (int i = 0; i < ap.length; i++) {
          if (ap[i] < bp[i]) return -1;
          if (ap[i] > bp[i]) return 1;
        }
        return 0;
      }

      final comparison = _cmp(_currentVersion, _firebaseVersion);
      if (comparison < 0) {
        // يوجد تحديث - عرض تأكيد التحديث
        final shouldUpdate = await _showUpdateDialog();
        if (shouldUpdate) {
          await _performInAppUpdate();
        }
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('التطبيق محدث'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر فحص التحديث: $e')),
      );
    }
  }

  Future<bool> _showUpdateDialog() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('تحديث متاح'),
        content: Text(
          'يوجد إصدار جديد متاح: $_firebaseVersion\n'
          'الإصدار الحالي: $_currentVersion\n\n'
          'هل تريد تحديث التطبيق الآن؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('لاحقاً'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2FBDAF),
              foregroundColor: Colors.white,
            ),
            child: const Text('تحديث الآن'),
          ),
        ],
      ),
    ) ?? false;
  }

  Future<void> _performInAppUpdate() async {
    if (_updateUrl == null || _updateUrl!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('رابط التحديث غير متاح'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    _safeSetState(() {
      _isUpdating = true;
      _downloadProgress = 0.0;
      _updateStatus = 'جاري بدء التحديث...';
    });

    try {
      // التحديث الحقيقي دائماً
      print('Starting real update process...');
      await _performRealUpdate();
      
      // تحديث الإصدار في التطبيق
      if (!mounted) return;
      _safeSetState(() {
        _currentVersion = _firebaseVersion;
      });

      // عرض رسالة نجاح
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تحديث التطبيق بنجاح!\nالإصدار الجديد: $_firebaseVersion'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }

    } catch (e) {
      print('Error in in-app update: $e');
      
      String errorMessage = 'خطأ في التحديث';
      
      if (e.toString().contains('SocketException')) {
        errorMessage = 'خطأ في الاتصال بالإنترنت. تأكد من اتصالك بالشبكة.';
      } else if (e.toString().contains('HttpException')) {
        errorMessage = 'خطأ في الرابط. تأكد من صحة رابط التحديث.';
      } else if (e.toString().contains('Permission')) {
        errorMessage = 'مطلوب إذن الكتابة للتخزين.';
      } else if (e.toString().contains('simulation')) {
        errorMessage = 'خطأ في محاكاة التحديث.';
      } else if (e.toString().contains('production')) {
        errorMessage = 'خطأ في التحديث الحقيقي.';
      }
      
      _safeSetState(() {
        _updateStatus = 'فشل في التحديث: $errorMessage';
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      _safeSetState(() {
        _isUpdating = false;
      });
    }
  }

  // يتأكد من إذن تثبيت التطبيقات من خارج المتجر. يطلب الإذن أو يفتح الإعدادات عند الرفض
  Future<bool> _ensureInstallPermission() async {
    try {
      // بعض الأجهزة لا تدعم هذا الإذن برمجياً، سنحاول بأفضل المتاح
      var status = await Permission.requestInstallPackages.status;
      if (status.isGranted) return true;

      status = await Permission.requestInstallPackages.request();
      if (status.isGranted) return true;

      // إذا رفض المستخدم، نعرض حوار مع زر لفتح الإعدادات
      if (!mounted) return false;
      final openSettings = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('السماح بالتثبيت'),
          content: const Text(
            'لتثبيت التحديث، يجب السماح للتطبيق بتثبيت التطبيقات من خارج المتجر.\n'
            'افتح الإعدادات وقم بتفعيل الخيار ثم عد للتطبيق وأعد المحاولة.'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                await openAppSettings();
                if (Navigator.canPop(context)) {
                  Navigator.pop(context, true);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2FBDAF),
                foregroundColor: Colors.white,
              ),
              child: const Text('فتح الإعدادات'),
            ),
          ],
        ),
      ) ?? false;

      if (!openSettings) return false;

      // بعد العودة من الإعدادات، نفحص مجدداً
      final recheck = await Permission.requestInstallPackages.status;
      return recheck.isGranted;
    } catch (e) {
      // إذا فشلنا لأسباب تتعلق بالإصدار، نسمح بالمتابعة ومحاولة الفتح مباشرة
      print('ensureInstallPermission fallback: $e');
      return true;
    }
  }

  // دالة للتحقق من صحة رابط التحديث (للمساعدة في التشخيص)
  Future<bool> _isUpdateUrlValid() async {
    try {
      if (_updateUrl == null || _updateUrl!.isEmpty) {
        print('No update URL provided');
        return false;
      }
      
      String cleanUrl = _updateUrl!;
      if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
        cleanUrl = 'https://$cleanUrl';
      }
      
      if (!cleanUrl.toLowerCase().contains('.apk')) {
        print('URL does not contain APK file');
        return false;
      }
      
      final response = await http.head(Uri.parse(cleanUrl));
      print('URL validation response: ${response.statusCode}');
      
      return response.statusCode == 200;
    } catch (e) {
      print('URL validation failed: $e');
      return false;
    }
  }

  Future<void> _performRealUpdate() async {
    try {
      print('Starting real update process...');
      
      // مرحلة 1: التحضير (لا حاجة لإذن تخزين عند استخدام مجلد التطبيق المؤقت)
      _safeSetState(() {
        _updateStatus = 'جاري التحضير...';
        _downloadProgress = 0.1;
      });

      // مرحلة 2: تحميل التحديث
      _safeSetState(() {
        _updateStatus = 'جاري تحميل التحديث...';
        _downloadProgress = 0.3;
      });

      String cleanUrl = _updateUrl!;
      if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
        cleanUrl = 'https://$cleanUrl';
      }
      
      print('Downloading from: $cleanUrl');

      http.Response response;
      try {
        response = await http.get(
          Uri.parse(cleanUrl),
          headers: {'User-Agent': 'HospitalAdminApp/1.0'},
        );
        if (!mounted) return;

        print('Download response: ${response.statusCode}');
        
        if (response.statusCode != 200) {
          throw Exception('فشل في تحميل التحديث: ${response.statusCode}');
        }
        
        if (response.bodyBytes.isEmpty) {
          throw Exception('الملف المحمل فارغ');
        }
        
        print('Download completed, file size: ${response.bodyBytes.length} bytes');
      } catch (e) {
        print('Download error: $e');
        throw Exception('خطأ في التحميل: $e');
      }

      // مرحلة 3: حفظ الملف في مجلد مؤقت خاص بالتطبيق (لا يتطلب إذن تخزين)
      _safeSetState(() {
        _updateStatus = 'جاري حفظ الملف...';
        _downloadProgress = 0.7;
      });

      try {
        final tempDir = await getTemporaryDirectory();
        print('Temp directory: ${tempDir.path}');

        final file = File('${tempDir.path}/hospital_admin_update.apk');
        await file.writeAsBytes(response.bodyBytes, flush: true);
        
        print('File saved successfully');
      } catch (e) {
        print('File save error: $e');
        throw Exception('خطأ في حفظ الملف: $e');
      }

      // مرحلة 4: فتح ملف التثبيت عبر النظام
      _safeSetState(() {
        _updateStatus = 'جاري فتح ملف التثبيت...';
        _downloadProgress = 0.9;
      });

      try {
        // طلب إذن تثبيت الحزم من المستخدم بشكل صريح وفتح الإعدادات إن لزم
        final granted = await _ensureInstallPermission();
        if (!granted) {
          throw Exception('لم يتم منح إذن التثبيت');
        }

        // استخدام نفس المجلد المؤقت الذي حفظنا به الملف
        final tempDir = await getTemporaryDirectory();
        final filePath = '${tempDir.path}/hospital_admin_update.apk';
        final apkFile = File(filePath);
        if (!await apkFile.exists()) {
          // إذا لم يكن الملف موجوداً هنا (مثلاً إذا تم حفظه سابقاً في موقع آخر)،
          // انسخ من الموقع السابق إن وُجد، وإلا أعد الحفظ من الذاكرة المؤقتة أعلاه
          // ملاحظة: في هذا التدفق نحن حفظنا سابقاً في external، لذا نعيد النسخ إن لزم
          try {
            // لم نعد نستخدم external، لذا لا حاجة لنسخ من هناك
          } catch (_) {}
        }

        // افتح ملف الـ APK عبر النظام
        final result = await OpenFilex.open(
          filePath,
          type: 'application/vnd.android.package-archive',
        );
        print('OpenFilex result: ${result.type}');

        _safeSetState(() {
          _updateStatus = 'تم فتح المثبت. يرجى المتابعة للتثبيت';
          _downloadProgress = 1.0;
        });
      } catch (e) {
        print('Installer open error: $e');
        throw Exception('تعذر فتح ملف التثبيت: $e');
      }

          } catch (e) {
        print('Production update error: $e');
        
        // رسائل خطأ أكثر وضوحاً
        String errorMessage = 'خطأ في التحديث';
        
        if (e.toString().contains('Permission')) {
          errorMessage = 'مطلوب إذن الكتابة للتخزين. يرجى تفعيل الإذن في إعدادات التطبيق.';
        } else if (e.toString().contains('SocketException')) {
          errorMessage = 'خطأ في الاتصال بالإنترنت. تأكد من اتصالك بالشبكة.';
        } else if (e.toString().contains('HttpException')) {
          errorMessage = 'خطأ في رابط التحديث. تأكد من صحة الرابط في Firebase.';
        } else if (e.toString().contains('فشل في تحميل')) {
          errorMessage = 'فشل في تحميل ملف التحديث. تأكد من أن الرابط صحيح.';
        } else if (e.toString().contains('الملف المحمل فارغ')) {
          errorMessage = 'ملف التحديث فارغ. تأكد من صحة الرابط.';
        } else if (e.toString().contains('لا يمكن الوصول')) {
          errorMessage = 'لا يمكن الوصول إلى مجلد التخزين. تأكد من الأذونات.';
        } else if (e.toString().contains('خطأ في حفظ')) {
          errorMessage = 'خطأ في حفظ ملف التحديث. تأكد من وجود مساحة كافية.';
        }
        
        throw Exception(errorMessage);
      }
  }

  Future<void> _simulateUpdateProcess() async {
    try {
      // مرحلة 1: بدء التحديث
      setState(() {
        _updateStatus = 'جاري بدء التحديث...';
        _downloadProgress = 0.1;
      });
      await Future.delayed(const Duration(milliseconds: 500));

      // مرحلة 2: فحص الأذونات
      setState(() {
        _updateStatus = 'جاري فحص الأذونات...';
        _downloadProgress = 0.2;
      });
      await Future.delayed(const Duration(milliseconds: 800));

      // مرحلة 3: تحميل التحديث
      setState(() {
        _updateStatus = 'جاري تحميل التحديث...';
        _downloadProgress = 0.3;
      });
      await Future.delayed(const Duration(milliseconds: 1000));

      // مرحلة 4: تحميل متقدم
      setState(() {
        _updateStatus = 'جاري تحميل التحديث...';
        _downloadProgress = 0.5;
      });
      await Future.delayed(const Duration(milliseconds: 1200));

      // مرحلة 5: تحميل شبه مكتمل
      setState(() {
        _updateStatus = 'جاري تحميل التحديث...';
        _downloadProgress = 0.7;
      });
      await Future.delayed(const Duration(milliseconds: 1000));

      // مرحلة 6: حفظ الملف
      setState(() {
        _updateStatus = 'جاري حفظ الملف...';
        _downloadProgress = 0.8;
      });
      await Future.delayed(const Duration(milliseconds: 800));

      // مرحلة 7: تثبيت التحديث
      setState(() {
        _updateStatus = 'جاري تثبيت التحديث...';
        _downloadProgress = 0.9;
      });
      await Future.delayed(const Duration(milliseconds: 1000));

      // مرحلة 8: اكتمال التحديث
      setState(() {
        _updateStatus = 'تم التحديث بنجاح!';
        _downloadProgress = 1.0;
      });
      await Future.delayed(const Duration(milliseconds: 500));

    } catch (e) {
      throw Exception('simulation error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasFirebaseVersion = _firebaseVersion.isNotEmpty;
    final hasUpdate = hasFirebaseVersion && _firebaseVersion != _currentVersion;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'حول التطبيق',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          backgroundColor: const Color(0xFF2FBDAF),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: Logo placeholder + App name + brief
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.12),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            )
                          ],
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.asset(
                                  'assets/images/icon.png',
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Text('تطبيق إدارة المراكز الطبية', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                  SizedBox(height: 6),
                                  Text(
                                    'تطبيق متخصص لإدارة المراكز الطبية يتيح إدارة الأطباء والحجوزات والمستخدمين وشركات التأمين بكل سهولة وكفاءة.',
                                    style: TextStyle(color: Colors.black87, height: 1.4),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Features (expandable)
                      ExpandableSection(
                        title: 'المميزات الرئيسية',
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Bullet(text: 'إدارة المراكز الطبية والمستشفيات'),
                            _Bullet(text: 'إدارة الأطباء والتخصصات'),
                            _Bullet(text: 'إدارة الحجوزات والمواعيد'),
                            _Bullet(text: 'إدارة المستخدمين والمرضى'),
                            _Bullet(text: 'إدارة شركات التأمين'),
                            _Bullet(text: 'لوحات تحكم شاملة وإحصائيات'),
                            _Bullet(text: 'نظام إشعارات متقدم'),
                            _Bullet(text: 'واجهة إدارية سهلة الاستخدام'),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Version (expandable)
                      ExpandableSection(
                        title: 'معلومات الإصدار',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                          children: [
                            Text('رقم الإصدار: $_currentVersion', style: TextStyle(color: Colors.grey[700])),
                                if (hasUpdate) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.orange[100],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'تحديث متاح',
                                      style: TextStyle(
                                        color: Colors.orange[700],
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (hasFirebaseVersion && hasUpdate) ...[
                              const SizedBox(height: 8),
                              Text(
                                'الإصدار الجديد المتاح: $_firebaseVersion',
                                style: TextStyle(
                                  color: Colors.green[700],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            
                            // معلومات التحديث الحقيقي
                            if (!_isUpdating) ...[
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.blue[50],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.blue[200]!),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.info_outline,
                                          color: Colors.blue[700],
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'سيتم تحميل وتثبيت التحديث الحقيقي',
                                            style: TextStyle(
                                              color: Colors.blue[700],
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            onPressed: () async {
                                              bool isValid = await _isUpdateUrlValid();
                                              if (mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      isValid 
                                                          ? 'رابط التحديث صحيح' 
                                                          : 'رابط التحديث غير صحيح',
                                                    ),
                                                    backgroundColor: isValid ? Colors.green : Colors.red,
                                                  ),
                                                );
                                              }
                                            },
                                            icon: const Icon(Icons.link, size: 16),
                                            label: const Text('اختبار الرابط'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.blue[100],
                                              foregroundColor: Colors.blue[700],
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            
                            // شريط تقدم التحديث
                            if (_isUpdating) ...[
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _updateStatus,
                                    style: TextStyle(
                                      color: Colors.grey[700],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  LinearProgressIndicator(
                                    value: _downloadProgress,
                                    backgroundColor: Colors.grey[300],
                                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2FBDAF)),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${(_downloadProgress * 100).toInt()}%',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ] else ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: _handleCheckAndUpdate,
                                      icon: const Icon(Icons.system_update),
                                      label: Text(
                                        hasUpdate
                                            ? 'تحديث التطبيق'
                                            : 'فحص الإصدار والتحديث'
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: hasUpdate
                                            ? Colors.green
                                            : const Color(0xFF2FBDAF),
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Developer (expandable)
                      const ExpandableSection(
                        title: 'عن المطور',
                        child: Text('تم تطويره من قبل نجوم الانتاج', style: TextStyle(color: Colors.black87)),
                      ),

                      const SizedBox(height: 16),

                      // Support (expandable)
                      ExpandableSection(
                        title: 'الدعم الفني ووسائل التواصل',
                        child: Text('قريباً', style: TextStyle(color: Colors.grey[600])),
                      ),

                      const SizedBox(height: 16),

                      // Policies (each expandable)
                      ExpandableSection(
                        title: 'سياسة الخصوصية',
                        child: Text(
                          'نحترم خصوصيتك. يتم استخدام بياناتك فقط لأغراض إدارة المراكز الطبية وتحسين الخدمة. لا نشارك بياناتك مع أطراف ثالثة إلا وفق القوانين أو بموافقتك.',
                          style: TextStyle(color: Colors.grey[700], height: 1.5),
                        ),
                      ),

                      const SizedBox(height: 16),

                      ExpandableSection(
                        title: 'الشروط والأحكام',
                        child: Text(
                          'باستخدامك للتطبيق فإنك توافق على الشروط والأحكام الخاصة باستخدام الخدمة، وتشمل الالتزام بسياسات إدارة المراكز الطبية وعدم إساءة الاستخدام والمحافظة على سرية بيانات دخولك.',
                          style: TextStyle(color: Colors.grey[700], height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 16)),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}

class ExpandableSection extends StatefulWidget {
  final String title;
  final Widget child;
  const ExpandableSection({super.key, required this.title, required this.child});

  @override
  State<ExpandableSection> createState() => _ExpandableSectionState();
}

class _ExpandableSectionState extends State<ExpandableSection> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold)),
            trailing: Transform.rotate(
              angle: _open ? 1.5708 : 0,
              child: const Icon(Icons.arrow_right, color: Colors.black54),
            ),
            onTap: () => setState(() => _open = !_open),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(right: 8, left: 8, bottom: 12),
              child: Align(alignment: Alignment.centerRight, child: widget.child),
            ),
        ],
      ),
    );
  }
}
