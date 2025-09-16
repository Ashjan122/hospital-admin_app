"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.notifyNewAppointment = void 0;
const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();
exports.notifyNewAppointment = functions.firestore
    .document('medicalFacilities/{centerId}/specializations/{specId}/doctors/{doctorId}/appointments/{appointmentId}')
    .onCreate(async (snap, context) => {
    const data = snap.data() || {};
    const createdByType = String(data.createdByType || '');
    const createdBy = String(data.createdBy || '');
    if (createdByType === 'reception' || createdBy === 'reception') {
        return null; // لا ترسل إشعاراً لحجوزات موظف الاستقبال
    }
    const doctorId = context.params.doctorId;
    const centerId = context.params.centerId;
    const specId = context.params.specId;
    const topic = `doctor_${doctorId}`;
    const patientName = data.patientName || 'مريض';
    const date = data.date || '';
    const time = data.time || '';
    // جلب اسم الدكتور لإظهاره في عنوان الإشعار
    let doctorName = String(data.doctorName || '');
    try {
        if (!doctorName) {
            const doctorSnap = await admin
                .firestore()
                .doc(`medicalFacilities/${centerId}/specializations/${specId}/doctors/${doctorId}`)
                .get();
            const doctorData = doctorSnap.data() || {};
            doctorName = String(doctorData.docName || doctorData.doctorName || '');
        }
    }
    catch (e) {
        console.error('Error fetching doctor name for notification:', e);
    }
    const message = {
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
    }
    catch (e) {
        console.error('Error sending FCM:', e);
        return null;
    }
});
//# sourceMappingURL=index.js.map