// Web push (D-56): shows notifications while the app tab is closed. Firebase keys come from
// firebase-config.js, made from app/firebase.json by `dart run tool/firebase_web.dart` (not in git).

// Tapping a notification opens its page (data.route) in the app (D-80). This listener is added before Firebase's
// own one, which would stop it: an open app tab is focused and told the route (Push listens for `twvRoute`),
// otherwise a new tab opens on that page.
self.addEventListener('notificationclick', (event) => {
  const msg = (event.notification.data && event.notification.data.FCM_MSG) || null;
  const data = (msg && msg.data) || (event.notification.data || {});
  const route = typeof data.route === 'string' && data.route.startsWith('/') ? data.route : '/';
  event.stopImmediatePropagation();
  event.notification.close();
  event.waitUntil(clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
    const mine = list.filter((c) => new URL(c.url).origin === self.location.origin);
    if (mine.length) {
      const c = mine.find((x) => x.focused) || mine[0];
      c.postMessage({ twvRoute: route });
      return c.focus();
    }
    return clients.openWindow(route);
  }));
});

try { importScripts('/firebase-config.js'); } catch (e) {}
if (self.TWV_FIREBASE) {
  importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
  importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');
  firebase.initializeApp(self.TWV_FIREBASE);
  firebase.messaging();
}
