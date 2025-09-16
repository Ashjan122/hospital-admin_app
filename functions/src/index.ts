import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

admin.initializeApp();

export const notifyNewAppointment = functions.firestore
  .document('medicalFacilities/{centerId}/specializations/{specId}/doctors/{doctorId}/appointments/{appointmentId}')
  .onCreate(async (snap, context) => {
    const data = snap.data() as any || {};

    const createdByType = String(data.createdByType || '');
    const createdBy = String(data.createdBy || '');
    if (createdByType === 'reception' || createdBy === 'reception') {
      return null; // لا ترسل إشعاراً لحجوزات موظف الاستقبال
    }

    const doctorId = context.params.doctorId as string;
    const centerId = context.params.centerId as string;
    const specId = context.params.specId as string;
    const topic = `doctor_${doctorId}`;

    const patientName = data.patientName || 'مريض';
    const date = data.date || '';
    const time = data.time || '';

    // جلب اسم الدكتور لإظهاره في عنوان الإشعار
    let doctorName: string = String(data.doctorName || '');
    try {
      if (!doctorName) {
        const doctorSnap = await admin
          .firestore()
          .doc(`medicalFacilities/${centerId}/specializations/${specId}/doctors/${doctorId}`)
          .get();
        const doctorData = doctorSnap.data() as any || {};
        doctorName = String(doctorData.docName || doctorData.doctorName || '');
      }
    } catch (e) {
      console.error('Error fetching doctor name for notification:', e);
    }

    const message: admin.messaging.Message = {
      notification: {
        title: doctorName ? `حجز جديد لدى د. ${doctorName}` : 'حجز جديد',
        body: `المريض ${patientName} - ${date} ${time}`,
      },
      data: {
        type: 'new_appointment',
        doctorId,
        appointmentId: context.params.appointmentId,
        date,
        time,
        doctorName,
      },
      topic,
    };

    try {
      await admin.messaging().send(message);
      return null;
    } catch (e) {
      console.error('Error sending FCM:', e);
      return null;
    }
  });


