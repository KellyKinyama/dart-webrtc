// E2EE worker for the ion-style SFU demo.
//
// Uses RTCRtpScriptTransform (Insertable Streams) to encrypt every
// outbound encoded frame and decrypt every inbound encoded frame with
// AES-GCM-128. The shared key is supplied by the page (derived from a
// passphrase) so all peers in the room can decrypt each other.
//
// Wire format per encrypted frame:
//
//   [ codec prefix : N bytes (cleartext)       ]
//   [ ciphertext   : variable                  ]
//   [ auth tag     : 16 bytes (AES-GCM)        ]
//   [ IV           : 12 bytes                  ]
//   [ prefix len   : 1 byte                    ]
//
// The trailing prefix-length byte lets the receiver locate the codec
// prefix without reparsing the payload. A small codec-specific prefix
// is left in the clear so the SFU can still inspect things like the
// VP8/VP9 descriptor or the H.264 NAL header for keyframe detection.
//
// The IV is per-frame random (12 bytes via crypto.getRandomValues),
// which is safe because AES-GCM tolerates random IVs up to 2^32 frames
// per key. For a real deployment use SFrame (RFC 9605) which adds
// proper key rotation, replay protection, and salted IVs.

// Bytes of payload to leave unencrypted, by codec mime-type.
// Picked to cover the descriptor bytes a typical SFU inspects.
const CLEAR_PREFIX_BY_MIME = {
  'video/VP8':  10,
  'video/VP9':  10,
  'video/H264': 10,
  'video/AV1':  10,
  'audio/opus':  1,
  'audio/PCMA':  0,
  'audio/PCMU':  0,
};

let cryptoKey = null;

self.addEventListener('message', async (e) => {
  const { type, keyBytes } = e.data || {};
  if (type === 'setKey') {
    cryptoKey = await crypto.subtle.importKey(
      'raw', keyBytes, { name: 'AES-GCM' }, false, ['encrypt', 'decrypt']);
    self.postMessage({ type: 'keyReady' });
  }
});

self.onrtctransform = (event) => {
  const transformer = event.transformer;
  const dir = transformer.options && transformer.options.direction; // 'send' | 'receive'
  const mime = (transformer.options && transformer.options.mimeType) || '';
  const prefixLen = CLEAR_PREFIX_BY_MIME[mime] ?? 1;

  const xform = new TransformStream({
    transform: async (frame, controller) => {
      try {
        if (!cryptoKey) {
          // Pass through until the key arrives so we don't break the
          // initial handshake / DTLS-SRTP setup.
          controller.enqueue(frame);
          return;
        }
        if (dir === 'send') {
          await encryptFrame(frame, prefixLen);
        } else {
          await decryptFrame(frame);
        }
        controller.enqueue(frame);
      } catch (err) {
        // Drop frames we can't process so a bad key doesn't lock up
        // the receiver.
        // eslint-disable-next-line no-console
        console.warn('e2ee transform error', err);
      }
    },
  });

  transformer.readable.pipeThrough(xform).pipeTo(transformer.writable);
};

async function encryptFrame(frame, prefixLen) {
  const view = new Uint8Array(frame.data);
  const clear = view.subarray(0, Math.min(prefixLen, view.length));
  const body  = view.subarray(clear.length);

  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = new Uint8Array(await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv }, cryptoKey, body));

  // Layout: [clear][ct+tag][iv:12][prefixLen:1]
  const out = new Uint8Array(clear.length + ct.length + 12 + 1);
  out.set(clear, 0);
  out.set(ct, clear.length);
  out.set(iv, clear.length + ct.length);
  out[out.length - 1] = clear.length;

  frame.data = out.buffer;
}

async function decryptFrame(frame) {
  const view = new Uint8Array(frame.data);
  if (view.length < 1 + 12 + 16) throw new Error('frame too short');

  const prefixLen = view[view.length - 1];
  const ivStart   = view.length - 1 - 12;
  const ctStart   = prefixLen;
  if (ivStart < ctStart) throw new Error('frame layout invalid');

  const clear = view.subarray(0, prefixLen);
  const ct    = view.subarray(ctStart, ivStart);
  const iv    = view.subarray(ivStart, ivStart + 12);

  const pt = new Uint8Array(await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv }, cryptoKey, ct));

  const out = new Uint8Array(clear.length + pt.length);
  out.set(clear, 0);
  out.set(pt, clear.length);
  frame.data = out.buffer;
}
