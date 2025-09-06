import 'package:cloud_firestore/cloud_firestore.dart';

class FavoriteDoctorsService {
  static const String _collectionName = 'users';

  /// حفظ الأطباء المفضلين لموظف استقبال معين
  static Future<bool> saveFavoriteDoctors({
    required String userId,
    required String centerId,
    required List<String> doctorIds,
  }) async {
    try {
      print('=== SAVING FAVORITE DOCTORS ===');
      print('User ID: $userId');
      print('Center ID: $centerId');
      print('Doctors to save: $doctorIds');
      print('Number of doctors: ${doctorIds.length}');
      print('Document ID: $userId');

      // تحديث وثيقة المستخدم الموجودة في مجموعة users
      final docRef = FirebaseFirestore.instance
          .collection(_collectionName)
          .doc(userId);
      
      final updateData = {
        'favoriteDoctors': doctorIds,
        'lastUpdated': FieldValue.serverTimestamp(),
        'totalFavoriteDoctors': doctorIds.length,
      };

      print('Updating user document with: $updateData');
      
      // استخدام set مع merge: true لضمان إضافة الحقول الجديدة
      await docRef.set(updateData, SetOptions(merge: true));

      // التحقق من أن البيانات تم تحديثها
      final updatedDoc = await docRef.get();
      if (updatedDoc.exists) {
        final updatedData = updatedDoc.data()!;
        print('✅ User document updated successfully!');
        print('Updated document ID: ${updatedDoc.id}');
        print('Updated favoriteDoctors: ${updatedData['favoriteDoctors']}');
        print('Updated totalFavoriteDoctors: ${updatedData['totalFavoriteDoctors']}');
        print('Updated lastUpdated: ${updatedData['lastUpdated']}');
        
        // التحقق من صحة البيانات المحفوظة
        final savedDoctors = List<String>.from(updatedData['favoriteDoctors'] ?? []);
        final savedCount = updatedData['totalFavoriteDoctors'] ?? 0;
        
        print('🔍 Verification:');
        print('- Saved doctors: $savedDoctors');
        print('- Saved count: $savedCount');
        print('- Original doctors: $doctorIds');
        print('- Original count: ${doctorIds.length}');
        print('- Count match: ${savedCount == doctorIds.length}');
        print('- Data match: ${savedDoctors.length == doctorIds.length && savedDoctors.every((id) => doctorIds.contains(id))}');
        
        if (savedCount != doctorIds.length) {
          print('⚠️ WARNING: Count mismatch after save!');
          print('Expected: ${doctorIds.length}, Saved: $savedCount');
        }
        
        if (savedDoctors.length != doctorIds.length) {
          print('⚠️ WARNING: Data length mismatch after save!');
          print('Expected: ${doctorIds.length}, Saved: ${savedDoctors.length}');
        }
      } else {
        print('❌ User document was not found!');
      }

      print('=== SAVE COMPLETED ===');
      return true;
    } catch (e) {
      print('❌ Error saving favorite doctors: $e');
      print('Error details: ${e.toString()}');
      return false;
    }
  }

  /// جلب الأطباء المفضلين لموظف استقبال معين
  static Future<List<String>> getFavoriteDoctors({
    required String userId,
    required String centerId,
  }) async {
    try {
      print('=== LOADING FAVORITE DOCTORS ===');
      print('User ID: $userId');
      print('Center ID: $centerId');
      print('Document ID: $userId');

      final doc = await FirebaseFirestore.instance
          .collection(_collectionName)
          .doc(userId)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        print('✅ User document found!');
        print('Document ID: ${doc.id}');
        print('Document data: $data');
        
        final favoriteDoctors = List<String>.from(data['favoriteDoctors'] ?? []);
        final totalFavoriteDoctors = data['totalFavoriteDoctors'] ?? 0;
        final lastUpdated = data['lastUpdated'];
        
        print('📊 Data Summary:');
        print('- User ID: ${data['userId'] ?? doc.id}');
        print('- Center ID: ${data['centerId']}');
        print('- User Type: ${data['userType']}');
        print('- Favorite Doctors: $favoriteDoctors');
        print('- Total Favorite Doctors: $totalFavoriteDoctors');
        print('- Last Updated: $lastUpdated');
        print('- Actual Count: ${favoriteDoctors.length}');
        
        if (favoriteDoctors.length != totalFavoriteDoctors) {
          print('⚠️ WARNING: Count mismatch! Expected: $totalFavoriteDoctors, Actual: ${favoriteDoctors.length}');
        }
        
        print('=== LOAD COMPLETED ===');
        return favoriteDoctors;
      } else {
        print('❌ No user document found for user: $userId');
        print('Document path: ${_collectionName}/$userId');
        print('=== LOAD COMPLETED (EMPTY) ===');
        return [];
      }
    } catch (e) {
      print('❌ Error loading favorite doctors: $e');
      print('Error details: ${e.toString()}');
      print('=== LOAD FAILED ===');
      return [];
    }
  }

  /// إضافة طبيب إلى المفضلين
  static Future<bool> addFavoriteDoctor({
    required String userId,
    required String centerId,
    required String doctorId,
  }) async {
    try {
      print('=== ADDING FAVORITE DOCTOR ===');
      print('User ID: $userId');
      print('Center ID: $centerId');
      print('Doctor ID to add: $doctorId');

      final currentFavorites = await getFavoriteDoctors(
        userId: userId,
        centerId: centerId,
      );

      print('Current favorites: $currentFavorites');
      print('Current count: ${currentFavorites.length}');

      if (!currentFavorites.contains(doctorId)) {
        currentFavorites.add(doctorId);
        print('Added doctor $doctorId to favorites');
        print('New favorites: $currentFavorites');
        print('New count: ${currentFavorites.length}');
        
        return await saveFavoriteDoctors(
          userId: userId,
          centerId: centerId,
          doctorIds: currentFavorites,
        );
      } else {
        print('Doctor $doctorId already exists in favorites');
        return true; // الطبيب موجود بالفعل
      }
    } catch (e) {
      print('❌ Error adding favorite doctor: $e');
      return false;
    }
  }

  /// إزالة طبيب من المفضلين
  static Future<bool> removeFavoriteDoctor({
    required String userId,
    required String centerId,
    required String doctorId,
  }) async {
    try {
      final currentFavorites = await getFavoriteDoctors(
        userId: userId,
        centerId: centerId,
      );

      currentFavorites.remove(doctorId);
      return await saveFavoriteDoctors(
        userId: userId,
        centerId: centerId,
        doctorIds: currentFavorites,
      );
    } catch (e) {
      print('Error removing favorite doctor: $e');
      return false;
    }
  }

  /// التحقق من وجود طبيب في المفضلين
  static Future<bool> isFavoriteDoctor({
    required String userId,
    required String centerId,
    required String doctorId,
  }) async {
    try {
      final favorites = await getFavoriteDoctors(
        userId: userId,
        centerId: centerId,
      );
      return favorites.contains(doctorId);
    } catch (e) {
      print('Error checking if doctor is favorite: $e');
      return false;
    }
  }

  /// حذف جميع الأطباء المفضلين لموظف معين
  static Future<bool> clearAllFavorites({
    required String userId,
    required String centerId,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection(_collectionName)
          .doc('${userId}_$centerId')
          .delete();

      print('All favorite doctors cleared for user: $userId');
      return true;
    } catch (e) {
      print('Error clearing favorite doctors: $e');
      return false;
    }
  }

  /// جلب إحصائيات الأطباء المفضلين
  static Future<Map<String, dynamic>> getFavoritesStats({
    required String centerId,
  }) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(_collectionName)
          .where('centerId', isEqualTo: centerId)
          .get();

      int totalUsers = snapshot.docs.length;
      int totalFavorites = 0;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final doctorIds = List<String>.from(data['doctorIds'] ?? []);
        totalFavorites += doctorIds.length;
      }

      return {
        'totalUsers': totalUsers,
        'totalFavorites': totalFavorites,
        'averageFavorites': totalUsers > 0 ? totalFavorites / totalUsers : 0,
      };
    } catch (e) {
      print('Error getting favorites stats: $e');
      return {
        'totalUsers': 0,
        'totalFavorites': 0,
        'averageFavorites': 0,
      };
    }
  }

  /// دالة جديدة: اختبار حفظ البيانات مباشرة
  static Future<bool> testSaveFavoriteDoctors({
    required String userId,
    required String centerId,
    required List<String> testDoctorIds,
  }) async {
    try {
      print('=== TESTING SAVE FAVORITE DOCTORS ===');
      print('User ID: $userId');
      print('Center ID: $centerId');
      print('Test doctors: $testDoctorIds');
      print('Test count: ${testDoctorIds.length}');
      
      // حفظ البيانات التجريبية
      final success = await saveFavoriteDoctors(
        userId: userId,
        centerId: centerId,
        doctorIds: testDoctorIds,
      );
      
      if (success) {
        print('✅ Test save successful!');
        
        // التحقق من البيانات المحفوظة
        final savedDoctors = await getFavoriteDoctors(
          userId: userId,
          centerId: centerId,
        );
        
        print('🔍 Test verification:');
        print('- Expected: $testDoctorIds');
        print('- Saved: $savedDoctors');
        print('- Expected count: ${testDoctorIds.length}');
        print('- Saved count: ${savedDoctors.length}');
        print('- Match: ${savedDoctors.length == testDoctorIds.length}');
        
        return savedDoctors.length == testDoctorIds.length;
      } else {
        print('❌ Test save failed!');
        return false;
      }
    } catch (e) {
      print('❌ Error in test save: $e');
      return false;
    }
  }

  /// دالة جديدة: التحقق من حالة البيانات في قاعدة البيانات
  static Future<Map<String, dynamic>> checkDatabaseStatus({
    required String userId,
    required String centerId,
  }) async {
    try {
      print('=== CHECKING DATABASE STATUS ===');
      print('User ID: $userId');
      print('Center ID: $centerId');
      
      // التحقق من وجود وثيقة المستخدم
      final doc = await FirebaseFirestore.instance
          .collection(_collectionName)
          .doc(userId)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        print('✅ User document exists in database');
        print('Document ID: ${doc.id}');
        print('Document data: $data');
        
        // التحقق من صحة البيانات
        final favoriteDoctors = List<String>.from(data['favoriteDoctors'] ?? []);
        final savedUserId = data['userId'] ?? doc.id;
        final savedCenterId = data['centerId'];
        final lastUpdated = data['lastUpdated'];
        final totalFavoriteDoctors = data['totalFavoriteDoctors'] ?? 0;
        final userType = data['userType'];
        
        final isValid = savedUserId == userId && 
                       savedCenterId == centerId && 
                       userType == 'reception';
        
        print('📊 Data Validation:');
        print('- User ID match: ${savedUserId == userId}');
        print('- Center ID match: ${savedCenterId == centerId}');
        print('- User Type: $userType');
        print('- Has favorite doctors: ${favoriteDoctors.isNotEmpty}');
        print('- Expected count: $totalFavoriteDoctors');
        print('- Actual count: ${favoriteDoctors.length}');
        
        return {
          'exists': true,
          'isValid': isValid,
          'documentId': doc.id,
          'userId': savedUserId,
          'centerId': savedCenterId,
          'userType': userType,
          'favoriteDoctors': favoriteDoctors,
          'totalFavoriteDoctors': totalFavoriteDoctors,
          'actualCount': favoriteDoctors.length,
          'lastUpdated': lastUpdated,
          'dataIntegrity': {
            'userIdMatch': savedUserId == userId,
            'centerIdMatch': savedCenterId == centerId,
            'userTypeMatch': userType == 'reception',
            'hasDoctors': favoriteDoctors.isNotEmpty,
            'countMatch': totalFavoriteDoctors == favoriteDoctors.length,
          }
        };
      } else {
        print('❌ User document does not exist in database');
        return {
          'exists': false,
          'isValid': false,
          'documentId': userId,
          'error': 'User document not found'
        };
      }
    } catch (e) {
      print('❌ Error checking database status: $e');
      return {
        'exists': false,
        'isValid': false,
        'error': e.toString()
      };
    }
  }
}
