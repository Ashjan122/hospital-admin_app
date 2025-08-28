import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import '../services/sms_service.dart';
import 'doctor_bookings_screen.dart';

class NotificationsScreen extends StatefulWidget {
  final String userId;
  final String centerName;
  final VoidCallback? onNotificationsChanged;

  const NotificationsScreen({
    super.key,
    required this.userId,
    required this.centerName,
    this.onNotificationsChanged,
  });

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    try {
      print('Loading notifications for user: ${widget.userId}');
      final notifications = await NotificationService.getNotifications(widget.userId);
      print('Loaded ${notifications.length} notifications');
      
      // طباعة حالة كل إشعار
      for (var notification in notifications) {
        print('Notification ${notification['id']}: isRead = ${notification['isRead']}');
      }
      
      setState(() {
        _notifications = notifications;
        _loading = false;
      });
      
      print('Notifications loaded in UI: ${_notifications.length}');
    } catch (e) {
      print('Error loading notifications: $e');
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _markAsRead(String notificationId) async {
    print('Marking notification as read in UI: $notificationId');
    
    // تحديث حالة الإشعار في القائمة المحلية فوراً
    setState(() {
      final index = _notifications.indexWhere((n) => n['id'] == notificationId);
      if (index != -1) {
        _notifications[index]['isRead'] = true;
        print('Updated notification in UI: ${_notifications[index]['id']} isRead = ${_notifications[index]['isRead']}');
      } else {
        print('WARNING: Notification not found in UI list: $notificationId');
      }
    });
    
    // حفظ التغيير في التخزين المحلي
    print('Saving to storage...');
    await NotificationService.markAsRead(widget.userId, notificationId);
    print('Saved to storage successfully');
    
    // إخطار شاشة الاستقبال بتحديث عدد الإشعارات
    widget.onNotificationsChanged?.call();
    
    // التحقق النهائي من أن البيانات تم حفظها
    await Future.delayed(const Duration(milliseconds: 200));
    final verification = await NotificationService.getNotifications(widget.userId);
    final notification = verification.firstWhere((n) => n['id'] == notificationId, orElse: () => {});
    if (notification.isNotEmpty) {
      print('Final verification: Notification ${notification['id']} isRead = ${notification['isRead']}');
    }
  }

  Future<void> _deleteNotification(String notificationId) async {
    // حذف الإشعار من القائمة المحلية فوراً
    setState(() {
      _notifications.removeWhere((n) => n['id'] == notificationId);
    });
    
    // حذف من التخزين المحلي
    await NotificationService.deleteNotification(widget.userId, notificationId);
    
    // إخطار شاشة الاستقبال بتحديث عدد الإشعارات
    widget.onNotificationsChanged?.call();
  }

  void _navigateToDoctorBookings(Map<String, dynamic> notification) async {
    print('Navigating to doctor bookings for notification: ${notification['id']}');
    print('Current isRead status: ${notification['isRead']}');
    
    // تحديد الإشعار كمقروء عند الضغط عليه
    if (notification['isRead'] != true && notification['isRead'] != 'true') {
      print('Marking notification as read before navigation...');
      await _markAsRead(notification['id']);
      print('Notification marked as read successfully');
    } else {
      print('Notification is already read');
    }
    
    // إظهار رسالة تأكيد
    if (mounted && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('جاري الانتقال إلى حجوزات د. ${notification['doctorName']}'),
          backgroundColor: const Color(0xFF2FBDAF),
          duration: const Duration(seconds: 2),
        ),
      );
    }
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DoctorBookingsScreen(
          doctorId: notification['doctorId'],
          centerId: notification['centerId'],
          centerName: widget.centerName,
          doctorName: notification['doctorName'],
        ),
      ),
    );
  }

  Future<void> _clearAllNotifications() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل أنت متأكد من حذف جميع الإشعارات؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('حذف الكل'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // مسح جميع الإشعارات من القائمة المحلية فوراً
      setState(() {
        _notifications.clear();
      });
      
      // مسح من التخزين المحلي
      await NotificationService.clearAllNotifications(widget.userId);
      
      // إخطار شاشة الاستقبال بتحديث عدد الإشعارات
      widget.onNotificationsChanged?.call();
    }
  }

  String formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return intl.DateFormat('EEEE, yyyy/MM/dd', 'ar').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  String formatTime(String timeStr) {
    try {
      final date = DateTime.parse(timeStr);
      return intl.DateFormat('HH:mm', 'ar').format(date);
    } catch (e) {
      return timeStr;
    }
  }

  String formatNotificationTime(String timestamp) {
    try {
      final date = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(date);
      
      if (difference.inMinutes < 1) {
        return 'الآن';
      } else if (difference.inMinutes < 60) {
        return 'منذ ${difference.inMinutes} دقيقة';
      } else if (difference.inHours < 24) {
        return 'منذ ${difference.inHours} ساعة';
      } else {
        return intl.DateFormat('dd/MM/yyyy HH:mm', 'ar').format(date);
      }
    } catch (e) {
      return 'وقت غير محدد';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'الإشعارات',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF2FBDAF),
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadNotifications,
              tooltip: 'تحديث',
            ),
            if (_notifications.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.clear_all),
                onPressed: _clearAllNotifications,
                tooltip: 'حذف الكل',
              ),
          ],
        ),
        body: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF2FBDAF),
                  ),
                )
              : _notifications.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.notifications_none,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'لا توجد إشعارات',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _notifications.length,
                      itemBuilder: (context, index) {
                        final notification = _notifications[index];
                        final isRead = notification['isRead'] == true || notification['isRead'] == 'true';
                        final timestamp = DateTime.tryParse(notification['timestamp'] ?? '');
                        
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: isRead ? Colors.white : Colors.blue[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isRead ? Colors.grey[300]! : Colors.blue[200]!,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.1),
                                spreadRadius: 1,
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: InkWell(
                            onTap: () => _navigateToDoctorBookings(notification),
                            borderRadius: BorderRadius.circular(12),
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(16),
                            leading: CircleAvatar(
                              backgroundColor: isRead ? Colors.grey[300] : Colors.blue[100],
                              child: Icon(
                                Icons.calendar_today,
                                color: isRead ? Colors.grey[600] : Colors.blue[700],
                              ),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'حجز جديد - د. ${notification['doctorName']}',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                                      color: isRead ? Colors.grey[700] : Colors.black87,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_forward_ios,
                                  size: 16,
                                  color: Colors.grey[400],
                                ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  'المريض: ${notification['patientName']}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'التاريخ: ${formatDate(notification['appointmentDate'])}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[500],
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'الوقت: ${notification['appointmentTime']}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[500],
                                  ),
                                ),
                                if (timestamp != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    '${formatNotificationTime(notification['timestamp'])}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey[400],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) {
                                switch (value) {
                                  case 'read':
                                    _markAsRead(notification['id']);
                                    break;
                                  case 'delete':
                                    _deleteNotification(notification['id']);
                                    break;
                                }
                              },
                              itemBuilder: (context) => [
                                if (!isRead)
                                  const PopupMenuItem(
                                    value: 'read',
                                    child: Row(
                                      children: [
                                        Icon(Icons.check, size: 16),
                                        SizedBox(width: 8),
                                        Text('تحديد كمقروء'),
                                      ],
                                    ),
                                  ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete, size: 16, color: Colors.red),
                                      SizedBox(width: 8),
                                      Text('حذف', style: TextStyle(color: Colors.red)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                      },
                    ),
        ),
      ),
    );
  }
}
