# Web Build Instructions & Testing URL

After running `flutter build web --release`, serve the `build/web` directory locally (for example `python3 -m http.server 8080 --directory build/web`).

Use the cache-busted URL below when testing:

```
http://localhost:8080/index.html?v=animals-stream-r1
```

Update the host/port as needed if you publish the bundle elsewhere; keep the `?v=animals-stream-r1` suffix to ensure cached assets refresh on Android WebView.
