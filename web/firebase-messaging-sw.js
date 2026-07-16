// Background push handler for Nyumba on the web.
//
// Required by firebase_messaging: without a service worker at this exact path,
// getToken() cannot subscribe and web push silently never works.
//
// The Firebase config is read from the registration URL rather than hard-coded.
// firebase_messaging_web registers this worker as
// `firebase-messaging-sw.js?firebaseConfig=<json>`, using the same options the
// app booted with. That keeps project identifiers out of the repository (see
// AGENTS.md) and — more usefully — makes it impossible for this file to drift
// out of sync with the environment the app is actually pointed at.
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

const params = new URL(self.location).searchParams;
const rawConfig = params.get('firebaseConfig');

if (!rawConfig) {
  // Registered without config: nothing here can work, and pretending otherwise
  // would surface as an opaque getToken() failure much later.
  console.error('[nyumba] firebase-messaging-sw.js registered without firebaseConfig.');
} else {
  firebase.initializeApp(JSON.parse(rawConfig));
  const messaging = firebase.messaging();

  // Notifications carrying a `notification` block are displayed by the browser
  // automatically; this handler exists for data-only messages, and to attach
  // the deep link the app reads on click.
  messaging.onBackgroundMessage((payload) => {
    const data = payload.data || {};
    if (payload.notification) return;
    if (!data.title) return;
    self.registration.showNotification(data.title, {
      body: data.body || '',
      icon: '/icons/Icon-192.png',
      data: { route: data.route || '/' },
    });
  });
}

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const route = (event.notification.data && event.notification.data.route) || '/';
  const target = new URL(route, self.location.origin).href;
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windows) => {
      // Focus an open tab rather than stacking another copy of the app.
      for (const client of windows) {
        if (client.url === target && 'focus' in client) return client.focus();
      }
      return clients.openWindow ? clients.openWindow(target) : undefined;
    }),
  );
});
