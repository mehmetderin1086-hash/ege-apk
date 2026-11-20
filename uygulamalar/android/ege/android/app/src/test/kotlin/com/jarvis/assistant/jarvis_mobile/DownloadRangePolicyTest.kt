package com.jarvis.assistant.jarvis_mobile
import org.junit.Assert.assertEquals
import org.junit.Test
class DownloadRangePolicyTest {
    @Test fun validResume() { assertEquals(1000L, DownloadRangePolicy.validate(200, 206, "bytes 200-999/1000", 800)) }
    @Test fun ignoredRangeRestarts() { assertEquals(1000L, DownloadRangePolicy.validate(200, 200, null, 1000)) }
    @Test(expected = IllegalArgumentException::class) fun wrongOffsetRejected() { DownloadRangePolicy.validate(200, 206, "bytes 0-999/1000", 1000) }
    @Test(expected = IllegalArgumentException::class) fun truncatedRangeRejected() { DownloadRangePolicy.validate(200, 206, "bytes 200-299/1000", 100) }
    @Test(expected = IllegalArgumentException::class) fun wrongLengthRejected() { DownloadRangePolicy.validate(200, 206, "bytes 200-999/1000", 400) }
    @Test(expected = IllegalArgumentException::class) fun errorPageRejected() { DownloadRangePolicy.validate(0, 403, null, 100) }
}
