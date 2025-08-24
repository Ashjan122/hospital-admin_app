import 'package:flutter/material.dart';
import 'package:hospital_admin_app/services/app_update_service.dart';
import 'package:hospital_admin_app/widgets/app_update_dialog.dart';

class AppUpdateWrapper extends StatefulWidget {
  final Widget child;

  const AppUpdateWrapper({
    super.key,
    required this.child,
  });

  @override
  State<AppUpdateWrapper> createState() => _AppUpdateWrapperState();
}

class _AppUpdateWrapperState extends State<AppUpdateWrapper> {
  bool _hasCheckedUpdate = false;
  bool _isChecking = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    // تأخير قليل للتأكد من تحميل التطبيق
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdate();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // التحقق من التحديث عند تغيير الصفحة أيضاً
    if (!_hasCheckedUpdate) {
      _checkForUpdate();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _checkForUpdate() async {
    // تم إلغاء عرض Dialog التحديث على مستوى التطبيق.
    // التحقق والتحديث يتم حصراً من صفحة "حول التطبيق".
    return;
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
