"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.sendTomorrowReminders = exports.notifyNewHomeClinicRequest = exports.notifyNewPatientSignup = exports.notifyNewAppointment = void 0;
const functions = require("firebase-functions");
const admin = require("firebase-admin");
const https = require("https");
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
    // Helpers to format date/time in Arabic
    const toTwo = (n) => (n < 10 ? `0${n}` : `${n}`);
    const parseDateTime = (dateStr, timeStr) => {
        try {
            if (!dateStr && !timeStr)
                return null;
            if (dateStr && timeStr) {
                // Normalize to ISO if possible
                const dt = new Date(`${dateStr}T${timeStr}`);
                if (!isNaN(dt.getTime()))
                    return dt;
            }
            if (dateStr) {
                const d = new Date(dateStr);
                if (!isNaN(d.getTime()))
                    return d;
            }
            if (timeStr) {
                const now = new Date();
                const parts = timeStr.split(':');
                const h = parseInt(parts[0] || '0', 10);
                const m = parseInt(parts[1] || '0', 10);
                const t = new Date(now.getFullYear(), now.getMonth(), now.getDate(), h, m, 0);
                if (!isNaN(t.getTime()))
                    return t;
            }
            return null;
        }
        catch {
            return null;
        }
    };
    const formatRelativeDay = (d) => {
        if (!d)
            return '';
        const now = new Date();
        const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        const target = new Date(d.getFullYear(), d.getMonth(), d.getDate());
        const diffDays = Math.round((+target - +today) / (24 * 60 * 60 * 1000));
        if (diffDays === 0)
            return 'اليوم';
        if (diffDays === 1)
            return 'غداً';
        // Day name in Arabic
        const days = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
        return days[target.getDay()];
    };
    const formatDate = (d) => {
        if (!d)
            return String(date || '');
        return `${d.getFullYear()}/${toTwo(d.getMonth() + 1)}/${toTwo(d.getDate())}`;
    };
    const formatTime = (d, timeStr) => {
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
    const message = {
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
    }
    catch (e) {
        console.error('Error sending FCM:', e);
        return null;
    }
});
// Scheduled function: send reminders 24h before scheduled appointments
// Notification for new patient signup
exports.notifyNewPatientSignup = functions.firestore
    .document('patients/{patientId}')
    .onCreate(async (snap, context) => {
    const data = snap.data() || {};
    const patientName = data.name || 'مريض جديد';
    const patientPhone = data.phone || 'غير محدد';
    const message = {
        notification: {
            title: 'تم إنشاء حساب جديد',
            body: `الاسم: ${patientName} - الهاتف: ${patientPhone}`,
        },
        data: {
            type: 'new_patient_signup',
            patientId: context.params.patientId,
            patientName,
            patientPhone,
            timestamp: new Date().toISOString(),
        },
        topic: 'new_signup',
    };
    try {
        await admin.messaging().send(message);
        console.log('New patient signup notification sent successfully');
        return null;
    }
    catch (e) {
        console.error('Error sending new patient signup notification:', e);
        return null;
    }
});
// Notification for new home clinic request
exports.notifyNewHomeClinicRequest = functions.firestore
    .document('homeSampleRequests/{requestId}')
    .onCreate(async (snap, context) => {
    const data = snap.data() || {};
    const patientName = data.patientName || data.name || 'مريض جديد';
    const patientPhone = data.patientPhone || data.phone || 'غير محدد';
    const serviceType = data.serviceType || data.service || 'خدمة طبية';
    const centerName = data.centerName || data.center || 'مركز طبي';
    const message = {
        notification: {
            title: 'طلب جديد للعيادة المنزلية',
            body: `الاسم: ${patientName} - الهاتف: ${patientPhone} - النوع: ${serviceType} - المركز: ${centerName}`,
        },
        data: {
            type: 'new_home_clinic_request',
            requestId: context.params.requestId,
            patientName,
            patientPhone,
            serviceType,
            centerName,
            timestamp: new Date().toISOString(),
        },
        topic: 'home_clinic_requests',
    };
    try {
        await admin.messaging().send(message);
        console.log('New home clinic request notification sent successfully');
        return null;
    }
    catch (e) {
        console.error('Error sending new home clinic request notification:', e);
        return null;
    }
});
exports.sendTomorrowReminders = functions.pubsub
    .schedule('0 8 * * *') // daily at 08:00
    .timeZone('Africa/Khartoum')
    .onRun(async () => {
    const db = admin.firestore();
    // Compute tomorrow (Riyadh timezone assumed by schedule). We compare by date only.
    const now = new Date();
    const tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
    const tomorrowY = tomorrow.getFullYear();
    const tomorrowM = tomorrow.getMonth();
    const tomorrowD = tomorrow.getDate();
    try {
        // Query all scheduled appointments where reminder not yet sent
        const snap = await db
            .collectionGroup('scheduledAppointments')
            .where('status', '==', 'scheduled')
            .where('reminderSent', '==', false)
            .get();
        if (snap.empty) {
            console.log('No scheduled appointments pending reminders.');
            return null;
        }
        console.log(`Found ${snap.size} scheduled appointments to evaluate`);
        const results = [];
        for (const doc of snap.docs) {
            const data = doc.data();
            const appointmentDateStr = String(data.appointmentDate || '');
            const patientPhone = String(data.patientPhone || '');
            const doctorName = String(data.doctorName || '');
            // Parse appointment date regardless of timezone in ISO string
            let appointmentDate = null;
            try {
                if (appointmentDateStr) {
                    const d = new Date(appointmentDateStr);
                    if (!isNaN(d.getTime()))
                        appointmentDate = d;
                }
            }
            catch { }
            if (!appointmentDate) {
                results.push({ id: doc.id, sent: false, reason: 'Invalid appointmentDate' });
                continue;
            }
            const isTomorrow = appointmentDate.getFullYear() === tomorrowY &&
                appointmentDate.getMonth() === tomorrowM &&
                appointmentDate.getDate() === tomorrowD;
            if (!isTomorrow) {
                results.push({ id: doc.id, sent: false, reason: 'Not tomorrow' });
                continue;
            }
            if (!patientPhone) {
                results.push({ id: doc.id, sent: false, reason: 'Missing patientPhone' });
                continue;
            }
            const messageBody = `لديك موعد مع د. ${doctorName} غداً يرجى الحجز`;
            try {
                // Send WhatsApp reminder via UltraMsg
                await sendWhatsAppUsingUltraMsg(patientPhone, messageBody);
                // Optionally: Integrate SMS provider here if needed
                await doc.ref.update({
                    reminderSent: true,
                    reminderSentAt: admin.firestore.FieldValue.serverTimestamp(),
                });
                results.push({ id: doc.id, sent: true });
            }
            catch (e) {
                console.error('Failed sending reminder for', doc.ref.path, e);
                results.push({ id: doc.id, sent: false, reason: String(e?.message || e) });
            }
        }
        const sentCount = results.filter(r => r.sent).length;
        console.log(`Reminders processed. Sent: ${sentCount}/${results.length}`);
        return null;
    }
    catch (e) {
        console.error('sendTomorrowReminders failed', e);
        return null;
    }
});
function sendWhatsAppUsingUltraMsg(to, body) {
    return new Promise((resolve, reject) => {
        const cfg = functions.config() || {};
        const instance = cfg.ultramsg?.instance || process.env.ULTRAMSG_INSTANCE;
        const token = cfg.ultramsg?.token || process.env.ULTRAMSG_TOKEN;
        if (!instance || !token) {
            return reject(new Error('UltraMsg config missing (ultramsg.instance/token)'));
        }
        const url = new URL(`https://api.ultramsg.com/${instance}/messages/chat`);
        const postData = new URLSearchParams({ token, to, body }).toString();
        const req = https.request(url, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'Content-Length': Buffer.byteLength(postData).toString(),
            },
        }, (res) => {
            let data = '';
            res.on('data', (chunk) => (data += chunk));
            res.on('end', () => {
                if (res.statusCode && res.statusCode >= 200 && res.statusCode < 300) {
                    resolve();
                }
                else {
                    reject(new Error(`UltraMsg HTTP ${res.statusCode}: ${data}`));
                }
            });
        });
        req.on('error', (err) => reject(err));
        req.write(postData);
        req.end();
    });
}
//# sourceMappingURL=index.js.map