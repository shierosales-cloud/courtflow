// Fully offline Piper TTS in the browser.
// Deps (all local, in ./vendor): onnxruntime-web 1.17.3 (ort.wasm.min.js + *.wasm),
// piper_phonemize (espeak-ng wasm, full espeak-ng-data incl. ru_dict).
// Load order in HTML: vendor/ort/ort.wasm.min.js, vendor/phonemize/piper_phonemize.js, then this file.

const PH_CFG = { pad: "_", bos: "^", eos: "$", interspersePad: true, addBos: true, addEos: true };

ort.env.wasm.wasmPaths = "./vendor/ort/";
ort.env.wasm.numThreads = self.crossOriginIsolated ? Math.min(4, navigator.hardwareConcurrency || 1) : 1;

let phonemizerPromise;
function getPhonemizer() {
  return phonemizerPromise ??= (async () => {
    let out = [];
    const mod = await createPiperPhonemize({
      print: line => out.push(JSON.parse(line)),
      printErr: line => console.warn("[espeak]", line),
      locateFile: f => "./vendor/phonemize/" + f,
    });
    return {
      // returns [{ text, processed_text, phonemes: [...], phoneme_ids: [...] }] per input text
      phonemize(texts, lang) {
        out = [];
        const rc = mod.callMain(["--espeak_data", "/espeak-ng-data", "--language", lang,
          "--input", JSON.stringify(texts.map(text => ({ text })))]);
        if (rc !== 0) throw new Error("piper_phonemize exit code " + rc);
        return out;
      },
    };
  })();
}

function phonemesToIds(phonemes, cfg) {
  const map = cfg.phoneme_id_map, ids = [], missing = new Set();
  const push = p => { const v = map[p]; if (v) { ids.push(...v); return true; } missing.add(p); return false; };
  if (PH_CFG.addBos) { push(PH_CFG.bos); if (PH_CFG.interspersePad) push(PH_CFG.pad); }
  for (const p of phonemes) if (push(p) && PH_CFG.interspersePad) push(PH_CFG.pad);
  if (PH_CFG.addEos) push(PH_CFG.eos);
  if (missing.size) console.warn("Missing phonemes", [...missing]);
  return ids;
}

async function createEngine(onnxUrl, cfgUrl) {
  const [buf, cfg] = await Promise.all([fetch(onnxUrl).then(r => r.arrayBuffer()), fetch(cfgUrl).then(r => r.json())]);
  const session = await ort.InferenceSession.create(buf, { executionProviders: ["wasm"] });
  const inf = cfg.inference ?? {};
  const sampleRate = cfg.audio?.sample_rate ?? 22050;
  const lang = cfg.espeak?.voice ?? "ru";
  return {
    cfg, sampleRate,
    async infer(ids, speakerId, { noiseScale = inf.noise_scale ?? 0.667, lengthScale = inf.length_scale ?? 1, noiseW = inf.noise_w ?? 0.8 } = {}) {
      const feeds = {
        input: new ort.Tensor("int64", BigInt64Array.from(ids.map(BigInt)), [1, ids.length]),
        input_lengths: new ort.Tensor("int64", BigInt64Array.from([BigInt(ids.length)]), [1]),
        scales: new ort.Tensor("float32", Float32Array.from([noiseScale, lengthScale, noiseW]), [3]),
      };
      if (speakerId != null) feeds.sid = new ort.Tensor("int64", BigInt64Array.from([BigInt(speakerId)]), [1]);
      const { output } = await session.run(feeds);
      return output.data; // Float32Array mono
    },
    async speak(text, opts = {}) {
      const ph = await getPhonemizer();
      // piper_phonemize CLI output: { text, phonemes: [flat...], phoneme_ids: [1,0,...,2, 1,0,...,2] }
      // phoneme_ids already have bos/pad/eos and sentence boundaries; split on eos (2).
      const [{ phoneme_ids }] = ph.phonemize([text], lang);
      const eos = cfg.phoneme_id_map[PH_CFG.eos][0];
      const sentences = []; let cur = [];
      for (const id of phoneme_ids) { cur.push(id); if (id === eos) { sentences.push(cur); cur = []; } }
      if (cur.length) sentences.push(cur);
      const gap = new Float32Array(Math.round(sampleRate * (opts.sentenceSilence ?? 0.2)));
      const chunks = [];
      for (const ids of sentences) chunks.push(await this.infer(ids, opts.speakerId, opts), gap);
      const out = new Float32Array(chunks.reduce((n, c) => n + c.length, 0));
      let o = 0; for (const c of chunks) { out.set(c, o); o += c.length; }
      return out;
    },
    dispose: () => session.release(),
  };
}

function toWav(samples, sampleRate) {
  const buf = new ArrayBuffer(44 + samples.length * 2), v = new DataView(buf);
  const w = (o, s) => [...s].forEach((c, i) => v.setUint8(o + i, c.charCodeAt(0)));
  w(0, "RIFF"); v.setUint32(4, 36 + samples.length * 2, true); w(8, "WAVE"); w(12, "fmt ");
  v.setUint32(16, 16, true); v.setUint16(20, 1, true); v.setUint16(22, 1, true);
  v.setUint32(24, sampleRate, true); v.setUint32(28, sampleRate * 2, true); v.setUint16(32, 2, true); v.setUint16(34, 16, true);
  w(36, "data"); v.setUint32(40, samples.length * 2, true);
  for (let i = 0; i < samples.length; i++) v.setInt16(44 + i * 2, Math.max(-1, Math.min(1, samples[i])) * 32767, true);
  return new Blob([buf], { type: "audio/wav" });
}

function playPcm(samples, sampleRate) {
  const ctx = new AudioContext();
  const b = ctx.createBuffer(1, samples.length, sampleRate);
  b.getChannelData(0).set(samples);
  const src = ctx.createBufferSource(); src.buffer = b; src.connect(ctx.destination); src.start();
  return new Promise(r => src.onended = r);
}

window.Piper = { createEngine, getPhonemizer, phonemesToIds, toWav, playPcm };
