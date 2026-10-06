/* Service worker da Central de Chamados: recebe os avisos push do time (Edge Function chamados-push). */
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

self.addEventListener('push', (e) => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch { d = { titulo: 'Central de Chamados', corpo: e.data ? e.data.text() : '' }; }
  const urg = Number(d.urgencia ?? 1);
  e.waitUntil((async () => {
    await self.registration.showNotification(d.titulo || 'Central de Chamados', {
      body: d.corpo || '',
      tag: d.tag || 'chamados',
      renotify: true,                       // lembrete do mesmo chamado substitui o anterior, mas toca de novo
      requireInteraction: !!d.exigirInteracao,
      vibrate: Array.isArray(d.vibrar) ? d.vibrar : [200],
      icon: '/icon-192.png',
      badge: '/badge-72.png',
      silent: false,
      timestamp: Date.now(),
      data: { url: d.url || '/', protocolo: d.protocolo, urgencia: urg },
    });
    // Aba aberta: avisa para atualizar a lista (o som próprio já toca pela aba).
    const abas = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    abas.forEach((c) => c.postMessage({ tipo: 'push', protocolo: d.protocolo, urgencia: urg }));
  })());
});

self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  const url = new URL((e.notification.data && e.notification.data.url) || '/', self.location.origin).href;
  e.waitUntil((async () => {
    const abas = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const c of abas) {
      if (new URL(c.url).origin === self.location.origin && 'focus' in c) { await c.focus(); return; }
    }
    await self.clients.openWindow(url);
  })());
});
