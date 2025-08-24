import 'package:flutter/material.dart';
import 'package:hospital_admin_app/services/app_update_service.dart';

class AppUpdateDialog extends StatelessWidget {
  final Map<String, dynamic> updateInfo;

  const AppUpdateDialog({
    super.key,
    required this.updateInfo,
  });

  @override
  Widget build(BuildContext context) {
    final isForceUpdate = updateInfo['isForceUpdate'] as bool? ?? false;
    final message = updateInfo['message'] as String? ?? 'يتوفر تحديث جديد للتطبيق';
    final currentVersion = updateInfo['currentVersion'] as String? ?? '';
    final latestVersion = updateInfo['latestVersion'] as String? ?? '';

    return PopScope(
      canPop: !isForceUpdate, // منع الإغلاق إذا كان التحديث إجباري
      child: AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(
              Icons.system_update,
              color: const Color(0xFF2FBDAF),
              size: 28,
            ),
            const SizedBox(width: 8),
            const Text(
              'تحديث التطبيق',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF2FBDAF),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: const Color(0xFF2FBDAF),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'الإصدار الحالي: $currentVersion',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        Text(
                          'الإصدار الجديد: $latestVersion',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (isForceUpdate) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber,
                      color: Colors.orange[600],
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'هذا التحديث إجباري لاستمرار استخدام التطبيق',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (!isForceUpdate)
            TextButton(
              onPressed: () {
                AppUpdateService.markUpdateAsSeen();
                Navigator.of(context).pop();
              },
              child: const Text(
                'لاحقاً',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ElevatedButton(
            onPressed: () async {
              final url = updateInfo['updateUrl'] as String?;
              if (url != null) {
                final success = await AppUpdateService.openUpdateUrl(url);
                if (success) {
                  AppUpdateService.markUpdateAsSeen();
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('لا يمكن فتح رابط التحديث'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2FBDAF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'تحديث الآن',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
