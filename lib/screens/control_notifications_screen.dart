import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';

class ControlNotificationsScreen extends StatefulWidget {
  const ControlNotificationsScreen({super.key});

  @override
  State<ControlNotificationsScreen> createState() => _ControlNotificationsScreenState();
}

class _ControlNotificationsScreenState extends State<ControlNotificationsScreen> {
  bool _isSubscribed = false;
  bool _isHomeClinicSubscribed = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkSubscriptionStatus();
    _ensureNotificationPermissions();
  }

  Future<void> _ensureNotificationPermissions() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      print('Notification permission status: ${settings.authorizationStatus}');
      
        // الاشتراك في توبك new_signup (نفس توبك الحسابات الجديدة)
        try {
          await messaging.subscribeToTopic('new_signup');
          print('Successfully subscribed to new_signup topic');
          
          // حفظ حالة الاشتراك
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('subscribed_to_new_signup', true);
          
        } catch (e) {
          print('Error subscribing to new_signup topic: $e');
        }
        
        // تم إلغاء الاشتراك التلقائي في إشعارات المعامل
    } catch (e) {
      print('Error requesting notification permissions: $e');
    }
  }

  Future<void> _checkSubscriptionStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isSubscribed = prefs.getBool('subscribed_to_new_signup') ?? false;
      final isHomeClinicSubscribed = prefs.getBool('subscribed_to_home_clinic_requests') ?? false;
      // لم نعد ندير اشتراك إشعارات المعامل
      
      // إذا كان مشترك محلياً، تأكد من الاشتراك في Firebase
      if (isSubscribed) {
        try {
          await FirebaseMessaging.instance.subscribeToTopic('new_signup');
          print('Re-subscribed to new_signup topic');
        } catch (e) {
          print('Error re-subscribing to new_signup topic: $e');
        }
      } else {
        // إذا لم يكن مشترك، اشترك تلقائياً
        try {
          await FirebaseMessaging.instance.subscribeToTopic('new_signup');
          await prefs.setBool('subscribed_to_new_signup', true);
          print('Auto-subscribed to new_signup topic');
        } catch (e) {
          print('Error auto-subscribing to new_signup topic: $e');
        }
      }
      
      // إدارة اشتراك طلبات العيادة المنزلية
      if (isHomeClinicSubscribed) {
        try {
          await FirebaseMessaging.instance.subscribeToTopic('home_clinic_requests');
          print('Re-subscribed to home_clinic_requests topic');
        } catch (e) {
          print('Error re-subscribing to home_clinic_requests topic: $e');
        }
      }
      
      // تم إلغاء إدارة اشتراك إشعارات المعامل
      
      setState(() {
        _isSubscribed = true; // دائماً مشترك في إشعارات الحسابات
        _isHomeClinicSubscribed = isHomeClinicSubscribed;
        _isLoading = false;
      });
    } catch (e) {
      print('Error checking subscription status: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleSubscription() async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (_isSubscribed) {
        // Unsubscribe
        await FirebaseMessaging.instance.unsubscribeFromTopic('new_signup');
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('subscribed_to_new_signup', false);
        
        setState(() {
          _isSubscribed = false;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم إلغاء الاشتراك في إشعارات الحسابات الجديدة'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        // Subscribe
        await FirebaseMessaging.instance.subscribeToTopic('new_signup');
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('subscribed_to_new_signup', true);
        
        setState(() {
          _isSubscribed = true;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم الاشتراك في إشعارات الحسابات الجديدة'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      print('Error toggling subscription: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تغيير حالة الاشتراك: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleHomeClinicSubscription() async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (_isHomeClinicSubscribed) {
        // Unsubscribe
        await FirebaseMessaging.instance.unsubscribeFromTopic('home_clinic_requests');
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('subscribed_to_home_clinic_requests', false);
        
        setState(() {
          _isHomeClinicSubscribed = false;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم إلغاء الاشتراك في إشعارات طلبات العيادة المنزلية'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        // Subscribe
        await FirebaseMessaging.instance.subscribeToTopic('home_clinic_requests');
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('subscribed_to_home_clinic_requests', true);
        
        setState(() {
          _isHomeClinicSubscribed = true;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم الاشتراك في إشعارات طلبات العيادة المنزلية'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      print('Error toggling home clinic subscription: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تغيير حالة الاشتراك: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // تم إزالة ميزة إشعارات المعامل

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'إشعارات الكنترول',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF0D47A1),
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Subscription Status Card
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isSubscribed ? Colors.green : Colors.orange,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isSubscribed ? Icons.notifications_active : Icons.notifications_off,
                          color: _isSubscribed ? Colors.green : Colors.orange,
                          size: 32,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'إشعارات الحسابات الجديدة',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: _isSubscribed ? Colors.green : Colors.orange,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isSubscribed 
                                    ? 'أنت مشترك في تلقي إشعارات الحسابات الجديدة'
                                    : 'أنت غير مشترك في إشعارات الحسابات الجديدة',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _toggleSubscription,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Icon(_isSubscribed ? Icons.notifications_off : Icons.notifications_active),
                        label: Text(
                          _isLoading
                              ? 'جاري التحديث...'
                              : _isSubscribed
                                  ? 'إلغاء الاشتراك'
                                  : 'الاشتراك في الإشعارات',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isSubscribed ? Colors.orange : Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              // Home Clinic Requests Subscription Card
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isHomeClinicSubscribed ? Colors.green : Colors.orange,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isHomeClinicSubscribed ? Icons.notifications_active : Icons.notifications_off,
                          color: _isHomeClinicSubscribed ? Colors.green : Colors.orange,
                          size: 32,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'إشعارات طلبات العيادة المنزلية',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: _isHomeClinicSubscribed ? Colors.green : Colors.orange,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isHomeClinicSubscribed 
                                    ? 'أنت مشترك في تلقي إشعارات طلبات العيادة المنزلية'
                                    : 'أنت غير مشترك في إشعارات طلبات العيادة المنزلية',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _toggleHomeClinicSubscription,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Icon(_isHomeClinicSubscribed ? Icons.notifications_off : Icons.notifications_active),
                        label: Text(
                          _isLoading
                              ? 'جاري التحديث...'
                              : _isHomeClinicSubscribed
                                  ? 'إلغاء الاشتراك'
                                  : 'الاشتراك في الإشعارات',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isHomeClinicSubscribed ? Colors.orange : Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              // تم إلغاء بطاقة إشعارات المعامل
              
              // تم إلغاء عرض الإشعارات السابقة
            ],
          ),
        ),
      ),
    );
  }


}
