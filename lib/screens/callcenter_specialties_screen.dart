import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:hospital_admin_app/screens/callcenter_doctors_screen.dart';
import 'package:hospital_admin_app/widgets/optimized_loading_widget.dart';



class CallcenterSpecialtiesScreen extends StatefulWidget {
  final String centerId;
  final String centerName;
  const CallcenterSpecialtiesScreen({super.key, required this.centerId, required this.centerName});

  @override
  State<CallcenterSpecialtiesScreen> createState() => _CallcenterSpecialtiesScreenState();
}

class _CallcenterSpecialtiesScreenState extends State<CallcenterSpecialtiesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<QueryDocumentSnapshot> _allSpecialties = [];
  bool _isSearching = false;

  Future<List<QueryDocumentSnapshot>> fetchSpecialties() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .where('isActive', isEqualTo: true)
          .orderBy('order')
          .get()
          .timeout(const Duration(seconds: 8));

      _allSpecialties = snapshot.docs;
      return snapshot.docs;
    } catch (e) {
      print('خطأ في تحميل التخصصات (الترتيب من القاعدة): $e');
      // fallback: بدون orderBy من القاعدة، نجلب ونرتب محلياً إذا توفر الحقل
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('medicalFacilities')
            .doc(widget.centerId)
            .collection('specializations')
            .where('isActive', isEqualTo: true)
            .get()
            .timeout(const Duration(seconds: 8));

        final docs = snapshot.docs..sort((a, b) {
          final ad = (a.data());
          final bd = (b.data());
          final ao = (ad['order'] is num) ? (ad['order'] as num).toInt() : 0;
          final bo = (bd['order'] is num) ? (bd['order'] as num).toInt() : 0;
          return ao.compareTo(bo);
        });
        _allSpecialties = docs;
        return docs;
      } catch (e2) {
        print('خطأ في تحميل التخصصات (فرز محلي): $e2');
        return [];
      }
    }
  }

  List<QueryDocumentSnapshot> getFilteredSpecialties() {
    if (_searchQuery.isEmpty) {
      return _allSpecialties;
    }
    
    return _allSpecialties.where((specialty) {
      final data = specialty.data() as Map<String, dynamic>;
      final specName = data['specName']?.toString().toLowerCase() ?? '';
      final searchLower = _searchQuery.toLowerCase();
      
      return specName.contains(searchLower);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          actions: [
            _isSearching
                ? IconButton(
                    onPressed: () {
                      setState(() {
                        _isSearching = false;
                        _searchQuery = '';
                        _searchController.clear();
                      });
                    },
                    icon: Icon(Icons.close, color: Color(0xFF2FBDAF)),
                  )
                : IconButton(
                    onPressed: () {
                      setState(() {
                        _isSearching = true;
                      });
                    },
                    icon: Icon(Icons.search, color: Color(0xFF2FBDAF)),
                  ),
          ],
          title: _isSearching
              ? TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'البحث عن تخصص طبي...',
                    border: InputBorder.none,
                    hintStyle: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 16,
                    ),
                  ),
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                  ),
                )
              : Text(
                  "التخصصات الطبية",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF2FBDAF),
                    fontSize: 30,
                  ),
                ),
        ),
        body: SafeArea(
          child: FutureBuilder<List<QueryDocumentSnapshot>>(
            future: fetchSpecialties(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const OptimizedLoadingWidget(
                  message: 'جاري تحميل التخصصات...',
                  color: Color(0xFF2FBDAF),
                );
              }

              final specialties = _searchQuery.isEmpty ? snapshot.data ?? [] : getFilteredSpecialties();
              if (specialties.isEmpty) {
                return Center(
                  child: _searchQuery.isNotEmpty
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search_off,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'لا يوجد تخصصات تطابق البحث',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.medical_services_outlined,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'لا توجد تخصصات حالياً',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                );
              }

              return ListView.builder(
                itemCount: specialties.length,
                itemBuilder: (context, index) {
                  final doc = specialties[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final specName = data['specName'] ?? 'تخصص غير معروف';
                  final specId = doc.id;

                  return Card(
                    elevation: 6,
                    margin: EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('medicalFacilities')
                          .doc(widget.centerId)
                          .collection('specializations')
                          .doc(specId)
                          .collection('subSpecialties')
                          .snapshots(),
                      builder: (context, subSnapshot) {
                        final subSpecialties = subSnapshot.data?.docs ?? [];
                        final hasSubSpecialties = subSpecialties.isNotEmpty;

                        if (hasSubSpecialties) {
                          // إذا كان هناك تخصصات فرعية، استخدم ExpansionTile
                          return ExpansionTile(
                            title: Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                specName,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                            children: [
                              ...subSpecialties.map((subDoc) {
                                final subData = subDoc.data() as Map<String, dynamic>;
                                final subName = subData['name'] ?? 'تخصص فرعي غير معروف';
                                final subId = subDoc.id;
                                
                                return InkWell(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => CallcenterDoctorsScreen(
                                          centerId: widget.centerId,
                                          specId: specId, // استخدام التخصص الرئيسي
                                          specializationName: subName,
                                          subSpecialtyId: subId, // التخصص الفرعي
                                        ),
                                      ),
                                    );
                                  },
                                  child: ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.arrow_left, size: 16),
                                    title: Text(subName),
                                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                                  ),
                                );
                              }).toList(),
                            ],
                          );
                        } else {
                          // إذا لم يكن هناك تخصصات فرعية، استخدم InkWell مباشرة
                          return InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => CallcenterDoctorsScreen(
                                    centerId: widget.centerId,
                                    specId: specId,
                                    specializationName: specName,
                                  ),
                                ),
                              );
                            },
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                              title: Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  specName,
                                  style: const TextStyle(
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                            ),
                          );
                        }
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}