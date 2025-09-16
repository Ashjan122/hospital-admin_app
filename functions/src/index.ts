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

    // Helpers to format date/time in Arabic
    const toTwo = (n: number) => (n < 10 ? `0${n}` : `${n}`);
    const parseDateTime = (dateStr: string, timeStr: string): Date | null => {
      try {
        if (!dateStr && !timeStr) return null;
        if (dateStr && timeStr) {
          // Normalize to ISO if possible
          const dt = new Date(`${dateStr}T${timeStr}`);
          if (!isNaN(dt.getTime())) return dt;
        }
        if (dateStr) {
          const d = new Date(dateStr);
          if (!isNaN(d.getTime())) return d;
        }
        if (timeStr) {
          const now = new Date();
          const parts = timeStr.split(':');
          const h = parseInt(parts[0] || '0', 10);
          const m = parseInt(parts[1] || '0', 10);
          const t = new Date(now.getFullYear(), now.getMonth(), now.getDate(), h, m, 0);
          if (!isNaN(t.getTime())) return t;
        }
        return null;
      } catch {
        return null;
      }
    };

    const formatRelativeDay = (d: Date | null): string => {
      if (!d) return '';
      const now = new Date();
      const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
      const target = new Date(d.getFullYear(), d.getMonth(), d.getDate());
      const diffDays = Math.round((+target - +today) / (24 * 60 * 60 * 1000));
      if (diffDays === 0) return 'اليوم';
      if (diffDays === 1) return 'غداً';
      // Day name in Arabic
      const days = ['الأحد','الاثنين','الثلاثاء','الأربعاء','الخميس','الجمعة','السبت'];
      return days[target.getDay()];
    };

    const formatDate = (d: Date | null): string => {
      if (!d) return String(date || '');
      return `${d.getFullYear()}/${toTwo(d.getMonth() + 1)}/${toTwo(d.getDate())}`;
    };

    const formatTime = (d: Date | null, timeStr: string): { time: string; period: string } => {
      if (d) {
        const hour = d.getHours();
        const minute = d.getMinutes();
        const period = hour < 12 ? 'صباحاً' : 'مساءً';
        return { time: `${toTwo(hour)}:${toTwo(minute)}`, period };
      }
      // fallback to timeStr
      const parts = (timeStr || '').split(':');
      const h = parseInt(parts[0] || '0', 10);
      const m = parseInt(parts[1] || '0', 10);
      const period = h < 12 ? 'صباحاً' : 'مساءً';
      return { time: `${toTwo(h)}:${toTwo(m)}`, period };
    };

    const dt = parseDateTime(date, time);
    const relative = formatRelativeDay(dt);
    const dateOut = formatDate(dt);
    const { time: timeOut, period } = formatTime(dt, time);

    const message: admin.messaging.Message = {
      notification: {
        title: doctorName ? `حجز جديد لدى د. ${doctorName}` : 'حجز جديد',
        body: `المريض ${patientName} - ${relative ? relative + ' - ' : ''}${dateOut} - ${timeOut} (${period})`,
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


