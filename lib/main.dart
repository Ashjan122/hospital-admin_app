import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hospital_admin_app/firebase_options.dart';
import 'package:hospital_admin_app/screens/call_center_screen.dart';
import 'package:hospital_admin_app/screens/control_panel_screen.dart';
import 'package:hospital_admin_app/screens/dashboard_screen.dart';
import 'package:hospital_admin_app/screens/doctor_user_screen.dart';
import 'package:hospital_admin_app/screens/login_screen.dart';
import 'package:hospital_admin_app/screens/reception_staff_screen.dart';
import 'package:hospital_admin_app/screens/sample_requests_screen.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'secondary_firebase_options.dart';

// Handle background messages
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await Firebase.initializeApp(
    name: 'secondaryApp',
    options: secondaryFirebaseOptions,
  );

  print('Handling a background message: ${message.messageId}');
  print('Message data: ${message.data}');

  if (message.notification != null) {
    print(
      'Background notification: ${message.notification?.title} - ${message.notification?.body}',
    );
  }
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> _handleNotificationNavigation(RemoteMessage message) async {
  try {
    final type = message.data['type']?.toString();
    if (type == 'new_home_clinic_request') {
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
      final userType = prefs.getString('userType');
      if (isLoggedIn && userType == 'control') {
        navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (context) => const SampleRequestsScreen()),
        );
      }
    }
  } catch (e) {
    // ignore navigation errors
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await Firebase.initializeApp(
    name: 'secondaryApp',
    options: secondaryFirebaseOptions,
  );
  await initializeDateFormatting('ar', null);
  Widget initialScreen = const LoginScreen();

  final user = FirebaseAuth.instance.currentUser;

  if (user != null) {
    try {
      final doc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;

        final role = data['role']?.toString() ?? '';
        final userType = data['userType']?.toString() ?? '';

        final centerId = data['facilityId']?.toString() ?? '';
        final centerName = data['facilityName']?.toString() ?? '';
        final userName = data['displayName']?.toString() ?? '';

        if (role == 'superadmin') {
          initialScreen = const ControlPanelScreen();
        } else if (userType == 'admin') {
          initialScreen = DashboardScreen(
            centerId: centerId,
            centerName: centerName,
            fromControlPanel: false,
          );
        } else if (userType == 'callcenter') {
          initialScreen = CallCenterScreen(
            centerId: centerId,
            centerName: centerName,
            userId: user.uid,
            userName: userName,
          );
        } else if (userType == 'reception') {
          initialScreen = ReceptionStaffScreen(
            centerId: centerId,
            centerName: centerName,
            userId: user.uid,
            userName: userName,
          );
        } else if (userType == 'doctor') {
          final doctorId = data['doctorId']?.toString() ?? '';
          final doctorName = data['doctorName']?.toString() ?? '';

          if (doctorId.isNotEmpty) {
            initialScreen = DoctorUserScreen(
              doctorId: doctorId,
              centerId: centerId,
              centerName: centerName,
              doctorName: doctorName,
            );
          }
        }

        // حفظ البيانات محلياً
        final prefs = await SharedPreferences.getInstance();

        await prefs.setBool('isLoggedIn', true);
        await prefs.setString('userId', user.uid);
        await prefs.setString('userName', userName);
        await prefs.setString('userType', userType);
        await prefs.setString('role', role);
        await prefs.setString('centerId', centerId);
        await prefs.setString('centerName', centerName);
      }
    } catch (e) {
      print('Auto login error: $e');
      initialScreen = const LoginScreen();
    }
  }

  // Initialize Firebase Messaging
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Request permission for notifications
  FirebaseMessaging messaging = FirebaseMessaging.instance;
  NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    announcement: false,
    badge: true,
    carPlay: false,
    criticalAlert: false,
    provisional: false,
    sound: true,
  );

  print('User granted permission: ${settings.authorizationStatus}');

  // Get FCM token
  String? token = await messaging.getToken();
  print('FCM Token: $token');

  // Note: Subscription to new_signup topic is handled in ControlNotificationsScreen

  // Set up auto-initialization for better background handling
  await messaging.setAutoInitEnabled(true);

  // Configure notification channel for Android
  await messaging.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  // Handle foreground messages
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print('Got a message whilst in the foreground!');
    print('Message data: ${message.data}');

    if (message.notification != null) {
      print('Message also contained a notification: ${message.notification}');
    }
  });

  // Handle messages when app is opened from background
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
    print('A new onMessageOpenedApp event was published!');
    print('Message data: ${message.data}');
    await _handleNotificationNavigation(message);
  });

  // Handle messages when app is opened from terminated state
  final RemoteMessage? initialMessage =
      await FirebaseMessaging.instance.getInitialMessage();

  runApp(HospitalAdminApp(initialScreen: initialScreen));

  if (initialMessage != null) {
    // Delay to ensure navigator is ready
    Future.microtask(() => _handleNotificationNavigation(initialMessage));
  }
}

class HospitalAdminApp extends StatelessWidget {
  final Widget initialScreen;

  const HospitalAdminApp({super.key, required this.initialScreen});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'تطبيق إدارة المراكز الطبية',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'SA'),
      supportedLocales: const [Locale('ar', 'SA'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        primarySwatch: const MaterialColor(0xFF2FBDAF, <int, Color>{
          50: Color(0xFFE0F7FA),
          100: Color(0xFFB2EBF2),
          200: Color(0xFF80DEEA),
          300: Color(0xFF4DD0E1),
          400: Color(0xFF26C6DA),
          500: Color.fromARGB(255, 34, 96, 129),
          600: Color(0xFF00ACC1),
          700: Color(0xFF0097A7),
          800: Color(0xFF00838F),
          900: Color(0xFF006064),
        }),
        primaryColor: const Color.fromARGB(255, 34, 96, 129),
        fontFamily: 'Cairo',
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontSize: 16),
          bodyMedium: TextStyle(fontSize: 14),
        ),
      ),
      home: initialScreen,
    );
  }
}
