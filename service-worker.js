
const CACHE_NAME = "line-pwa-v13";
const APP_SHELL = [
  "/",
  "/manifest.json",
  "/icons/icon-192.png",
  "/icons/icon-512.png",
  "/icons/apple-touch-icon.png"
];

self.addEventListener("install", event => {
  self.skipWaiting();
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache => cache.addAll(APP_SHELL).catch(() => {}))
  );
});

self.addEventListener("activate", event => {
  event.waitUntil((async()=>{
    const names = await caches.keys();
    await Promise.all(names.filter(n => n !== CACHE_NAME).map(n => caches.delete(n)));
    await self.clients.claim();
  })());
});

self.addEventListener("message", event => {
  if(event.data?.type === "SKIP_WAITING") self.skipWaiting();
});

self.addEventListener("fetch", event => {
  const req = event.request;
  const url = new URL(req.url);

  if(req.method !== "GET") return;

  // Never cache Supabase/API calls.
  if(
    url.hostname.includes("supabase.co") ||
    url.pathname.includes("/functions/v1/") ||
    url.pathname.includes("/rest/v1/")
  ) return;

  if(req.mode === "navigate"){
    event.respondWith((async()=>{
      try{
        const fresh = await fetch(req);
        const cache = await caches.open(CACHE_NAME);
        cache.put("/", fresh.clone());
        return fresh;
      }catch{
        return (await caches.match(req)) || (await caches.match("/"));
      }
    })());
    return;
  }

  event.respondWith(
    caches.match(req).then(cached => cached || fetch(req).then(res => {
      if(res && res.status === 200 && res.type === "basic"){
        const clone = res.clone();
        caches.open(CACHE_NAME).then(c => c.put(req, clone));
      }
      return res;
    }))
  );
});

self.addEventListener("push", event => {
  let payload = {};
  try{
    payload = event.data ? event.data.json() : {};
  }catch{
    payload = {body: event.data?.text() || "Você tem uma nova notificação da LINE."};
  }

  const title = payload.title || "LINE • Interligados";
  const options = {
    body: payload.body || "Você tem uma nova atualização.",
    icon: payload.icon || "/icons/icon-192.png",
    badge: payload.badge || "/icons/icon-192.png",
    tag: payload.tag || "line-notification",
    renotify: true,
    requireInteraction: false,
    data: {
      url: payload.url || "/#notificacoes",
      notification_id: payload.notification_id || null,
      event_id: payload.event_id || null
    },
    actions: payload.actions || [
      {action:"open", title:"Abrir LINE"}
    ]
  };

  event.waitUntil((async()=>{
    await self.registration.showNotification(title, options);
    try{
      if(self.navigator?.setAppBadge){
        await self.navigator.setAppBadge(Number(payload.badge_count || 1));
      }
    }catch{}
  })());
});

self.addEventListener("notificationclick", event => {
  event.notification.close();
  const targetUrl = new URL(event.notification.data?.url || "/#notificacoes", self.location.origin).href;

  event.waitUntil((async()=>{
    const clientsList = await clients.matchAll({type:"window", includeUncontrolled:true});
    for(const client of clientsList){
      if("focus" in client){
        try{
          await client.navigate(targetUrl);
        }catch{}
        return client.focus();
      }
    }
    if(clients.openWindow) return clients.openWindow(targetUrl);
  })());
});

self.addEventListener("notificationclose", () => {});
