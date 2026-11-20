package com.jarvis.assistant.jarvis_mobile

/** A partial response is appendable only if it starts exactly at the stored offset and covers the remaining representation. */
object DownloadRangePolicy {
    fun validate(offset: Long, status: Int, range: String?, length: Long): Long {
        require(offset >= 0) { "Negatif dosya konumu" }
        if (status == 200) return length
        require(status == 206) { "HTTP $status" }
        val match = Regex("bytes (\\d+)-(\\d+)/(\\d+)").matchEntire(range ?: "")
            ?: throw IllegalArgumentException("Geçersiz Content-Range")
        val start = match.groupValues[1].toLong(); val end = match.groupValues[2].toLong(); val total = match.groupValues[3].toLong()
        require(start == offset && end >= start && total > end && end == total - 1) { "Sunucu beklenen dosya aralığını döndürmedi" }
        require(length < 0 || length == end - start + 1) { "Yanıt boyutu aralıkla uyuşmuyor" }
        return total
    }
}
