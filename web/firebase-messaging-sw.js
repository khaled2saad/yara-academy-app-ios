/* Background notifications for the website (Firebase Cloud Messaging). The web config below is public by design. */
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js', 'https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');
firebase.initializeApp({ apiKey: 'AIzaSyBsBykjb_ibfeuw8ra_WqjTLGTJlkpxhng', authDomain: 'device-streaming-2ca492cd.firebaseapp.com', projectId: 'device-streaming-2ca492cd', storageBucket: 'device-streaming-2ca492cd.firebasestorage.app', messagingSenderId: '17974910911', appId: '1:17974910911:web:874a17bb35231966380b0a' });
firebase.messaging(); // messages that carry a "notification" are shown by the SDK itself
self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  const data = e.notification.data?.FCM_MSG?.data;
  e.waitUntil(clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
    for (const c of list) if ('focus' in c) { if (data) c.postMessage({ type: 'yara-ring', data }); return c.focus(); }
    return clients.openWindow(data ? '/?lessonAlert=' + encodeURIComponent(JSON.stringify(data)) : '/');
  }));
});
