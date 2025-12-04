import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hospital_admin_app/services/central_data_service.dart';
import 'package:hospital_admin_app/screens/sub_specialties_screen.dart';

class CentralSpecialtiesScreen extends StatefulWidget {
  const CentralSpecialtiesScreen({super.key});

  @override
  State<CentralSpecialtiesScreen> createState() => _CentralSpecialtiesScreenState();
}

class _CentralSpecialtiesScreenState extends State<CentralSpecialtiesScreen> {
  String _searchQuery = '';
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'إدارة التخصصات',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF0D47A1),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Search bar
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.grey[50],
                child: TextField(
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'البحث في التخصصات...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),
              // Specialties list
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('medicalSpecialties')
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
                          ],
                        ),
                      );
                    }

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final specialties = snapshot.data?.docs ?? [];
                    
                    // Filter specialties based on search query
                    final filteredSpecialties = specialties.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final name = data['name']?.toString().toLowerCase() ?? '';
                      final description = data['description']?.toString().toLowerCase() ?? '';
                      return name.contains(_searchQuery.toLowerCase()) ||
                             description.contains(_searchQuery.toLowerCase());
                    }).toList();

                    if (filteredSpecialties.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _searchQuery.isEmpty ? Icons.medical_services : Icons.search_off,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty 
                                  ? 'لا توجد تخصصات'
                                  : 'لم يتم العثور على تخصصات تطابق البحث',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredSpecialties.length,
                      itemBuilder: (context, index) {
                        final doc = filteredSpecialties[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final name = data['name'] ?? 'تخصص غير معروف';
                        final description = data['description'] ?? '';

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(10),
                            
                            title: Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            subtitle: description.isNotEmpty
                                ? Text(description)
                                : null,
                            trailing: Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    IconButton(
      icon: const Icon(Icons.account_tree), // أيقونة التخصصات الفرعية
      onPressed: () => _openSubSpecialtiesScreen(doc.id, name),
    ),
    IconButton(
      icon: const Icon(Icons.edit),
      onPressed: () => _showEditSpecialtyDialog(
        doc.id,
        name,
        description,
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
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showAddSpecialtyDialog(),
          backgroundColor: const Color(0xFF0D47A1),
          foregroundColor: Colors.white,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Future<String> _getNextNumericId(String collectionPath) async {
    final snapshot = await FirebaseFirestore.instance.collection(collectionPath).get();
    int maxId = 0;
      for (final doc in snapshot.docs) {
        int? idNum = int.tryParse(doc.id);
        if (idNum == null) {
          final data = doc.data();
          final dynamic fieldId = data['id'];
        if (fieldId is int) {
          idNum = fieldId;
        } else if (fieldId is String) {
          idNum = int.tryParse(fieldId);
        }
      }
      if (idNum != null && idNum > maxId) maxId = idNum;
    }
    return (maxId + 1).toString();
  }
  void _openSubSpecialtiesScreen(String id, String name) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => SubSpecialtiesScreen(parentId: id, parentName: name),
    ),
  );
}


  void _showAddSpecialtyDialog() {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة تخصص جديد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'اسم التخصص',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(
                labelText: 'وصف التخصص (اختياري)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isNotEmpty) {
                Navigator.pop(context);
                await _addSpecialty(
                  nameController.text.trim(),
                  descriptionController.text.trim(),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D47A1),
              foregroundColor: Colors.white,
            ),
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
  }

  void _showEditSpecialtyDialog(String id, String currentName, String currentDescription) {
    final nameController = TextEditingController(text: currentName);
    final descriptionController = TextEditingController(text: currentDescription);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تعديل التخصص'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'اسم التخصص',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(
                labelText: 'وصف التخصص (اختياري)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isNotEmpty) {
                Navigator.pop(context);
                await _updateSpecialty(
                  id,
                  nameController.text.trim(),
                  descriptionController.text.trim(),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D47A1),
              foregroundColor: Colors.white,
            ),
            child: const Text('تحديث'),
          ),
        ],
      ),
    );
  }

  Future<void> _addSpecialty(String name, String description) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Prevent duplicates (case-insensitive)
      final existingSnap = await FirebaseFirestore.instance
          .collection('medicalSpecialties')
          .get();
      final lower = name.trim().toLowerCase();
      final bool exists = existingSnap.docs.any((d) {
        final data = d.data();
        final existingName = (data['name']?.toString() ?? '').trim().toLowerCase();
        return existingName == lower;
      });

      if (exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('هذا التخصص موجود بالفعل'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final id = await _getNextNumericId('medicalSpecialties');
      
      await FirebaseFirestore.instance
          .collection('medicalSpecialties')
          .doc(id)
          .set({
        'id': int.tryParse(id) ?? id,
        'name': name,
        'description': description,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم إضافة التخصص "$name" بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في إضافة التخصص: $e'),
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

  Future<void> _updateSpecialty(String id, String name, String description) async {
    setState(() {
      _isLoading = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('medicalSpecialties')
          .doc(id)
          .update({
        'name': name,
        'description': description,
      });

      // مزامنة الاسم إلى جميع المراكز التي تستخدم هذا التخصص
      await CentralDataService.propagateSpecialtyUpdate(
        specialtyId: id,
        name: name,
        description: description,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تحديث التخصص "$name" بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحديث التخصص: $e'),
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

  void _showAddAllSpecialtiesDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة جميع التخصصات الطبية'),
        content: const Text(
          'سيتم إضافة جميع التخصصات الطبية الرئيسية مع التخصصات الفرعية لكل تخصص.\n\nملاحظة: سيتم التحقق من كل تخصص قبل الإضافة لتجنب التكرار.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _addAllMedicalSpecialties();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D47A1),
              foregroundColor: Colors.white,
            ),
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
  }

  Future<void> _addAllMedicalSpecialties() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // قائمة بجميع التخصصات الطبية الرئيسية مع التخصصات الفرعية
      final Map<String, Map<String, dynamic>> specialties = {
        '1': {
          'name': 'أمراض القلب والشرايين',
          'description': 'تخصص في تشخيص وعلاج أمراض القلب والأوعية الدموية',
          'subSpecialties': [
            'أمراض القلب التاجية',
            'قصور القلب',
            'اضطرابات النظم القلبية',
            'أمراض صمامات القلب',
            'ارتفاع ضغط الدم',
            'أمراض القلب الخلقية',
            'أمراض الأوعية الدموية',
            'أمراض القلب عند الأطفال',
          ],
        },
        '2': {
          'name': 'أمراض الجهاز العصبي',
          'description': 'تخصص في تشخيص وعلاج أمراض الجهاز العصبي',
          'subSpecialties': [
            'الصرع',
            'السكتة الدماغية',
            'مرض باركنسون',
            'التصلب المتعدد',
            'الصداع والصداع النصفي',
            'أمراض العضلات والأعصاب',
            'الخرف والزهايمر',
            'أمراض النخاع الشوكي',
          ],
        },
        '3': {
          'name': 'جراحة العظام والمفاصل',
          'description': 'تخصص في تشخيص وعلاج أمراض العظام والمفاصل',
          'subSpecialties': [
            'جراحة العمود الفقري',
            'جراحة اليد والرسغ',
            'جراحة الركبة',
            'جراحة الورك',
            'جراحة الكتف',
            'جراحة القدم والكاحل',
            'جراحة العظام عند الأطفال',
            'جراحة الأورام العظمية',
          ],
        },
        '4': {
          'name': 'أمراض الجلد',
          'description': 'تخصص في تشخيص وعلاج أمراض الجلد',
          'subSpecialties': [
            'الأمراض الجلدية الالتهابية',
            'أمراض الجلد المعدية',
            'أورام الجلد',
            'أمراض الشعر والأظافر',
            'أمراض الجلد المناعية',
            'التجميل والليزر',
            'أمراض الجلد عند الأطفال',
            'أمراض الجلد الوراثية',
          ],
        },
        '5': {
          'name': 'طب الأطفال',
          'description': 'تخصص في رعاية وعلاج الأطفال',
          'subSpecialties': [
            'طب الأطفال حديثي الولادة',
            'أمراض القلب عند الأطفال',
            'أمراض الجهاز العصبي عند الأطفال',
            'أمراض الجهاز الهضمي عند الأطفال',
            'أمراض الجهاز التنفسي عند الأطفال',
            'أمراض الدم والأورام عند الأطفال',
            'أمراض الكلى عند الأطفال',
            'أمراض الغدد الصماء عند الأطفال',
          ],
        },
        '6': {
          'name': 'الطب الباطني',
          'description': 'تخصص في تشخيص وعلاج الأمراض الداخلية',
          'subSpecialties': [
            'الطب الباطني العام',
            'أمراض القلب الباطنية',
            'أمراض الجهاز الهضمي الباطنية',
            'أمراض الكلى الباطنية',
            'أمراض الغدد الصماء الباطنية',
            'أمراض الروماتيزم الباطنية',
            'أمراض الدم الباطنية',
            'أمراض الجهاز التنفسي الباطنية',
          ],
        },
        '7': {
          'name': 'جراحة عامة',
          'description': 'تخصص في الجراحة العامة',
          'subSpecialties': [
            'جراحة الجهاز الهضمي',
            'جراحة الغدد الصماء',
            'جراحة الأوعية الدموية الطرفية',
            'جراحة الصدر العامة',
            'جراحة المناظير',
            'جراحة السمنة',
            'جراحة الأورام العامة',
            'جراحة الطوارئ',
          ],
        },
        '8': {
          'name': 'طب النساء والولادة',
          'description': 'تخصص في رعاية صحة المرأة والحمل والولادة',
          'subSpecialties': [
            'أمراض النساء',
            'العقم وأطفال الأنابيب',
            'أورام النساء',
            'طب الأم والجنين',
            'جراحة النساء',
            'تنظيم الأسرة',
            'جراحة المناظير النسائية',
            'أمراض الثدي',
          ],
        },
        '9': {
          'name': 'طب العيون',
          'description': 'تخصص في تشخيص وعلاج أمراض العيون',
          'subSpecialties': [
            'جراحة الشبكية',
            'جراحة القرنية',
            'جراحة الجفون',
            'أمراض الشبكية',
            'المياه البيضاء',
            'المياه الزرقاء',
            'أمراض العيون عند الأطفال',
            'جراحة العيون التجميلية',
          ],
        },
        '10': {
          'name': 'أنف وأذن وحنجرة',
          'description': 'تخصص في تشخيص وعلاج أمراض الأنف والأذن والحنجرة',
          'subSpecialties': [
            'جراحة الأنف والجيوب',
            'جراحة الأذن',
            'جراحة الحنجرة',
            'جراحة الرأس والرقبة',
            'جراحة السمع',
            'أمراض الصوت',
            'جراحة الأنف التجميلية',
            'أمراض الأنف والأذن عند الأطفال',
          ],
        },
        '11': {
          'name': 'الطب النفسي',
          'description': 'تخصص في تشخيص وعلاج الأمراض النفسية',
          'subSpecialties': [
            'الطب النفسي للبالغين',
            'الطب النفسي للأطفال',
            'الطب النفسي للمسنين',
            'إدمان المخدرات',
            'الطب النفسي الشرعي',
            'العلاج النفسي',
            'الطب النفسي العصبي',
            'الطب النفسي الجسدي',
          ],
        },
        '12': {
          'name': 'الأشعة والتصوير الطبي',
          'description': 'تخصص في التصوير الطبي والتشخيص',
          'subSpecialties': [
            'الأشعة المقطعية',
            'الرنين المغناطيسي',
            'الموجات فوق الصوتية',
            'أشعة التداخلية',
            'أشعة الثدي',
            'أشعة الأطفال',
            'أشعة القلب',
            'أشعة العظام',
          ],
        },
        '13': {
          'name': 'التخدير',
          'description': 'تخصص في التخدير والعناية المركزة',
          'subSpecialties': [
            'تخدير الجراحة العامة',
            'تخدير القلب',
            'تخدير الأطفال',
            'تخدير التوليد',
            'العناية المركزة',
            'إدارة الألم',
            'تخدير جراحة الأعصاب',
            'تخدير جراحة العظام',
          ],
        },
        '14': {
          'name': 'الطب الطوارئ',
          'description': 'تخصص في علاج الحالات الطارئة',
          'subSpecialties': [
            'طب الطوارئ للبالغين',
            'طب الطوارئ للأطفال',
            'طب الطوارئ للصدمات',
            'طب الطوارئ للقلب',
            'طب الطوارئ العصبي',
            'طب الطوارئ النفسي',
            'طب الطوارئ الجراحي',
            'طب الطوارئ الداخلي',
          ],
        },
        '15': {
          'name': 'الطب النووي',
          'description': 'تخصص في استخدام المواد المشعة للتشخيص والعلاج',
          'subSpecialties': [
            'التصوير النووي',
            'العلاج الإشعاعي',
            'الطب النووي للقلب',
            'الطب النووي للعظام',
            'الطب النووي للأورام',
            'الطب النووي للأطفال',
            'الطب النووي للغدد',
            'الطب النووي للكلى',
          ],
        },
        '16': {
          'name': 'الطب الطبيعي والتأهيل',
          'description': 'تخصص في العلاج الطبيعي والتأهيل',
          'subSpecialties': [
            'العلاج الطبيعي للعظام',
            'العلاج الطبيعي للأعصاب',
            'العلاج الطبيعي للأطفال',
            'العلاج الطبيعي للقلب',
            'العلاج الطبيعي للجهاز التنفسي',
            'العلاج الوظيفي',
            'العلاج الطبيعي للرياضيين',
            'العلاج الطبيعي للمسنين',
          ],
        },
        '17': {
          'name': 'الطب المخبري',
          'description': 'تخصص في التحاليل الطبية والتشخيص المخبري',
          'subSpecialties': [
            'الكيمياء الحيوية',
            'علم الأحياء الدقيقة',
            'علم الدم',
            'علم المناعة',
            'علم الوراثة',
            'علم الأمراض',
            'علم الطفيليات',
            'علم الفيروسات',
          ],
        },
        '18': {
          'name': 'جراحة التجميل',
          'description': 'تخصص في جراحة التجميل والترميم',
          'subSpecialties': [
            'جراحة التجميل الترميمية',
            'جراحة التجميل التجميلية',
            'جراحة الحروق',
            'جراحة اليد التجميلية',
            'جراحة الوجه والفكين',
            'جراحة الثدي',
            'جراحة الجسم',
            'جراحة الليزر',
          ],
        },
        '19': {
          'name': 'جراحة المسالك البولية',
          'description': 'تخصص في تشخيص وعلاج أمراض المسالك البولية',
          'subSpecialties': [
            'جراحة الكلى',
            'جراحة المثانة',
            'جراحة البروستاتا',
            'جراحة المسالك البولية عند الأطفال',
            'جراحة المسالك البولية النسائية',
            'جراحة المسالك البولية بالمنظار',
            'جراحة العقم عند الرجال',
            'جراحة الأورام البولية',
          ],
        },
        '20': {
          'name': 'جراحة المخ والأعصاب',
          'description': 'تخصص في جراحة الجهاز العصبي',
          'subSpecialties': [
            'جراحة الأورام الدماغية',
            'جراحة الأوعية الدموية الدماغية',
            'جراحة العمود الفقري العصبية',
            'جراحة الأعصاب الطرفية',
            'جراحة الصرع',
            'جراحة الأطفال العصبية',
            'جراحة الحوادث العصبية',
            'جراحة الأورام الشوكية',
          ],
        },
        '21': {
          'name': 'أمراض الجهاز الهضمي',
          'description': 'تخصص في تشخيص وعلاج أمراض الجهاز الهضمي',
          'subSpecialties': [
            'أمراض الكبد',
            'أمراض البنكرياس',
            'أمراض المريء',
            'أمراض المعدة',
            'أمراض الأمعاء',
            'أمراض القولون',
            'أمراض المرارة',
            'مناظير الجهاز الهضمي',
          ],
        },
        '22': {
          'name': 'أمراض الكلى',
          'description': 'تخصص في تشخيص وعلاج أمراض الكلى',
          'subSpecialties': [
            'أمراض الكلى المزمنة',
            'أمراض الكلى الحادة',
            'زراعة الكلى',
            'غسيل الكلى',
            'أمراض الكلى عند الأطفال',
            'أمراض الكلى الوراثية',
            'أمراض الكلى المناعية',
            'ارتفاع ضغط الدم الكلوي',
          ],
        },
        '23': {
          'name': 'أمراض الغدد الصماء',
          'description': 'تخصص في تشخيص وعلاج أمراض الغدد الصماء',
          'subSpecialties': [
            'داء السكري',
            'أمراض الغدة الدرقية',
            'أمراض الغدة النخامية',
            'أمراض الغدة الكظرية',
            'أمراض الغدد التناسلية',
            'أمراض الغدد عند الأطفال',
            'أمراض التمثيل الغذائي',
            'أمراض السمنة',
          ],
        },
        '24': {
          'name': 'أمراض الروماتيزم',
          'description': 'تخصص في تشخيص وعلاج أمراض الروماتيزم',
          'subSpecialties': [
            'التهاب المفاصل الروماتويدي',
            'التهاب المفاصل التنكسي',
            'أمراض النسيج الضام',
            'أمراض العظام الأيضية',
            'أمراض الروماتيزم عند الأطفال',
            'أمراض الروماتيزم المناعية',
            'أمراض العضلات الروماتيزمية',
            'أمراض الأوعية الدموية الروماتيزمية',
          ],
        },
        '25': {
          'name': 'أمراض الدم',
          'description': 'تخصص في تشخيص وعلاج أمراض الدم',
          'subSpecialties': [
            'أمراض الدم الوراثية',
            'أمراض الدم المكتسبة',
            'أورام الدم',
            'أمراض النزيف',
            'أمراض التخثر',
            'أمراض الدم عند الأطفال',
            'زراعة النخاع العظمي',
            'أمراض الدم المناعية',
          ],
        },
        '26': {
          'name': 'أمراض الجهاز التنفسي',
          'description': 'تخصص في تشخيص وعلاج أمراض الجهاز التنفسي',
          'subSpecialties': [
            'أمراض الرئة المزمنة',
            'أمراض الرئة الحادة',
            'أمراض الصدر',
            'أمراض الجهاز التنفسي عند الأطفال',
            'أمراض النوم',
            'أمراض الحساسية',
            'أمراض الرئة المهنية',
            'أورام الرئة',
          ],
        },
        '27': {
          'name': 'جراحة القلب والصدر',
          'description': 'تخصص في جراحة القلب والصدر',
          'subSpecialties': [
            'جراحة القلب المفتوح',
            'جراحة القلب بالمنظار',
            'جراحة صمامات القلب',
            'جراحة الشرايين التاجية',
            'جراحة القلب عند الأطفال',
            'جراحة الصدر',
            'زراعة القلب',
            'جراحة الأوعية الدموية القلبية',
          ],
        },
        '28': {
          'name': 'أورام',
          'description': 'تخصص في تشخيص وعلاج الأورام',
          'subSpecialties': [
            'أورام الجهاز الهضمي',
            'أورام الثدي',
            'أورام الرئة',
            'أورام الدم',
            'أورام الأطفال',
            'أورام الجهاز التناسلي',
            'أورام الجهاز العصبي',
            'أورام العظام',
          ],
        },
        '29': {
          'name': 'طب الأسرة',
          'description': 'تخصص في الرعاية الصحية الشاملة للأسرة',
          'subSpecialties': [
            'طب الأسرة للبالغين',
            'طب الأسرة للأطفال',
            'طب الأسرة للمسنين',
            'طب الأسرة للنساء',
            'طب الأسرة للرجال',
            'طب الأسرة للرياضيين',
            'طب الأسرة المهني',
            'طب الأسرة النفسي',
          ],
        },
        '30': {
          'name': 'طب المسنين',
          'description': 'تخصص في رعاية وعلاج المسنين',
          'subSpecialties': [
            'أمراض المسنين العامة',
            'أمراض القلب عند المسنين',
            'أمراض الجهاز العصبي عند المسنين',
            'أمراض العظام عند المسنين',
            'أمراض الجهاز الهضمي عند المسنين',
            'أمراض الجهاز التنفسي عند المسنين',
            'أمراض المسنين النفسية',
            'رعاية المسنين',
          ],
        },
      };

      int addedCount = 0;
      int subSpecialtiesCount = 0;

      for (final entry in specialties.entries) {
        final specialtyId = entry.key;
        final specialtyData = entry.value;
        final specialtyName = specialtyData['name'] as String;
        final specialtyDescription = specialtyData['description'] as String;
        final subSpecialties = specialtyData['subSpecialties'] as List<String>;

        // التحقق من وجود التخصص
        final specialtyDoc = await FirebaseFirestore.instance
            .collection('medicalSpecialties')
            .doc(specialtyId)
            .get();

        if (!specialtyDoc.exists) {
          // إضافة التخصص الرئيسي
          await FirebaseFirestore.instance
              .collection('medicalSpecialties')
              .doc(specialtyId)
              .set({
            'id': int.tryParse(specialtyId) ?? specialtyId,
            'name': specialtyName,
            'description': specialtyDescription,
          });
          addedCount++;
        }

        // إضافة التخصصات الفرعية
        // أولاً: حذف جميع التخصصات الفرعية القديمة الخاطئة
        final existingSubSpecialties = await FirebaseFirestore.instance
            .collection('medicalSpecialties')
            .doc(specialtyId)
            .collection('subSpecialties')
            .get();
        
        // حذف التخصصات الفرعية القديمة
        for (var doc in existingSubSpecialties.docs) {
          await doc.reference.delete();
        }
        
        // إضافة التخصصات الفرعية الصحيحة
        for (int i = 0; i < subSpecialties.length; i++) {
          final subSpecialtyName = subSpecialties[i];
          final subSpecialtyId = '${specialtyId}_${i + 1}';

          await FirebaseFirestore.instance
              .collection('medicalSpecialties')
              .doc(specialtyId)
              .collection('subSpecialties')
              .doc(subSpecialtyId)
              .set({
            'id': subSpecialtyId,
            'name': subSpecialtyName,
          });
          subSpecialtiesCount++;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم إضافة $addedCount تخصص رئيسي و $subSpecialtiesCount تخصص فرعي بنجاح',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في إضافة التخصصات: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
}
