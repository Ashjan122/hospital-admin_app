import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class SampleRequestsScreen extends StatefulWidget {
  const SampleRequestsScreen({super.key});

  @override
  State<SampleRequestsScreen> createState() => _SampleRequestsScreenState();
}

class _SampleRequestsScreenState extends State<SampleRequestsScreen> {
  String? _currentControlId;
  String? _currentUserName;

  @override
  void initState() {
    super.initState();
    print('SampleRequestsScreen initState called');
    _getCurrentControlId();
  }
  Future<void> _callPhoneNumber(String phone) async {
    final String sanitized = phone.replaceAll(RegExp(r'[^0-9+]+'), '');
    final Uri uri = Uri(scheme: 'tel', path: sanitized);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذّر فتح تطبيق الهاتف: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }


  Future<void> _getCurrentControlId() async {
    print('_getCurrentControlId() called');
    try {
      final prefs = await SharedPreferences.getInstance();
      print('SharedPreferences instance obtained');
      
      // طباعة جميع البيانات المحفوظة في SharedPreferences
      print('=== SharedPreferences Debug ===');
      print('isLoggedIn: ${prefs.getBool('isLoggedIn')}');
      print('userType: ${prefs.getString('userType')}');
      print('userName: ${prefs.getString('userName')}');
      print('userEmail: ${prefs.getString('userEmail')}');
      print('userId: ${prefs.getString('userId')}');
      print('centerId: ${prefs.getString('centerId')}');
      print('centerName: ${prefs.getString('centerName')}');
      print('===============================');
      
      final userName = prefs.getString('userName');
      print('Getting userName from SharedPreferences: $userName');
      setState(() {
        _currentUserName = userName;
      });
      
      if (userName != null) {
        // البحث عن الكنترول في كولكشن controlUsers باستخدام userName
        print('Searching for control user with userName: $userName');
        final querySnapshot = await FirebaseFirestore.instance
            .collection('controlUsers')
            .where('userName', isEqualTo: userName)
            .limit(1)
            .get();
        
        print('Query result: ${querySnapshot.docs.length} documents found');
        
        if (querySnapshot.docs.isNotEmpty) {
          final controlDoc = querySnapshot.docs.first;
          final controlId = controlDoc.id;
          final controlData = controlDoc.data();
          print('Found control user with ID: $controlId');
          print('Control user data: $controlData');
          setState(() {
            _currentControlId = controlId;
          });
        } else {
          print('No control user found with userName: $userName');
          
          // محاولة البحث بجميع المستخدمين في controlUsers
          print('Trying to get all control users...');
          final allControlUsers = await FirebaseFirestore.instance
              .collection('controlUsers')
              .get();
          print('Total control users in database: ${allControlUsers.docs.length}');
          for (var doc in allControlUsers.docs) {
            print('Control user: ${doc.id} - ${doc.data()}');
          }
          
          setState(() {
            _currentControlId = null;
          });
        }
      } else {
        print('No userName found in SharedPreferences');
        setState(() {
          _currentControlId = null;
          _currentUserName = null;
        });
      }
    } catch (e) {
      print('Error getting control ID: $e');
      setState(() {
        _currentControlId = null;
      });
    }
    print('_getCurrentControlId() finished. Final _currentControlId: $_currentControlId');
  }

  Future<void> _receiveRequest(String requestId) async {
    print('_receiveRequest called for requestId: $requestId');
    print('_currentControlId: $_currentControlId');
    
    if (_currentControlId == null) {
      print('_currentControlId is null, showing error');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('خطأ: لم يتم العثور على معرف الكنترول'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      print('Updating request with controlId: $_currentControlId');
      
      await FirebaseFirestore.instance
          .collection('homeSampleRequests')
          .doc(requestId)
          .update({
        'controlId': _currentControlId,
        'receivedAt': FieldValue.serverTimestamp(),
        'status': 'received',
        'receivedByName': _currentUserName,
      });

      print('Request updated successfully');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم استلام الطلب بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error updating request: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في استلام الطلب: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return 'غير محدد';
    
    final dateTime = timestamp.toDate();
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inDays > 0) {
      return 'منذ ${difference.inDays} يوم';
    } else if (difference.inHours > 0) {
      return 'منذ ${difference.inHours} ساعة';
    } else if (difference.inMinutes > 0) {
      return 'منذ ${difference.inMinutes} دقيقة';
    } else {
      return 'الآن';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'طلبات العيادة المنزلية',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF0D47A1),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('homeSampleRequests')
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error, color: Colors.red, size: 64),
                    const SizedBox(height: 16),
                    Text('خطأ في الاتصال: ${snapshot.error}'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {});
                      },
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final allRequests = snapshot.data?.docs ?? [];
            
            // عرض جميع الطلبات
            final pendingRequests = allRequests;

            // ترتيب الطلبات حسب وقت الإنشاء
            pendingRequests.sort((a, b) {
              final aData = a.data() as Map<String, dynamic>;
              final bData = b.data() as Map<String, dynamic>;
              final aTime = aData['createdAt'] as Timestamp?;
              final bTime = bData['createdAt'] as Timestamp?;
              
              if (aTime == null && bTime == null) return 0;
              if (aTime == null) return 1;
              if (bTime == null) return -1;
              
              return bTime.compareTo(aTime); // ترتيب تنازلي
            });

            if (pendingRequests.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.inbox, color: Colors.grey, size: 64),
                    const SizedBox(height: 16),
                    const Text(
                      'لا توجد طلبات',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'لم يتم العثور على أي طلبات للعيادة المنزلية',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'إجمالي الطلبات في النظام: ${allRequests.length}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    if (allRequests.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'الطلبات المعلقة: ${pendingRequests.length}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: pendingRequests.length,
              itemBuilder: (context, index) {
                final request = pendingRequests[index];
                final requestData = request.data() as Map<String, dynamic>;
                final requestId = request.id;
                final receivedByName = requestData['receivedByName']?.toString();
                
                // طباعة جميع الحقول للتشخيص
                print('Request ID: $requestId');
                print('Request Data: $requestData');
                
                // البيانات المطلوبة
                final name = requestData['patientName'] ?? 
                           requestData['name'] ?? 
                           requestData['fullName'] ?? 
                           requestData['userName'] ?? 
                           'غير محدد';
                           
                final phone = requestData['patientPhone'] ?? 
                            requestData['phone'] ?? 
                            requestData['phoneNumber'] ?? 
                            requestData['mobile'] ?? 
                            requestData['contact'] ?? 
                            'غير محدد';
                            
                final serviceType = requestData['serviceType'] ?? 
                                  requestData['service'] ?? 
                                  requestData['type'] ?? 
                                  'غير محدد';
                                  
                final centerName = requestData['centerName'] ?? 
                                 requestData['center'] ?? 
                                 requestData['facilityName'] ?? 
                                 'غير محدد';
                              
                final createdAt = requestData['createdAt'] as Timestamp?;
                final status = requestData['status']?.toString() ?? 'pending';
                final controlId = requestData['controlId'];
                final isReceived = status == 'received' || controlId != null;
                
                // رقم الطلب (الأحدث أولاً، لذا الطلب الأول رقم 1)
                final requestNumber = pendingRequests.length - index;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // رقم الطلب في الأعلى (نص عادي باليمين)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'طلب رقم $requestNumber',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color.fromARGB(255, 17, 1, 1),
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 8),
                        
                        // الاسم كعنوان رئيسي
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        
                        const SizedBox(height: 4),
                        
                        // رقم الهاتف (قابل للنقر للاتصال)
                        InkWell(
                          onTap: () => _callPhoneNumber(phone.toString()),
                          child: Text(
                            phone,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF0D47A1),
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 4),
                        
                        // نوع الطلب
                        Text(
                          'نوع الطلب: $serviceType',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black87,
                          ),
                        ),
                        
                        const SizedBox(height: 4),
                        
                        // مقدم الخدمة
                        Text(
                          'مقدم الخدمة: $centerName',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        
                        // الزمن بدون "زمن الطلب" وباللون الرمادي
                        Text(
                          _formatTimestamp(createdAt),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                        
                        const SizedBox(height: 10),
                        
                        // Action button
                        SizedBox(
                          width: double.infinity,
                          child: isReceived
                              ? Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                                  ),
                                  child: Text(
                                    (receivedByName != null && receivedByName.isNotEmpty)
                                        ? 'تم الاستلام من قبل $receivedByName'
                                        : 'تم الاستلام',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                )
                              : ElevatedButton(
                                  onPressed: () => _receiveRequest(requestId),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0D47A1),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: const Text(
                                    'استلام الطلب',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

}
