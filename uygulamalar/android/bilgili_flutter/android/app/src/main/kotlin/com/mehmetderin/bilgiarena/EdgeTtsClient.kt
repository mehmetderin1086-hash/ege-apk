package com.mehmetderin.bilgiarena

import java.io.ByteArrayOutputStream
import java.io.EOFException
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.security.SecureRandom
import java.text.SimpleDateFormat
import java.util.ArrayList
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory

object EdgeTtsClient {
    const val DEFAULT_VOICE = "tr-TR-AhmetNeural"
    const val EMEL_VOICE = "tr-TR-EmelNeural"
    const val SYSTEM_VOICE = "system"

    private const val HOST = "speech.platform.bing.com"
    private const val PORT = 443
    private const val TRUSTED_CLIENT_TOKEN = "6A5AA1D4EAFF4E9FB37E23D68491D6F4"
    private const val SEC_MS_GEC_VERSION = "2-143.0.3650.75"
    private const val USER_AGENT =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0"

    private val D_A = longArrayOf(
        0x6a09e667L, 0xbb67ae85L, 0x3c6ef372L, 0xa54ff53aL,
        0x510e527fL, 0x9b05688cL, 0x1f83d9abL, 0x5be0cd19L
    )
    private val D_B = longArrayOf(
        0xfd9fbea2L, 0x91243ce7L, 0xbe499094L, 0xcd2e1e0aL,
        0x6c006f49L, 0x04bd35abL, 0xfeb0a7e4L, 0x03effbd2L
    )
    private val D_C = longArrayOf(
        0xeb24bf9eL, 0x1558691fL, 0xa0c09ee2L, 0x0cfa32baL,
        0xa622ee8cL, 0xd1dd9491L, 0xc0dd25a0L, 0xf9e70ab6L,
        0xf0c31573L, 0x7058ce4eL, 0x7188e606L, 0x00e5ab33L,
        0xd258b060L, 0x72766564L
    )
    private val D_D = longArrayOf(
        0x428a2f98L, 0x71374491L, 0xb5c0fbcfL, 0xe9b5dba5L, 0x3956c25bL, 0x59f111f1L, 0x923f82a4L, 0xab1c5ed5L,
        0xd807aa98L, 0x12835b01L, 0x243185beL, 0x550c7dc3L, 0x72be5d74L, 0x80deb1feL, 0x9bdc06a7L, 0xc19bf174L,
        0xe49b69c1L, 0xefbe4786L, 0x0fc19dc6L, 0x240ca1ccL, 0x2de92c6fL, 0x4a7484aaL, 0x5cb0a9dcL, 0x76f988daL,
        0x983e5152L, 0xa831c66dL, 0xb00327c8L, 0xbf597fc7L, 0xc6e00bf3L, 0xd5a79147L, 0x06ca6351L, 0x14292967L,
        0x27b70a85L, 0x2e1b2138L, 0x4d2c6dfcL, 0x53380d13L, 0x650a7354L, 0x766a0abbL, 0x81c2c92eL, 0x92722c85L,
        0xa2bfe8a1L, 0xa81a664bL, 0xc24b8b70L, 0xc76c51a3L, 0xd192e819L, 0xd6990624L, 0xf40e3585L, 0x106aa070L,
        0x19a4c116L, 0x1e376c08L, 0x2748774cL, 0x34b0bcb5L, 0x391c0cb3L, 0x4ed8aa4aL, 0x5b9cca4fL, 0x682e6ff3L,
        0x748f82eeL, 0x78a5636fL, 0x84c87814L, 0x8cc70208L, 0x90befffaL, 0xa4506cebL, 0xbef9a3f7L, 0xc67178f2L
    )
    private val D_E = LongArray(64) { idx -> if (idx == 14) 0xc9dc06a7L else D_D[idx] }

    private val D_F = arrayOf(
        longArrayOf(0xe82e91b1L, 0xb32700d0L),
        longArrayOf(0x44de24c6L, 0x88dff51dL),
        longArrayOf(0x3beb65bcL, 0x29514038L),
        longArrayOf(0xc89c5933L, 0xb328cbdfL),
        longArrayOf(0x8d1ec211L, 0xd405b4d5L),
        longArrayOf(0x314ef5d5L, 0x26e55f3cL),
        longArrayOf(0xe92491b1L, 0x607801c6L),
        longArrayOf(0xf0a5b9d5L, 0x82b2c1fbL),
        longArrayOf(0x06064cf3L, 0xfa51a3daL),
        longArrayOf(0xda79fa60L, 0x207cc464L),
        longArrayOf(0xbed20560L, 0x3c3c74f3L),
        longArrayOf(0x89f9c9f8L, 0xd2d14b61L),
        longArrayOf(0x35fa38c6L, 0xbb04a2c1L),
        longArrayOf(0xcb49e3c6L, 0xc5626167L)
    )

    private val secureRandom = SecureRandom()

    fun resolveVoice(preferredVoice: String?, languageTag: String?): String {
        val pref = preferredVoice?.trim().orEmpty()
        if (pref.equals(SYSTEM_VOICE, ignoreCase = true)) {
            return SYSTEM_VOICE
        }
        val baseTr = if (pref.isEmpty() || !pref.contains("Neural", ignoreCase = true)) {
            DEFAULT_VOICE
        } else {
            pref
        }
        val lang = (languageTag ?: "tr-TR").trim().lowercase(Locale.ROOT)
        if (!lang.startsWith("tr")) {
            return when {
                lang.startsWith("en") -> "en-US-ChristopherNeural"
                lang.startsWith("de") -> "de-DE-ConradNeural"
                lang.startsWith("fr") -> "fr-FR-HenriNeural"
                lang.startsWith("es") -> "es-ES-AlvaroNeural"
                lang.startsWith("it") -> "it-IT-DiegoNeural"
                lang.startsWith("ar") -> "ar-SA-HamedNeural"
                lang.startsWith("ru") -> "ru-RU-DmitryNeural"
                else -> baseTr
            }
        }
        return baseTr
    }

    fun synthesizeToFile(
        cacheDir: File,
        text: String,
        voiceName: String,
        rate: Float,
        pitch: Float = 1.0f
    ): File? {
        val clean = sanitizeSpeechText(text)
        if (clean.isEmpty()) return null

        val ratePct = ((rate.coerceIn(0.5f, 2.0f) - 1.0f) * 100f).toInt()
        val pitchHz = ((pitch.coerceIn(0.5f, 1.6f) - 1.0f) * 50f).toInt()
        val rateStr = if (ratePct >= 0) "+${ratePct}%" else "${ratePct}%"
        val pitchStr = if (pitchHz >= 0) "+${pitchHz}Hz" else "${pitchHz}Hz"

        val ttsCacheDir = File(cacheDir, "edge_tts_cache")
        if (!ttsCacheDir.exists()) {
            ttsCacheDir.mkdirs()
        }
        val cacheKey = sha256Hex("$voiceName|$rateStr|$pitchStr|$clean")
        val targetFile = File(ttsCacheDir, "tts_$cacheKey.mp3")
        if (targetFile.exists() && targetFile.length() > 128L) {
            return targetFile
        }

        val mp3Bytes = fetchMp3OverWebSocket(clean, voiceName, rateStr, pitchStr) ?: return null
        if (mp3Bytes.size <= 128) return null

        return try {
            val tmpFile = File(ttsCacheDir, "tts_${cacheKey}_${System.nanoTime()}.tmp")
            FileOutputStream(tmpFile).use { out ->
                out.write(mp3Bytes)
                out.flush()
            }
            if (!tmpFile.renameTo(targetFile)) {
                FileOutputStream(targetFile).use { out ->
                    out.write(mp3Bytes)
                    out.flush()
                }
                tmpFile.delete()
            }
            targetFile
        } catch (_: Exception) {
            null
        }
    }

    private fun fetchMp3OverWebSocket(
        cleanText: String,
        voiceName: String,
        rateStr: String,
        pitchStr: String
    ): ByteArray? {
        for (attempt in 0..1) {
            var socket: SSLSocket? = null
            try {
                val secMsGec = generateSecMsGec()
                val connId = UUID.randomUUID().toString().replace("-", "")
                val muid = UUID.randomUUID().toString().replace("-", "").uppercase(Locale.ROOT)
                val wsKeyBytes = ByteArray(16)
                secureRandom.nextBytes(wsKeyBytes)
                val wsKey = android.util.Base64.encodeToString(wsKeyBytes, android.util.Base64.NO_WRAP)

                val factory = SSLSocketFactory.getDefault() as SSLSocketFactory
                socket = factory.createSocket(HOST, PORT) as SSLSocket
                socket.soTimeout = 12000
                socket.startHandshake()

                val input = socket.inputStream
                val output = socket.outputStream

                val path = "/consumer/speech/synthesize/readaloud/edge/v1" +
                    "?TrustedClientToken=$TRUSTED_CLIENT_TOKEN" +
                    "&ConnectionId=$connId" +
                    "&Sec-MS-GEC=$secMsGec" +
                    "&Sec-MS-GEC-Version=$SEC_MS_GEC_VERSION"

                val handshakeReq = buildString {
                    append("GET $path HTTP/1.1\r\n")
                    append("Host: $HOST\r\n")
                    append("Pragma: no-cache\r\n")
                    append("Cache-Control: no-cache\r\n")
                    append("Origin: chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold\r\n")
                    append("User-Agent: $USER_AGENT\r\n")
                    append("Accept-Language: en-US,en;q=0.9\r\n")
                    append("Cookie: muid=$muid;\r\n")
                    append("Upgrade: websocket\r\n")
                    append("Connection: Upgrade\r\n")
                    append("Sec-WebSocket-Key: $wsKey\r\n")
                    append("Sec-WebSocket-Version: 13\r\n\r\n")
                }
                output.write(handshakeReq.toByteArray(StandardCharsets.UTF_8))
                output.flush()

                val statusLine = readHttpHeader(input)
                if (!statusLine.contains("101")) {
                    socket.close()
                    continue
                }

                val timestamp = isoTimestamp()
                val configPayload =
                    "X-Timestamp:$timestamp\r\n" +
                    "Content-Type:application/json; charset=utf-8\r\n" +
                    "Path:speech.config\r\n\r\n" +
                    "{\"context\":{\"synthesis\":{\"audio\":{\"metadataoptions\":{\"sentenceBoundaryEnabled\":\"false\",\"wordBoundaryEnabled\":\"false\"},\"outputFormat\":\"audio-24khz-48kbitrate-mono-mp3\"}}}}\r\n"
                sendWebSocketTextFrame(output, configPayload)

                val reqId = UUID.randomUUID().toString().replace("-", "")
                val langAttr = if (voiceName.length >= 5 && voiceName[2] == '-') {
                    voiceName.substring(0, 5)
                } else {
                    "tr-TR"
                }
                val ssmlPayload =
                    "X-RequestId:$reqId\r\n" +
                    "Content-Type:application/ssml+xml\r\n" +
                    "X-Timestamp:${timestamp}Z\r\n" +
                    "Path:ssml\r\n\r\n" +
                    "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='$langAttr'>" +
                    "<voice name='$voiceName'>" +
                    "<prosody pitch='$pitchStr' rate='$rateStr' volume='+0%'>" +
                    escapeXml(cleanText) +
                    "</prosody></voice></speak>"
                sendWebSocketTextFrame(output, ssmlPayload)

                val audioOut = ByteArrayOutputStream(32768)
                while (true) {
                    val frame = readWebSocketFrame(input) ?: break
                    val opcode = frame.first
                    val payload = frame.second
                    if (opcode == 1) {
                        val txt = String(payload, StandardCharsets.UTF_8)
                        if (txt.contains("Path:turn.end")) {
                            break
                        }
                    } else if (opcode == 2) {
                        if (payload.size > 2) {
                            val headerLen = ((payload[0].toInt() and 0xFF) shl 8) or (payload[1].toInt() and 0xFF)
                            if (payload.size >= 2 + headerLen) {
                                val headerStr = String(payload, 2, headerLen, StandardCharsets.UTF_8)
                                if (headerStr.contains("Path:audio")) {
                                    val audioOffset = 2 + headerLen
                                    val audioLen = payload.size - audioOffset
                                    if (audioLen > 0) {
                                        audioOut.write(payload, audioOffset, audioLen)
                                    }
                                }
                            }
                        }
                    } else if (opcode == 8) {
                        break
                    } else if (opcode == 9) {
                        sendWebSocketPongFrame(output, payload)
                    }
                }
                try {
                    socket.close()
                } catch (_: Exception) {}

                val bytes = audioOut.toByteArray()
                if (bytes.size > 128) {
                    return bytes
                }
            } catch (_: Exception) {
                try {
                    socket?.close()
                } catch (_: Exception) {}
            }
        }
        return null
    }

    private fun readHttpHeader(input: InputStream): String {
        val buf = ByteArrayOutputStream(512)
        var state = 0
        while (true) {
            val b = input.read()
            if (b == -1) break
            buf.write(b)
            state = when {
                state == 0 && b == '\r'.code -> 1
                state == 1 && b == '\n'.code -> 2
                state == 2 && b == '\r'.code -> 3
                state == 3 && b == '\n'.code -> 4
                b == '\r'.code -> 1
                else -> 0
            }
            if (state == 4 || buf.size() > 8192) break
        }
        val header = String(buf.toByteArray(), StandardCharsets.UTF_8)
        return header.lineSequence().firstOrNull().orEmpty()
    }

    private fun sendWebSocketTextFrame(output: OutputStream, text: String) {
        val payload = text.toByteArray(StandardCharsets.UTF_8)
        sendWebSocketFrame(output, 0x81, payload)
    }

    private fun sendWebSocketPongFrame(output: OutputStream, payload: ByteArray) {
        sendWebSocketFrame(output, 0x8A, payload)
    }

    private fun sendWebSocketFrame(output: OutputStream, firstByte: Int, payload: ByteArray) {
        val mask = ByteArray(4)
        secureRandom.nextBytes(mask)
        val n = payload.size
        val header = ByteArrayOutputStream(14)
        header.write(firstByte)
        when {
            n < 126 -> header.write(0x80 or n)
            n < 65536 -> {
                header.write(0x80 or 126)
                header.write((n ushr 8) and 0xFF)
                header.write(n and 0xFF)
            }
            else -> {
                header.write(0x80 or 127)
                val lenLong = n.toLong()
                for (i in 7 downTo 0) {
                    header.write(((lenLong ushr (i * 8)) and 0xFFL).toInt())
                }
            }
        }
        header.write(mask)
        val masked = ByteArray(n)
        for (i in 0 until n) {
            masked[i] = (payload[i].toInt() xor mask[i and 3].toInt()).toByte()
        }
        output.write(header.toByteArray())
        output.write(masked)
        output.flush()
    }

    private fun readWebSocketFrame(input: InputStream): Pair<Int, ByteArray>? {
        val b0 = input.read()
        if (b0 == -1) return null
        val b1 = input.read()
        if (b1 == -1) return null

        val opcode = b0 and 0x0F
        val masked = (b1 and 0x80) != 0
        var length = (b1 and 0x7F).toLong()
        if (length == 126L) {
            val lenBytes = readExact(input, 2)
            length = (((lenBytes[0].toInt() and 0xFF) shl 8) or (lenBytes[1].toInt() and 0xFF)).toLong()
        } else if (length == 127L) {
            val lenBytes = readExact(input, 8)
            length = 0L
            for (i in 0 until 8) {
                length = (length shl 8) or (lenBytes[i].toLong() and 0xFFL)
            }
        }
        val maskKey = if (masked) readExact(input, 4) else null
        val payload = readExact(input, length.toInt())
        if (masked && maskKey != null) {
            for (i in payload.indices) {
                payload[i] = (payload[i].toInt() xor maskKey[i and 3].toInt()).toByte()
            }
        }
        return Pair(opcode, payload)
    }

    private fun readExact(input: InputStream, len: Int): ByteArray {
        val out = ByteArray(len)
        var offset = 0
        while (offset < len) {
            val n = input.read(out, offset, len - offset)
            if (n < 0) throw EOFException("Unexpected EOF")
            offset += n
        }
        return out
    }

    private fun dB(x: Long): Long {
        val u = x and 0xFFFFFFFFL
        return ((u shl 16) or (u ushr 16)) and 0xFFFFFFFFL
    }

    private fun dD(x: Long): Long {
        val u = x and 0xFFFFFFFFL
        return ((u ushr 7) xor (u shl 25) xor (u ushr 18) xor (u shl 14) xor (u ushr 3)) and 0xFFFFFFFFL
    }

    private fun dE(x: Long): Long {
        val u = x and 0xFFFFFFFFL
        return ((u ushr 17) xor (u shl 15) xor (u ushr 19) xor (u shl 13) xor (u ushr 10)) and 0xFFFFFFFFL
    }

    private fun dA(w: ArrayList<Long>, startIdx: Int) {
        var idx = startIdx
        while (idx < 64) {
            val sum = (w[idx - 7] + dE(w[idx - 2]) + dD(w[idx - 15]) + w[idx - 16]) and 0xFFFFFFFFL
            w.add(sum)
            idx++
        }
    }

    private fun rotr32(x: Long, n: Int): Long {
        val u = x and 0xFFFFFFFFL
        return ((u ushr n) or (u shl (32 - n))) and 0xFFFFFFFFL
    }

    private fun dC(state: LongArray, w: ArrayList<Long>, startRound: Int): LongArray {
        var a = state[0] and 0xFFFFFFFFL
        var b = state[1] and 0xFFFFFFFFL
        var c = state[2] and 0xFFFFFFFFL
        var d = state[3] and 0xFFFFFFFFL
        var e = state[4] and 0xFFFFFFFFL
        var f = state[5] and 0xFFFFFFFFL
        var g = state[6] and 0xFFFFFFFFL
        var h = state[7] and 0xFFFFFFFFL
        val k = if (startRound == 14) D_E else D_D

        for (r in startRound until 64) {
            val s1 = rotr32(e, 6) xor rotr32(e, 11) xor rotr32(e, 25)
            val ch = g xor (e and (f xor g))
            val temp1 = (h + s1 + ch + k[r] + w[r]) and 0xFFFFFFFFL
            val s0 = rotr32(a, 2) xor rotr32(a, 13) xor rotr32(a, 22)
            val maj = (a and b) or (c and (a or b))
            val newA = (temp1 + s0 + maj) and 0xFFFFFFFFL
            val newE = (d + temp1) and 0xFFFFFFFFL
            h = g
            g = f
            f = e
            e = newE
            d = c
            c = b
            b = a
            a = newA
        }
        return longArrayOf(a, b, c, d, e, f, g, h)
    }

    fun generateSecMsGec(offsetSeconds: Long = 0L): String {
        var sec = (System.currentTimeMillis() / 1000L) + offsetSeconds
        sec += 11644473600L
        sec -= (sec % 300L)
        val ticks = sec * 10000000L
        val msgBytes = "$ticks$TRUSTED_CLIENT_TOKEN".toByteArray(StandardCharsets.UTF_8)
        val len = msgBytes.size
        val totalLen = len + 57
        var padZeros = (55 - totalLen) % 64
        if (padZeros < 0) padZeros += 64
        val v1 = len - 6 + padZeros
        val tailLen = v1 + 8
        val tail = ByteArray(tailLen)
        System.arraycopy(msgBytes, 7, tail, 0, len - 7)
        tail[len - 7] = (-128).toByte()
        val bitLen = totalLen.toLong() * 8L
        for (i in 0 until 8) {
            tail[v1 + i] = ((bitLen ushr ((7 - i) * 8)) and 0xFFL).toByte()
        }

        val w = ArrayList<Long>(64)
        for (i in 0 until 14) {
            w.add(0L)
        }
        w.add(
            ((msgBytes[0].toLong() and 0xFFL) shl 16) or
                ((msgBytes[1].toLong() and 0xFFL) shl 8) or
                (msgBytes[2].toLong() and 0xFFL)
        )
        w.add(
            ((msgBytes[3].toLong() and 0xFFL) shl 24) or
                ((msgBytes[4].toLong() and 0xFFL) shl 16) or
                ((msgBytes[5].toLong() and 0xFFL) shl 8) or
                (msgBytes[6].toLong() and 0xFFL)
        )
        for (i in 16 until 30) {
            var v = D_C[i - 16]
            if (i - 2 >= 14) {
                var t = dE(w[i - 2])
                if (i == 16) t = t xor 0x000b92c0L
                v += t
            }
            if (i - 7 >= 14) {
                v += w[i - 7]
            }
            if (i - 15 >= 14) {
                var t = dD(w[i - 15])
                if (i == 29) t = t xor 0x059c0b80L
                v += t
            }
            w.add(v and 0xFFFFFFFFL)
        }
        val val30 = (w[23] + dE(w[28]) + dD(w[15]) + w[14] + 0xc9dc06a7L - D_D[14]) and 0xFFFFFFFFL
        w.add(val30)
        dA(w, 31)
        val out0 = dC(D_B, w, 14)
        var state = LongArray(8) { j -> (D_A[j] + out0[j]) and 0xFFFFFFFFL }

        var offset = 0
        while (offset < tail.size) {
            val w2 = ArrayList<Long>(64)
            for (j in 0 until 16) {
                val base = offset + j * 4
                val word = ((tail[base].toLong() and 0xFFL) shl 24) or
                    ((tail[base + 1].toLong() and 0xFFL) shl 16) or
                    ((tail[base + 2].toLong() and 0xFFL) shl 8) or
                    (tail[base + 3].toLong() and 0xFFL)
                w2.add(word)
            }
            dA(w2, 16)
            val outChunk = dC(state, w2, 0)
            state = LongArray(8) { j -> (state[j] + outChunk[j]) and 0xFFFFFFFFL }
            offset += 64
        }

        val digest32 = ByteArray(32)
        for (j in 0 until 8) {
            val word = state[j]
            val base = j * 4
            digest32[base] = ((word ushr 24) and 0xFFL).toByte()
            digest32[base + 1] = ((word ushr 16) and 0xFFL).toByte()
            digest32[base + 2] = ((word ushr 8) and 0xFFL).toByte()
            digest32[base + 3] = (word and 0xFFL).toByte()
        }

        val k0 = ((digest32[0].toLong() and 0xFFL) or
            ((digest32[1].toLong() and 0xFFL) shl 8) or
            ((digest32[2].toLong() and 0xFFL) shl 16) or
            ((digest32[3].toLong() and 0xFFL) shl 24)) or 1L
        val k1 = ((digest32[4].toLong() and 0xFFL) or
            ((digest32[5].toLong() and 0xFFL) shl 8) or
            ((digest32[6].toLong() and 0xFFL) shl 16) or
            ((digest32[7].toLong() and 0xFFL) shl 24)) or 1L

        val s0 = (k0 * 0x82893933L) and 0xFFFFFFFFL
        val s1 = (k1 * 0x82893933L) and 0xFFFFFFFFL

        val list1 = ArrayList<Long>()
        val list2 = ArrayList<Long>()
        for (idx in 0 until 14) {
            val pair = D_F[idx]
            val sVal = if (idx % 2 == 0) s0 else s1
            list1.add((pair[0] * sVal) and 0xFFFFFFFFL)
            list2.add(pair[1] and 0xFFFFFFFFL)
        }

        val rawLen = 1 + len
        val paddedLen = (rawLen + 3) and -4
        val prefixed = ByteArray(paddedLen)
        System.arraycopy(msgBytes, 0, prefixed, 1, len)
        val numWords = paddedLen / 4
        val evenWords = if (numWords % 2 != 0) numWords + 1 else numWords
        val words = LongArray(evenWords)
        for (j in 0 until numWords) {
            val b = j * 4
            words[j] = (prefixed[b].toLong() and 0xFFL) or
                ((prefixed[b + 1].toLong() and 0xFFL) shl 8) or
                ((prefixed[b + 2].toLong() and 0xFFL) shl 16) or
                ((prefixed[b + 3].toLong() and 0xFFL) shl 24)
        }

        for (i in words.indices) {
            val wI = words[i]
            val kVal = if (i % 2 == 0) k0 else k1
            var v11 = wI * kVal
            var v6 = dB(wI) * (if (i % 2 == 0) 0xef0569fbL else 0xc31713dbL)
            if (i == 0) {
                v11 += s0 * 0xf2f90b1aL
                v6 += 0x0b1a0000L
            }
            list1.add(v11 and 0xFFFFFFFFL)
            list2.add(v6 and 0xFFFFFFFFL)
        }

        var acc5 = 0L
        var acc7 = 0L
        var acc22 = 0L
        var lastV13 = 0L
        var i = 0
        while (i < list1.size) {
            val x0 = list1[i]
            val x1 = list1[i + 1]
            val y0 = list2[i]
            val y1 = list2[i + 1]

            var t0 = dB((y0 + x0) and 0xFFFFFFFFL)
            t0 = (t0 * 0x76f50f34L) and 0xFFFFFFFFL
            t0 = ((dB(t0) * 0xc3efea97L) + t0) and 0xFFFFFFFFL
            acc22 = (acc22 + t0) and 0xFFFFFFFFL

            var t1 = dB((y1 + x1) and 0xFFFFFFFFL)
            t1 = (t1 * 0x1881ce3cL) and 0xFFFFFFFFL
            t1 = ((dB(t1) * 0x35bd1ec9L) + t1) and 0xFFFFFFFFL
            lastV13 = t1
            acc22 = (acc22 + t1) and 0xFFFFFFFFL

            acc5 = ((acc5 * k0) + x0) and 0xFFFFFFFFL
            acc5 = (dB(acc5) * 0xcf98b111L) and 0xFFFFFFFFL
            acc5 = (dB(acc5) * 0x87085b9fL) and 0xFFFFFFFFL
            acc5 = (dB(acc5) * 0x12ceb96dL) and 0xFFFFFFFFL
            acc5 = (dB(acc5) * 0x257e1d83L) and 0xFFFFFFFFL
            acc7 = (acc7 + acc5) and 0xFFFFFFFFL

            acc5 = ((acc5 * k1) + x1) and 0xFFFFFFFFL
            acc5 = (dB(acc5) * 0xa27416f5L) and 0xFFFFFFFFL
            acc5 = (dB(acc5) * 0xd38396ffL) and 0xFFFFFFFFL
            acc5 = (dB(acc5) * 0x7c932b89L) and 0xFFFFFFFFL
            acc5 = (dB(acc5) * 0xbfa49f69L) and 0xFFFFFFFFL
            acc7 = (acc7 + acc5) and 0xFFFFFFFFL

            i += 2
        }

        val outLo = (lastV13 xor acc5) and 0xFFFFFFFFL
        val outHi = (acc22 xor acc7) and 0xFFFFFFFFL
        val prefix8 = byteArrayOf(
            (outLo and 0xFFL).toByte(),
            ((outLo ushr 8) and 0xFFL).toByte(),
            ((outLo ushr 16) and 0xFFL).toByte(),
            ((outLo ushr 24) and 0xFFL).toByte(),
            (outHi and 0xFFL).toByte(),
            ((outHi ushr 8) and 0xFFL).toByte(),
            ((outHi ushr 16) and 0xFFL).toByte(),
            ((outHi ushr 24) and 0xFFL).toByte()
        )
        return "${bytesToHexUpper(prefix8)}-${bytesToHexUpper(digest32)}"
    }

    private fun bytesToHexUpper(bytes: ByteArray): String {
        val hexChars = "0123456789ABCDEF"
        val sb = StringBuilder(bytes.size * 2)
        for (b in bytes) {
            val v = b.toInt() and 0xFF
            sb.append(hexChars[v ushr 4])
            sb.append(hexChars[v and 0x0F])
        }
        return sb.toString()
    }

    private fun sha256Hex(input: String): String {
        val md = MessageDigest.getInstance("SHA-256")
        val digest = md.digest(input.toByteArray(StandardCharsets.UTF_8))
        return bytesToHexUpper(digest).lowercase(Locale.ROOT)
    }

    private fun isoTimestamp(): String {
        val sdf = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        sdf.timeZone = TimeZone.getTimeZone("UTC")
        return sdf.format(Date())
    }

    private fun sanitizeSpeechText(raw: String): String {
        val trimmed = raw
            .replace(Regex("[*_`#~>|]+"), " ")
            .replace(Regex("\\s+"), " ")
            .trim()
        return if (trimmed.length > 3600) trimmed.substring(0, 3600) else trimmed
    }

    private fun escapeXml(s: String): String {
        val sb = StringBuilder(s.length + 32)
        for (ch in s) {
            when (ch) {
                '&' -> sb.append("&amp;")
                '<' -> sb.append("&lt;")
                '>' -> sb.append("&gt;")
                '"' -> sb.append("&quot;")
                '\'' -> sb.append("&apos;")
                else -> if (ch.code >= 0x20 || ch == '\n' || ch == '\r' || ch == '\t') {
                    sb.append(ch)
                }
            }
        }
        return sb.toString()
    }
}
