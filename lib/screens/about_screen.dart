import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// إزالة http لعدم الحاجة بعد حذف اختبار الرابط
import 'package:hospital_admin_app/services/app_update_service.dart';

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
  // أزلنا حالة التحديث داخل التطبيق

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    super.dispose();
  }

  // أزلنا الدالة المساعدة غير المستخدمة

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
      if (_updateUrl == null || _updateUrl!.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('رابط التحديث غير متاح حالياً')),
        );
        return;
      }
      await AppUpdateService.openUpdateUrl(_updateUrl!);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر فتح رابط التحديث: $e')),
      );
    }
  }

  // أزلنا حوار التأكيد، الزر يفتح المتصفح مباشرة

  // تم استبدال التحديث الداخلي بفتح الرابط في المتصفح مباشرة من أماكن الاستدعاء.

  // لم نعد نستخدم مسار التثبيت داخل التطبيق، لذلك أزلنا أذونات التثبيت.

  // تم إزالة وظيفة اختبار الرابط بعد إلغاء زر الاختبار.

  // أزلنا منطق التحميل والتثبيت داخل التطبيق.

  // أزلنا محاكاة التحديث.

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
                            
                            // زر التحديث فقط يفتح المتصفح
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: _handleCheckAndUpdate,
                                      icon: const Icon(Icons.system_update),
                                    label: const Text('تحديث التطبيق'),
                                      style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF2FBDAF),
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            
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
