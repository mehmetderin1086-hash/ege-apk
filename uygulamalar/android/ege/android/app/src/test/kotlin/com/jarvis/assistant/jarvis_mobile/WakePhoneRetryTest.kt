package com.jarvis.assistant.jarvis_mobile

import org.junit.Assert.*
import org.junit.Test

class WakePhoneRetryTest {
    @Test fun missingModelBacksOffButRetriesAfterDownloadOpportunity() {
        val retry = WakePhoneRetry()
        assertTrue(retry.ready(100))
        retry.complete("ERROR_13", 100)
        assertFalse(retry.ready(60099))
        assertTrue(retry.ready(60100))
        retry.complete("OK", 60200)
        assertTrue(retry.ready(60200))
    }
    @Test fun silenceDoesNotCauseADeafPeriodAndTransientErrorsAreBounded() {
        val retry = WakePhoneRetry()
        for (status in listOf("NO_SPEECH", "ERROR_6", "ERROR_7")) {
            retry.complete(status, 100)
            assertTrue(retry.ready(100))
        }
        retry.complete("ERROR_8", 100)
        assertFalse(retry.ready(5099))
        assertTrue(retry.ready(5100))
        retry.complete("SOURCE_UNSUPPORTED", 5200)
        assertFalse(retry.ready(6000))
        retry.reset()
        assertTrue(retry.ready(6000))
    }
}
