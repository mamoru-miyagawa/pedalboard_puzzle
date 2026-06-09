/*! coi-serviceworker - MIT - https://github.com/gzuidhof/coi-serviceworker
 * Adds the Cross-Origin-Opener-Policy / Cross-Origin-Embedder-Policy headers
 * so SharedArrayBuffer (which Godot 4 web builds need) works on static hosts
 * like GitHub Pages, which can't set HTTP headers themselves.
 */
if (typeof window === 'undefined') {
    self.addEventListener('install', () => self.skipWaiting());
    self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

    self.addEventListener('fetch', function (event) {
        const r = event.request;
        if (r.cache === 'only-if-cached' && r.mode !== 'same-origin') {
            return;
        }
        event.respondWith(
            fetch(r)
                .then((response) => {
                    if (response.status === 0) {
                        return response;
                    }
                    const newHeaders = new Headers(response.headers);
                    newHeaders.set('Cross-Origin-Embedder-Policy', 'require-corp');
                    newHeaders.set('Cross-Origin-Opener-Policy', 'same-origin');
                    return new Response(response.body, {
                        status: response.status,
                        statusText: response.statusText,
                        headers: newHeaders,
                    });
                })
                .catch((e) => console.error(e))
        );
    });
} else {
    (() => {
        // If already cross-origin isolated, nothing to do.
        if (window.crossOriginIsolated !== false) return;
        if (!window.isSecureContext) {
            console.log('COOP/COEP Service Worker not registered: a secure (https) context is required.');
            return;
        }
        if (!navigator.serviceWorker) return;

        navigator.serviceWorker.register(window.document.currentScript.src).then(
            (registration) => {
                console.log('COOP/COEP Service Worker registered', registration.scope);
                registration.addEventListener('updatefound', () => {
                    console.log('Reloading page to make use of updated COOP/COEP Service Worker.');
                    window.location.reload();
                });
                // If the registration is active but it's not controlling the page, reload once.
                if (registration.active && !navigator.serviceWorker.controller) {
                    console.log('Reloading page to make use of COOP/COEP Service Worker.');
                    window.location.reload();
                }
            },
            (err) => console.error('COOP/COEP Service Worker failed to register:', err)
        );
    })();
}
