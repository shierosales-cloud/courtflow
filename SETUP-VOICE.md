# CourtFlow v27 — Fully Bundled Offline Announcements

CourtFlow uses Piper neural text-to-speech in the browser. This package includes the English voice model and all required runtime assets inside the Netlify deployment. It does not call the Supabase `tts` Edge Function and does not need a Google Cloud key.

## First use

1. Deploy the contents of this package's `CourtFlow-app-final-v27` folder to the Netlify site. Keep `vendor/`, `piper-browser.js`, `en_US-joe-medium.onnx`, and its `.json` config beside `index.html`.
2. Open CourtFlow on the iPad while connected to the internet.
3. Leave Voice set to **Natural voice (offline after first download)**.
4. Select the JBL speaker from iPad Control Center's audio output picker.
5. Tap Announce. The iPad loads the bundled runtime and English model from your own Netlify site. The ONNX model is about 60 MB and phonemizer data about 17 MB. Keep CourtFlow open until “Natural offline voice is ready” appears and the announcement plays.
6. Later announcements are synthesized on-device. The service worker caches same-origin assets when browser storage permits; offline reuse depends on iPadOS retaining that cache.

## Device voice option

Choose **Device voice (system voice)** to use iPadOS speech synthesis. On some iPadOS versions this voice may play through the iPad speaker rather than the selected Bluetooth output.

## Important notes

- Voice engine, WASM files, phonemizer data, and model are included in the Netlify package. No GitHub, jsDelivr, other CDN, Google Cloud, or Supabase TTS request is needed.
- The first use still transfers those bundled assets from your own Netlify site to the iPad; they are not pre-installed in the browser.
- Announcement text is processed locally in the browser and is not sent to a TTS service.
- iPadOS controls the active audio destination. CourtFlow cannot force the JBL output; select it in Control Center before announcing.
- The Supabase Edge Function under `supabase/functions/tts` is not required for announcements and can remain undeployed.
