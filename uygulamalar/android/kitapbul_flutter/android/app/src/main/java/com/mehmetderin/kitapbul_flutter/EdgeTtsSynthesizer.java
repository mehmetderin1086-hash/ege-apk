package com.mehmetderin.kitapbul_flutter;

import android.util.Base64;
import java.io.ByteArrayOutputStream;
import java.io.EOFException;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.Locale;
import java.util.TimeZone;
import java.util.UUID;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.SSLSocketFactory;

final class EdgeTtsSynthesizer {
    static final String DEFAULT_VOICE = "tr-TR-AhmetNeural";
    static final String EMEL_VOICE = "tr-TR-EmelNeural";
    static final String SYSTEM_VOICE = "system";

    private static final String HOST = "speech.platform.bing.com";
    private static final int PORT = 443;
    private static final String TRUSTED_CLIENT_TOKEN = "6A5AA1D4EAFF4E9FB37E23D68491D6F4";
    private static final String SEC_MS_GEC_VERSION = "2-143.0.3650.75";
    private static final String USER_AGENT =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0";

    private static final long[] D_A = new long[] {
        0x6a09e667L, 0xbb67ae85L, 0x3c6ef372L, 0xa54ff53aL,
        0x510e527fL, 0x9b05688cL, 0x1f83d9abL, 0x5be0cd19L
    };
    private static final long[] D_B = new long[] {
        0xfd9fbea2L, 0x91243ce7L, 0xbe499094L, 0xcd2e1e0aL,
        0x6c006f49L, 0x04bd35abL, 0xfeb0a7e4L, 0x03effbd2L
    };
    private static final long[] D_C = new long[] {
        0xeb24bf9eL, 0x1558691fL, 0xa0c09ee2L, 0x0cfa32baL,
        0xa622ee8cL, 0xd1dd9491L, 0xc0dd25a0L, 0xf9e70ab6L,
        0xf0c31573L, 0x7058ce4eL, 0x7188e606L, 0x00e5ab33L,
        0xd258b060L, 0x72766564L
    };
    private static final long[] D_D = new long[] {
        0x428a2f98L, 0x71374491L, 0xb5c0fbcfL, 0xe9b5dba5L, 0x3956c25bL, 0x59f111f1L, 0x923f82a4L, 0xab1c5ed5L,
        0xd807aa98L, 0x12835b01L, 0x243185beL, 0x550c7dc3L, 0x72be5d74L, 0x80deb1feL, 0x9bdc06a7L, 0xc19bf174L,
        0xe49b69c1L, 0xefbe4786L, 0x0fc19dc6L, 0x240ca1ccL, 0x2de92c6fL, 0x4a7484aaL, 0x5cb0a9dcL, 0x76f988daL,
        0x983e5152L, 0xa831c66dL, 0xb00327c8L, 0xbf597fc7L, 0xc6e00bf3L, 0xd5a79147L, 0x06ca6351L, 0x14292967L,
        0x27b70a85L, 0x2e1b2138L, 0x4d2c6dfcL, 0x53380d13L, 0x650a7354L, 0x766a0abbL, 0x81c2c92eL, 0x92722c85L,
        0xa2bfe8a1L, 0xa81a664bL, 0xc24b8b70L, 0xc76c51a3L, 0xd192e819L, 0xd6990624L, 0xf40e3585L, 0x106aa070L,
        0x19a4c116L, 0x1e376c08L, 0x2748774cL, 0x34b0bcb5L, 0x391c0cb3L, 0x4ed8aa4aL, 0x5b9cca4fL, 0x682e6ff3L,
        0x748f82eeL, 0x78a5636fL, 0x84c87814L, 0x8cc70208L, 0x90befffaL, 0xa4506cebL, 0xbef9a3f7L, 0xc67178f2L
    };
    private static final long[] D_E = new long[64];
    static {
        for (int i = 0; i < 64; i++) {
            D_E[i] = (i == 14) ? 0xc9dc06a7L : D_D[i];
        }
    }
    private static final long[][] D_F = new long[][] {
        {0xe82e91b1L, 0xb32700d0L},
        {0x44de24c6L, 0x88dff51dL},
        {0x3beb65bcL, 0x29514038L},
        {0xc89c5933L, 0xb328cbdfL},
        {0x8d1ec211L, 0xd405b4d5L},
        {0x314ef5d5L, 0x26e55f3cL},
        {0xe92491b1L, 0x607801c6L},
        {0xf0a5b9d5L, 0x82b2c1fbL},
        {0x06064cf3L, 0xfa51a3daL},
        {0xda79fa60L, 0x207cc464L},
        {0xbed20560L, 0x3c3c74f3L},
        {0x89f9c9f8L, 0xd2d14b61L},
        {0x35fa38c6L, 0xbb04a2c1L},
        {0xcb49e3c6L, 0xc5626167L}
    };

    private static final SecureRandom RANDOM = new SecureRandom();

    private EdgeTtsSynthesizer() {}

    static String resolveVoice(String preferredVoice) {
        if (preferredVoice == null) return DEFAULT_VOICE;
        String trimmed = preferredVoice.trim();
        if (trimmed.equalsIgnoreCase(SYSTEM_VOICE)) return SYSTEM_VOICE;
        if (trimmed.isEmpty() || !trimmed.toLowerCase(Locale.ROOT).contains("neural")) {
            return DEFAULT_VOICE;
        }
        return trimmed;
    }

    static File synthesizeToFile(
            File cacheDir, String text, String voiceName, double rate, double pitch) {
        String clean = sanitizeSpeechText(text);
        if (clean.isEmpty()) return null;

        double safeRate = Math.max(0.5, Math.min(2.0, rate <= 0 ? 1.0 : rate));
        double safePitch = Math.max(0.5, Math.min(1.6, pitch <= 0 ? 1.0 : pitch));
        int ratePct = (int) Math.round((safeRate - 1.0) * 100.0);
        int pitchHz = (int) Math.round((safePitch - 1.0) * 50.0);
        String rateStr = (ratePct >= 0 ? "+" : "") + ratePct + "%";
        String pitchStr = (pitchHz >= 0 ? "+" : "") + pitchHz + "Hz";

        File ttsCacheDir = new File(cacheDir, "edge_tts_cache");
        if (!ttsCacheDir.exists()) {
            ttsCacheDir.mkdirs();
        }
        String key = sha256Hex(voiceName + "|" + rateStr + "|" + pitchStr + "|" + clean);
        File target = new File(ttsCacheDir, "tts_" + key + ".mp3");
        if (target.exists() && target.length() > 128L) {
            return target;
        }

        byte[] mp3 = fetchMp3OverWebSocket(clean, voiceName, rateStr, pitchStr);
        if (mp3 == null || mp3.length <= 128) return null;

        try {
            File tmp = new File(ttsCacheDir, "tts_" + key + "_" + System.nanoTime() + ".tmp");
            try (FileOutputStream out = new FileOutputStream(tmp)) {
                out.write(mp3);
                out.flush();
            }
            if (!tmp.renameTo(target)) {
                try (FileOutputStream out = new FileOutputStream(target)) {
                    out.write(mp3);
                    out.flush();
                }
                tmp.delete();
            }
            return target;
        } catch (Exception ignored) {
            return null;
        }
    }

    private static byte[] fetchMp3OverWebSocket(
            String cleanText, String voiceName, String rateStr, String pitchStr) {
        for (int attempt = 0; attempt < 2; attempt++) {
            SSLSocket socket = null;
            try {
                String secMsGec = generateSecMsGec();
                String connId = UUID.randomUUID().toString().replace("-", "");
                String muid = UUID.randomUUID().toString().replace("-", "").toUpperCase(Locale.ROOT);
                byte[] wsKeyBytes = new byte[16];
                RANDOM.nextBytes(wsKeyBytes);
                String wsKey = Base64.encodeToString(wsKeyBytes, Base64.NO_WRAP);

                SSLSocketFactory factory = (SSLSocketFactory) SSLSocketFactory.getDefault();
                socket = (SSLSocket) factory.createSocket(HOST, PORT);
                socket.setSoTimeout(12000);
                socket.startHandshake();

                InputStream input = socket.getInputStream();
                OutputStream output = socket.getOutputStream();

                String path = "/consumer/speech/synthesize/readaloud/edge/v1"
                        + "?TrustedClientToken=" + TRUSTED_CLIENT_TOKEN
                        + "&ConnectionId=" + connId
                        + "&Sec-MS-GEC=" + secMsGec
                        + "&Sec-MS-GEC-Version=" + SEC_MS_GEC_VERSION;

                String handshake = "GET " + path + " HTTP/1.1\r\n"
                        + "Host: " + HOST + "\r\n"
                        + "Pragma: no-cache\r\n"
                        + "Cache-Control: no-cache\r\n"
                        + "Origin: chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold\r\n"
                        + "User-Agent: " + USER_AGENT + "\r\n"
                        + "Accept-Language: en-US,en;q=0.9\r\n"
                        + "Cookie: muid=" + muid + ";\r\n"
                        + "Upgrade: websocket\r\n"
                        + "Connection: Upgrade\r\n"
                        + "Sec-WebSocket-Key: " + wsKey + "\r\n"
                        + "Sec-WebSocket-Version: 13\r\n\r\n";

                output.write(handshake.getBytes(StandardCharsets.UTF_8));
                output.flush();

                String statusLine = readHttpHeader(input);
                if (!statusLine.contains("101")) {
                    socket.close();
                    continue;
                }

                String timestamp = isoTimestamp();
                String configPayload = "X-Timestamp:" + timestamp + "\r\n"
                        + "Content-Type:application/json; charset=utf-8\r\n"
                        + "Path:speech.config\r\n\r\n"
                        + "{\"context\":{\"synthesis\":{\"audio\":{\"metadataoptions\":{\"sentenceBoundaryEnabled\":\"false\",\"wordBoundaryEnabled\":\"false\"},\"outputFormat\":\"audio-24khz-48kbitrate-mono-mp3\"}}}}\r\n";
                sendWebSocketFrame(output, 0x81, configPayload.getBytes(StandardCharsets.UTF_8));

                String reqId = UUID.randomUUID().toString().replace("-", "");
                String langAttr = (voiceName.length() >= 5 && voiceName.charAt(2) == '-')
                        ? voiceName.substring(0, 5)
                        : "tr-TR";
                String ssmlPayload = "X-RequestId:" + reqId + "\r\n"
                        + "Content-Type:application/ssml+xml\r\n"
                        + "X-Timestamp:" + timestamp + "Z\r\n"
                        + "Path:ssml\r\n\r\n"
                        + "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='" + langAttr + "'>"
                        + "<voice name='" + voiceName + "'>"
                        + "<prosody pitch='" + pitchStr + "' rate='" + rateStr + "' volume='+0%'>"
                        + escapeXml(cleanText)
                        + "</prosody></voice></speak>";
                sendWebSocketFrame(output, 0x81, ssmlPayload.getBytes(StandardCharsets.UTF_8));

                ByteArrayOutputStream audioOut = new ByteArrayOutputStream(32768);
                while (true) {
                    WsFrame frame = readWebSocketFrame(input);
                    if (frame == null) break;
                    if (frame.opcode == 1) {
                        String txt = new String(frame.payload, StandardCharsets.UTF_8);
                        if (txt.contains("Path:turn.end")) {
                            break;
                        }
                    } else if (frame.opcode == 2) {
                        byte[] p = frame.payload;
                        if (p.length > 2) {
                            int headerLen = ((p[0] & 0xFF) << 8) | (p[1] & 0xFF);
                            if (p.length >= 2 + headerLen) {
                                String headerStr = new String(p, 2, headerLen, StandardCharsets.UTF_8);
                                if (headerStr.contains("Path:audio")) {
                                    int audioOffset = 2 + headerLen;
                                    int audioLen = p.length - audioOffset;
                                    if (audioLen > 0) {
                                        audioOut.write(p, audioOffset, audioLen);
                                    }
                                }
                            }
                        }
                    } else if (frame.opcode == 8) {
                        break;
                    } else if (frame.opcode == 9) {
                        sendWebSocketFrame(output, 0x8A, frame.payload);
                    }
                }
                try {
                    socket.close();
                } catch (Exception ignored) {}

                byte[] bytes = audioOut.toByteArray();
                if (bytes.length > 128) {
                    return bytes;
                }
            } catch (Exception ignored) {
                if (socket != null) {
                    try {
                        socket.close();
                    } catch (Exception ignored2) {}
                }
            }
        }
        return null;
    }

    private static final class WsFrame {
        final int opcode;
        final byte[] payload;
        WsFrame(int opcode, byte[] payload) {
            this.opcode = opcode;
            this.payload = payload;
        }
    }

    private static String readHttpHeader(InputStream input) throws Exception {
        ByteArrayOutputStream buf = new ByteArrayOutputStream(512);
        int state = 0;
        while (true) {
            int b = input.read();
            if (b == -1) break;
            buf.write(b);
            if (state == 0 && b == '\r') state = 1;
            else if (state == 1 && b == '\n') state = 2;
            else if (state == 2 && b == '\r') state = 3;
            else if (state == 3 && b == '\n') state = 4;
            else if (b == '\r') state = 1;
            else state = 0;
            if (state == 4 || buf.size() > 8192) break;
        }
        String header = new String(buf.toByteArray(), StandardCharsets.UTF_8);
        int idx = header.indexOf("\r\n");
        return idx >= 0 ? header.substring(0, idx) : header;
    }

    private static void sendWebSocketFrame(OutputStream output, int firstByte, byte[] payload)
            throws Exception {
        byte[] mask = new byte[4];
        RANDOM.nextBytes(mask);
        int n = payload.length;
        ByteArrayOutputStream header = new ByteArrayOutputStream(14);
        header.write(firstByte);
        if (n < 126) {
            header.write(0x80 | n);
        } else if (n < 65536) {
            header.write(0x80 | 126);
            header.write((n >>> 8) & 0xFF);
            header.write(n & 0xFF);
        } else {
            header.write(0x80 | 127);
            long lenLong = n;
            for (int i = 7; i >= 0; i--) {
                header.write((int) ((lenLong >>> (i * 8)) & 0xFFL));
            }
        }
        header.write(mask);
        byte[] masked = new byte[n];
        for (int i = 0; i < n; i++) {
            masked[i] = (byte) (payload[i] ^ mask[i & 3]);
        }
        output.write(header.toByteArray());
        output.write(masked);
        output.flush();
    }

    private static WsFrame readWebSocketFrame(InputStream input) throws Exception {
        int b0 = input.read();
        if (b0 == -1) return null;
        int b1 = input.read();
        if (b1 == -1) return null;

        int opcode = b0 & 0x0F;
        boolean masked = (b1 & 0x80) != 0;
        long length = b1 & 0x7F;
        if (length == 126L) {
            byte[] lenBytes = readExact(input, 2);
            length = ((lenBytes[0] & 0xFF) << 8) | (lenBytes[1] & 0xFF);
        } else if (length == 127L) {
            byte[] lenBytes = readExact(input, 8);
            length = 0L;
            for (int i = 0; i < 8; i++) {
                length = (length << 8) | (lenBytes[i] & 0xFFL);
            }
        }
        byte[] maskKey = masked ? readExact(input, 4) : null;
        byte[] payload = readExact(input, (int) length);
        if (masked && maskKey != null) {
            for (int i = 0; i < payload.length; i++) {
                payload[i] = (byte) (payload[i] ^ maskKey[i & 3]);
            }
        }
        return new WsFrame(opcode, payload);
    }

    private static byte[] readExact(InputStream input, int len) throws Exception {
        byte[] out = new byte[len];
        int offset = 0;
        while (offset < len) {
            int n = input.read(out, offset, len - offset);
            if (n < 0) throw new EOFException("Unexpected EOF");
            offset += n;
        }
        return out;
    }

    private static long dB(long x) {
        long u = x & 0xFFFFFFFFL;
        return ((u << 16) | (u >>> 16)) & 0xFFFFFFFFL;
    }

    private static long dD(long x) {
        long u = x & 0xFFFFFFFFL;
        return ((u >>> 7) ^ (u << 25) ^ (u >>> 18) ^ (u << 14) ^ (u >>> 3)) & 0xFFFFFFFFL;
    }

    private static long dE(long x) {
        long u = x & 0xFFFFFFFFL;
        return ((u >>> 17) ^ (u << 15) ^ (u >>> 19) ^ (u << 13) ^ (u >>> 10)) & 0xFFFFFFFFL;
    }

    private static void dA(ArrayList<Long> w, int startIdx) {
        for (int idx = startIdx; idx < 64; idx++) {
            long sum = (w.get(idx - 7) + dE(w.get(idx - 2)) + dD(w.get(idx - 15)) + w.get(idx - 16))
                    & 0xFFFFFFFFL;
            w.add(sum);
        }
    }

    private static long rotr32(long x, int n) {
        long u = x & 0xFFFFFFFFL;
        return ((u >>> n) | (u << (32 - n))) & 0xFFFFFFFFL;
    }

    private static long[] dC(long[] state, ArrayList<Long> w, int startRound) {
        long a = state[0] & 0xFFFFFFFFL;
        long b = state[1] & 0xFFFFFFFFL;
        long c = state[2] & 0xFFFFFFFFL;
        long d = state[3] & 0xFFFFFFFFL;
        long e = state[4] & 0xFFFFFFFFL;
        long f = state[5] & 0xFFFFFFFFL;
        long g = state[6] & 0xFFFFFFFFL;
        long h = state[7] & 0xFFFFFFFFL;
        long[] k = (startRound == 14) ? D_E : D_D;

        for (int r = startRound; r < 64; r++) {
            long s1 = rotr32(e, 6) ^ rotr32(e, 11) ^ rotr32(e, 25);
            long ch = g ^ (e & (f ^ g));
            long temp1 = (h + s1 + ch + k[r] + w.get(r)) & 0xFFFFFFFFL;
            long s0 = rotr32(a, 2) ^ rotr32(a, 13) ^ rotr32(a, 22);
            long maj = (a & b) | (c & (a | b));
            long newA = (temp1 + s0 + maj) & 0xFFFFFFFFL;
            long newE = (d + temp1) & 0xFFFFFFFFL;
            h = g;
            g = f;
            f = e;
            e = newE;
            d = c;
            c = b;
            b = a;
            a = newA;
        }
        return new long[] {a, b, c, d, e, f, g, h};
    }

    static String generateSecMsGec() {
        long sec = (System.currentTimeMillis() / 1000L) + 11644473600L;
        sec -= (sec % 300L);
        long ticks = sec * 10000000L;
        byte[] msgBytes = (ticks + TRUSTED_CLIENT_TOKEN).getBytes(StandardCharsets.UTF_8);
        int len = msgBytes.length;
        int totalLen = len + 57;
        int padZeros = (55 - totalLen) % 64;
        if (padZeros < 0) padZeros += 64;
        int v1 = len - 6 + padZeros;
        int tailLen = v1 + 8;
        byte[] tail = new byte[tailLen];
        System.arraycopy(msgBytes, 7, tail, 0, len - 7);
        tail[len - 7] = (byte) 0x80;
        long bitLen = ((long) totalLen) * 8L;
        for (int i = 0; i < 8; i++) {
            tail[v1 + i] = (byte) ((bitLen >>> ((7 - i) * 8)) & 0xFFL);
        }

        ArrayList<Long> w = new ArrayList<>(64);
        for (int i = 0; i < 14; i++) {
            w.add(0L);
        }
        w.add(((msgBytes[0] & 0xFFL) << 16)
                | ((msgBytes[1] & 0xFFL) << 8)
                | (msgBytes[2] & 0xFFL));
        w.add(((msgBytes[3] & 0xFFL) << 24)
                | ((msgBytes[4] & 0xFFL) << 16)
                | ((msgBytes[5] & 0xFFL) << 8)
                | (msgBytes[6] & 0xFFL));

        for (int i = 16; i < 30; i++) {
            long v = D_C[i - 16];
            if (i - 2 >= 14) {
                long t = dE(w.get(i - 2));
                if (i == 16) t ^= 0x000b92c0L;
                v += t;
            }
            if (i - 7 >= 14) {
                v += w.get(i - 7);
            }
            if (i - 15 >= 14) {
                long t = dD(w.get(i - 15));
                if (i == 29) t ^= 0x059c0b80L;
                v += t;
            }
            w.add(v & 0xFFFFFFFFL);
        }
        long val30 = (w.get(23) + dE(w.get(28)) + dD(w.get(15)) + w.get(14) + 0xc9dc06a7L - D_D[14])
                & 0xFFFFFFFFL;
        w.add(val30);
        dA(w, 31);
        long[] out0 = dC(D_B, w, 14);
        long[] state = new long[8];
        for (int j = 0; j < 8; j++) {
            state[j] = (D_A[j] + out0[j]) & 0xFFFFFFFFL;
        }

        for (int offset = 0; offset < tail.length; offset += 64) {
            ArrayList<Long> w2 = new ArrayList<>(64);
            for (int j = 0; j < 16; j++) {
                int base = offset + j * 4;
                long word = ((tail[base] & 0xFFL) << 24)
                        | ((tail[base + 1] & 0xFFL) << 16)
                        | ((tail[base + 2] & 0xFFL) << 8)
                        | (tail[base + 3] & 0xFFL);
                w2.add(word);
            }
            dA(w2, 16);
            long[] outChunk = dC(state, w2, 0);
            for (int j = 0; j < 8; j++) {
                state[j] = (state[j] + outChunk[j]) & 0xFFFFFFFFL;
            }
        }

        byte[] digest32 = new byte[32];
        for (int j = 0; j < 8; j++) {
            long word = state[j];
            int base = j * 4;
            digest32[base] = (byte) ((word >>> 24) & 0xFFL);
            digest32[base + 1] = (byte) ((word >>> 16) & 0xFFL);
            digest32[base + 2] = (byte) ((word >>> 8) & 0xFFL);
            digest32[base + 3] = (byte) (word & 0xFFL);
        }

        long k0 = ((digest32[0] & 0xFFL)
                | ((digest32[1] & 0xFFL) << 8)
                | ((digest32[2] & 0xFFL) << 16)
                | ((digest32[3] & 0xFFL) << 24)) | 1L;
        long k1 = ((digest32[4] & 0xFFL)
                | ((digest32[5] & 0xFFL) << 8)
                | ((digest32[6] & 0xFFL) << 16)
                | ((digest32[7] & 0xFFL) << 24)) | 1L;

        long s0 = (k0 * 0x82893933L) & 0xFFFFFFFFL;
        long s1 = (k1 * 0x82893933L) & 0xFFFFFFFFL;

        ArrayList<Long> list1 = new ArrayList<>();
        ArrayList<Long> list2 = new ArrayList<>();
        for (int idx = 0; idx < 14; idx++) {
            long[] pair = D_F[idx];
            long sVal = (idx % 2 == 0) ? s0 : s1;
            list1.add((pair[0] * sVal) & 0xFFFFFFFFL);
            list2.add(pair[1] & 0xFFFFFFFFL);
        }

        int rawLen = 1 + len;
        int paddedLen = (rawLen + 3) & -4;
        byte[] prefixed = new byte[paddedLen];
        System.arraycopy(msgBytes, 0, prefixed, 1, len);
        int numWords = paddedLen / 4;
        int evenWords = (numWords % 2 != 0) ? (numWords + 1) : numWords;
        long[] words = new long[evenWords];
        for (int j = 0; j < numWords; j++) {
            int b = j * 4;
            words[j] = (prefixed[b] & 0xFFL)
                    | ((prefixed[b + 1] & 0xFFL) << 8)
                    | ((prefixed[b + 2] & 0xFFL) << 16)
                    | ((prefixed[b + 3] & 0xFFL) << 24);
        }

        for (int i = 0; i < words.length; i++) {
            long wI = words[i];
            long kVal = (i % 2 == 0) ? k0 : k1;
            long v11 = wI * kVal;
            long v6 = dB(wI) * ((i % 2 == 0) ? 0xef0569fbL : 0xc31713dbL);
            if (i == 0) {
                v11 += s0 * 0xf2f90b1aL;
                v6 += 0x0b1a0000L;
            }
            list1.add(v11 & 0xFFFFFFFFL);
            list2.add(v6 & 0xFFFFFFFFL);
        }

        long acc5 = 0L;
        long acc7 = 0L;
        long acc22 = 0L;
        long lastV13 = 0L;
        for (int i = 0; i < list1.size(); i += 2) {
            long x0 = list1.get(i);
            long x1 = list1.get(i + 1);
            long y0 = list2.get(i);
            long y1 = list2.get(i + 1);

            long t0 = dB((y0 + x0) & 0xFFFFFFFFL);
            t0 = (t0 * 0x76f50f34L) & 0xFFFFFFFFL;
            t0 = ((dB(t0) * 0xc3efea97L) + t0) & 0xFFFFFFFFL;
            acc22 = (acc22 + t0) & 0xFFFFFFFFL;

            long t1 = dB((y1 + x1) & 0xFFFFFFFFL);
            t1 = (t1 * 0x1881ce3cL) & 0xFFFFFFFFL;
            t1 = ((dB(t1) * 0x35bd1ec9L) + t1) & 0xFFFFFFFFL;
            lastV13 = t1;
            acc22 = (acc22 + t1) & 0xFFFFFFFFL;

            acc5 = ((acc5 * k0) + x0) & 0xFFFFFFFFL;
            acc5 = (dB(acc5) * 0xcf98b111L) & 0xFFFFFFFFL;
            acc5 = (dB(acc5) * 0x87085b9fL) & 0xFFFFFFFFL;
            acc5 = (dB(acc5) * 0x12ceb96dL) & 0xFFFFFFFFL;
            acc5 = (dB(acc5) * 0x257e1d83L) & 0xFFFFFFFFL;
            acc7 = (acc7 + acc5) & 0xFFFFFFFFL;

            acc5 = ((acc5 * k1) + x1) & 0xFFFFFFFFL;
            acc5 = (dB(acc5) * 0xa27416f5L) & 0xFFFFFFFFL;
            acc5 = (dB(acc5) * 0xd38396ffL) & 0xFFFFFFFFL;
            acc5 = (dB(acc5) * 0x7c932b89L) & 0xFFFFFFFFL;
            acc5 = (dB(acc5) * 0xbfa49f69L) & 0xFFFFFFFFL;
            acc7 = (acc7 + acc5) & 0xFFFFFFFFL;
        }

        long outLo = (lastV13 ^ acc5) & 0xFFFFFFFFL;
        long outHi = (acc22 ^ acc7) & 0xFFFFFFFFL;
        byte[] prefix8 = new byte[] {
            (byte) (outLo & 0xFFL),
            (byte) ((outLo >>> 8) & 0xFFL),
            (byte) ((outLo >>> 16) & 0xFFL),
            (byte) ((outLo >>> 24) & 0xFFL),
            (byte) (outHi & 0xFFL),
            (byte) ((outHi >>> 8) & 0xFFL),
            (byte) ((outHi >>> 16) & 0xFFL),
            (byte) ((outHi >>> 24) & 0xFFL)
        };
        return bytesToHexUpper(prefix8) + "-" + bytesToHexUpper(digest32);
    }

    private static String bytesToHexUpper(byte[] bytes) {
        final String hex = "0123456789ABCDEF";
        StringBuilder sb = new StringBuilder(bytes.length * 2);
        for (byte b : bytes) {
            int v = b & 0xFF;
            sb.append(hex.charAt(v >>> 4));
            sb.append(hex.charAt(v & 0x0F));
        }
        return sb.toString();
    }

    private static String sha256Hex(String input) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            byte[] d = md.digest(input.getBytes(StandardCharsets.UTF_8));
            return bytesToHexUpper(d).toLowerCase(Locale.ROOT);
        } catch (Exception e) {
            return String.valueOf(input.hashCode());
        }
    }

    private static String isoTimestamp() {
        SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US);
        sdf.setTimeZone(TimeZone.getTimeZone("UTC"));
        return sdf.format(new Date());
    }

    private static String sanitizeSpeechText(String raw) {
        if (raw == null) return "";
        String trimmed = raw.replaceAll("[*_`#~>|]+", " ").replaceAll("\\s+", " ").trim();
        return trimmed.length() > 3600 ? trimmed.substring(0, 3600) : trimmed;
    }

    private static String escapeXml(String s) {
        StringBuilder sb = new StringBuilder(s.length() + 32);
        for (int i = 0; i < s.length(); i++) {
            char ch = s.charAt(i);
            switch (ch) {
                case '&': sb.append("&amp;"); break;
                case '<': sb.append("&lt;"); break;
                case '>': sb.append("&gt;"); break;
                case '"': sb.append("&quot;"); break;
                case '\'': sb.append("&apos;"); break;
                default:
                    if (ch >= 0x20 || ch == '\n' || ch == '\r' || ch == '\t') {
                        sb.append(ch);
                    }
                    break;
            }
        }
        return sb.toString();
    }
}
