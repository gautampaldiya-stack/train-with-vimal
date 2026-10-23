// Web push (D-56): shows notifications while the app tab is closed. Firebase keys come from
// firebase-config.js, made from app/firebase.json by `dart run tool/firebase_web.dart` (not in git).
try { importScripts('/firebase-config.js'); } catch (e) {}
if (self.TWV_FIREBASE) {
  importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
  importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');
  firebase.initializeApp(self.TWV_FIREBASE);
  firebase.messaging();
}
// Tapping a notification opens its page (data.route) in the app.
self.addEventListener('notificationclick', (event) => {
  const data = (event.notification.data && (event.notification.data.FCM_MSG || {}).data) || {};
  const url = data.route && data.route.startsWith('/') ? data.route : '/';
  event.notification.close();
  event.waitUntil(clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
    for (const c of list) { if ('focus' in c) { c.navigate(url); return c.focus(); } }
    return clients.openWindow(url);
  }));
});
