import 'package:cloud_firestore/cloud_firestore.dart';

class CentralDataService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // جلب جميع التخصصات الطبية من المجموعة المركزية
  static Future<List<Map<String, dynamic>>> getAllSpecialties() async {
    try {
      final snapshot = await _firestore
          .collection('medicalSpecialties')
          .get()
          .timeout(const Duration(seconds: 8));

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name'] ?? doc.id,
          'description': data['description'] ?? '',
        };
      }).toList();
    } catch (e) {
      print('خطأ في جلب التخصصات: $e');
      return [];
    }
  }

  // جلب جميع الأطباء من المجموعة المركزية
  static Future<List<Map<String, dynamic>>> getAllDoctors() async {
    try {
      final snapshot = await _firestore
          .collection('allDoctors')
          .get()
          .timeout(const Duration(seconds: 8));

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name'] ?? doc.id,
          'specialization': data['specialization'] ?? '',
          'phoneNumber': data['phoneNumber'] ?? '',
          'photoUrl': data['photoUrl'] ?? '',
        };
      }).toList();
    } catch (e) {
      print('خطأ في جلب الأطباء: $e');
      return [];
    }
  }

  // جلب جميع شركات التأمين من المجموعة المركزية
  static Future<List<Map<String, dynamic>>> getAllInsuranceCompanies() async {
    try {
      final snapshot = await _firestore
          .collection('insuranceCompanies')
          .get()
          .timeout(const Duration(seconds: 8));

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name'] ?? doc.id,
          'description': data['description'] ?? '',
          'phone': data['phone'] ?? '',
        };
      }).toList();
    } catch (e) {
      print('خطأ في جلب شركات التأمين: $e');
      return [];
    }
  }

  // إضافة تخصص إلى مركز معين (حفظ الـ ID فقط)
  static Future<void> addSpecialtyToCenter(String centerId, String specialtyId) async {
    try {
      // جلب بيانات التخصص من المجموعة المركزية
      final specialtyDoc = await _firestore
          .collection('medicalSpecialties')
          .doc(specialtyId)
          .get();

      if (specialtyDoc.exists) {
        final specialtyData = specialtyDoc.data()!;
        
        // إضافة التخصص إلى المركز مع حفظ الـ ID المرجعي
        await _firestore
            .collection('medicalFacilities')
            .doc(centerId)
            .collection('specializations')
            .doc(specialtyId)
            .set({
          'centralSpecialtyId': specialtyId,
          'specName': specialtyData['name'] ?? specialtyId,
          'description': specialtyData['description'] ?? '',
          'isActive': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print('خطأ في إضافة التخصص للمركز: $e');
      rethrow;
    }
  }

  // إضافة طبيب إلى مركز معين (حفظ الـ ID فقط)
  static Future<void> addDoctorToCenter(
    String centerId, 
    String specializationId, 
    String doctorId,
    Map<String, dynamic> additionalData,
  ) async {
    try {
      // جلب بيانات الطبيب من المجموعة المركزية
      final doctorDoc = await _firestore
          .collection('allDoctors')
          .doc(doctorId)
          .get();

      if (doctorDoc.exists) {
        final doctorData = doctorDoc.data()!;
        
        // إضافة الطبيب إلى المركز مع حفظ الـ ID المرجعي
        await _firestore
            .collection('medicalFacilities')
            .doc(centerId)
            .collection('specializations')
            .doc(specializationId)
            .collection('doctors')
            .doc(doctorId)
            .set({
          'centralDoctorId': doctorId,
          'docName': doctorData['name'] ?? doctorId,
          'phoneNumber': doctorData['phoneNumber'] ?? '',
          'photoUrl': doctorData['photoUrl'] ?? '',
          'specialization': doctorData['specialization'] ?? '',
          'morningPatientLimit': additionalData['morningPatientLimit'] ?? 20,
          'eveningPatientLimit': additionalData['eveningPatientLimit'] ?? 20,
          'isActive': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print('خطأ في إضافة الطبيب للمركز: $e');
      rethrow;
    }
  }

  // إضافة شركة تأمين إلى مركز معين (حفظ الـ ID فقط)
  static Future<void> addInsuranceCompanyToCenter(String centerId, String insuranceId) async {
    try {
      // جلب بيانات شركة التأمين من المجموعة المركزية
      final insuranceDoc = await _firestore
          .collection('insuranceCompanies')
          .doc(insuranceId)
          .get();

      if (insuranceDoc.exists) {
        final insuranceData = insuranceDoc.data()!;
        
        // إضافة شركة التأمين إلى المركز مع حفظ الـ ID المرجعي
        await _firestore
            .collection('medicalFacilities')
            .doc(centerId)
            .collection('insuranceCompanies')
            .doc(insuranceId)
            .set({
          'centralInsuranceId': insuranceId,
          'name': insuranceData['name'] ?? insuranceId,
          'description': insuranceData['description'] ?? '',
          'phone': insuranceData['phone'] ?? '',
          'isActive': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print('خطأ في إضافة شركة التأمين للمركز: $e');
      rethrow;
    }
  }

  // ===== دوال إضافة بيانات تجريبية =====

  // إضافة تخصصات تجريبية
  static Future<void> addSampleSpecialties() async {
    try {
      final specialties = [
        {
          'id': 'cardiology',
          'name': 'أمراض القلب',
          'description': 'تخصص في تشخيص وعلاج أمراض القلب والأوعية الدموية',
        },
        {
          'id': 'neurology',
          'name': 'أمراض الأعصاب',
          'description': 'تخصص في تشخيص وعلاج أمراض الجهاز العصبي',
        },
        {
          'id': 'orthopedics',
          'name': 'جراحة العظام',
          'description': 'تخصص في تشخيص وعلاج أمراض العظام والمفاصل',
        },
        {
          'id': 'dermatology',
          'name': 'أمراض الجلد',
          'description': 'تخصص في تشخيص وعلاج أمراض الجلد',
        },
        {
          'id': 'pediatrics',
          'name': 'طب الأطفال',
          'description': 'تخصص في رعاية وعلاج الأطفال',
        },
      ];

      for (final specialty in specialties) {
        await _firestore
            .collection('medicalSpecialties')
            .doc(specialty['id'])
            .set(specialty);
      }

      print('تم إضافة التخصصات التجريبية بنجاح');
    } catch (e) {
      print('خطأ في إضافة التخصصات التجريبية: $e');
    }
  }

  // إضافة أطباء تجريبيين
  static Future<void> addSampleDoctors() async {
    try {
      final doctors = [
        {
          'id': 'dr_ahmed_ali',
          'name': 'د. أحمد علي',
          'specialization': 'cardiology',
          'phoneNumber': '+249123456789',
          'photoUrl': 'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQupVHd_oeqnkds0k3EjT1SX4ctwwblwYP2Uw&s',
        },
        {
          'id': 'dr_fatima_mohammed',
          'name': 'د. فاطمة محمد',
          'specialization': 'neurology',
          'phoneNumber': '+249123456790',
          'photoUrl': 'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQupVHd_oeqnkds0k3EjT1SX4ctwwblwYP2Uw&s',
        },
        {
          'id': 'dr_omar_hassan',
          'name': 'د. عمر حسن',
          'specialization': 'orthopedics',
          'phoneNumber': '+249123456791',
          'photoUrl': 'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQupVHd_oeqnkds0k3EjT1SX4ctwwblwYP2Uw&s',
        },
        {
          'id': 'dr_sara_ahmed',
          'name': 'د. سارة أحمد',
          'specialization': 'dermatology',
          'phoneNumber': '+249123456792',
          'photoUrl': 'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQupVHd_oeqnkds0k3EjT1SX4ctwwblwYP2Uw&s',
        },
        {
          'id': 'dr_khalid_omar',
          'name': 'د. خالد عمر',
          'specialization': 'pediatrics',
          'phoneNumber': '+249123456793',
          'photoUrl': 'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQupVHd_oeqnkds0k3EjT1SX4ctwwblwYP2Uw&s',
        },
      ];

      for (final doctor in doctors) {
        await _firestore
            .collection('allDoctors')
            .doc(doctor['id'])
            .set(doctor);
      }

      print('تم إضافة الأطباء التجريبيين بنجاح');
    } catch (e) {
      print('خطأ في إضافة الأطباء التجريبيين: $e');
    }
  }

  // إضافة شركات تأمين تجريبية
  static Future<void> addSampleInsuranceCompanies() async {
    try {
      final companies = [
        {
          'id': 'blue_cross',
          'name': 'بلو كروس',
          'description': 'شركة تأمين صحي رائدة في السودان',
          'phone': '+249123456794',
        },
        {
          'id': 'sudan_insurance',
          'name': 'شركة التأمين السودانية',
          'description': 'شركة تأمين وطنية شاملة',
          'phone': '+249123456795',
        },
        {
          'id': 'medical_insurance',
          'name': 'تأمين طبي',
          'description': 'تأمين صحي متخصص',
          'phone': '+249123456796',
        },
        {
          'id': 'health_care',
          'name': 'رعاية صحية',
          'description': 'شركة تأمين صحي حديثة',
          'phone': '+249123456797',
        },
      ];

      for (final company in companies) {
        await _firestore
            .collection('insuranceCompanies')
            .doc(company['id'])
            .set(company);
      }

      print('تم إضافة شركات التأمين التجريبية بنجاح');
    } catch (e) {
      print('خطأ في إضافة شركات التأمين التجريبية: $e');
    }
  }

  // إضافة جميع البيانات التجريبية
  static Future<void> addAllSampleData() async {
    try {
      await addSampleSpecialties();
      await addSampleDoctors();
      await addSampleInsuranceCompanies();
      print('تم إضافة جميع البيانات التجريبية بنجاح');
    } catch (e) {
      print('خطأ في إضافة البيانات التجريبية: $e');
    }
  }

  // فحص البيانات الموجودة
  static Future<void> checkExistingData() async {
    try {
      print('=== فحص البيانات الموجودة ===');
      
      // فحص التخصصات
      final specialtiesSnapshot = await _firestore.collection('medicalSpecialties').get();
      print('عدد التخصصات الموجودة: ${specialtiesSnapshot.docs.length}');
      for (final doc in specialtiesSnapshot.docs) {
        print('- ${doc.id}: ${(doc.data()['name'] as String?) ?? 'بدون اسم'}');
      }
      
      // فحص الأطباء
      final doctorsSnapshot = await _firestore.collection('allDoctors').get();
      print('عدد الأطباء الموجودين: ${doctorsSnapshot.docs.length}');
      for (final doc in doctorsSnapshot.docs) {
        print('- ${doc.id}: ${(doc.data()['name'] as String?) ?? 'بدون اسم'}');
      }
      
      // فحص شركات التأمين
      final insuranceSnapshot = await _firestore.collection('insuranceCompanies').get();
      print('عدد شركات التأمين الموجودة: ${insuranceSnapshot.docs.length}');
      for (final doc in insuranceSnapshot.docs) {
        print('- ${doc.id}: ${doc.data()['name'] ?? 'بدون اسم'}');
      }
      
    } catch (e) {
      print('خطأ في فحص البيانات: $e');
    }
  }
}
