package com.jarvis.assistant.jarvis_mobile

import org.junit.Assert.*
import org.junit.Test
import com.jarvis.assistant.jarvis_mobile.PhoneScreenWait.State.*

class PhoneScreenWaitTest {
    @Test fun loadedScreenContinuesWithoutFixedSecondDelay() {
        val p = PhoneScreenWait(0, "search", true)
        assertEquals(WAIT, p.observe(0, "results", true, false))
        assertEquals(WAIT, p.observe(100, "results", true, false))
        assertEquals(READY, p.observe(300, "results", true, false))
    }
    @Test fun loadingAndNewResultsMustSettleAgain() {
        val p = PhoneScreenWait(0, "search", true)
        assertEquals(WAIT, p.observe(0, "old", true, false))
        assertEquals(WAIT, p.observe(200, "old", true, true))
        assertEquals(WAIT, p.observe(800, "new", true, false))
        assertEquals(WAIT, p.observe(900, "newer", true, false))
        assertEquals(READY, p.observe(1100, "newer", true, false))
    }
    @Test fun unchangedClickIsUncertainNotSuccessfulOrRetried() {
        val p = PhoneScreenWait(0, "screen", true)
        assertEquals(WAIT, p.observe(0, "screen", true, false))
        assertEquals(WAIT, p.observe(600, "screen", true, false))
        assertEquals(UNCHANGED, p.observe(700, "screen", true, false))
    }
    @Test fun missingAppAndEmptyScreensCannotBecomeReady() {
        val p = PhoneScreenWait(0, null, false)
        assertEquals(WAIT, p.observe(0, null, false, false))
        assertEquals(WAIT, p.observe(800, "empty", false, false))
        assertEquals(WAIT, p.observe(2000, "loading", true, true))
        assertEquals(TIMEOUT, p.observe(3000, "loading", true, true))
    }
    @Test fun observationOfAlreadyOpenScreenSettlesInTwoHundredMs() {
        val p = PhoneScreenWait(1000, null, false)
        assertEquals(WAIT, p.observe(1000, "form", true, false))
        assertEquals(READY, p.observe(1200, "form", true, false))
    }
    @Test fun movementHasBoundedDeadline() {
        val p = PhoneScreenWait(0, "old", true)
        for (i in 0..29) assertEquals(WAIT, p.observe(i * 100L, "frame$i", true, false))
        assertEquals(TIMEOUT, p.observe(3000, "frame30", true, false))
    }
    @Test fun invalidActionNeverLaunchesAnApp() {
        assertFalse(PhoneActionPolicy.valid("text", "", "", ""))
        assertFalse(PhoneActionPolicy.valid("submit", "", "", ""))
        assertFalse(PhoneActionPolicy.valid("click", "@1:0", "search", ""))
        assertFalse(PhoneActionPolicy.valid("open", "", "search", "https://example.com"))
        assertFalse(PhoneActionPolicy.valid("delete", "@1:0", "", ""))
        assertTrue(PhoneActionPolicy.valid("open", "", "Hayat Okumaları 191", ""))
        assertTrue(PhoneActionPolicy.valid("submit", "@2:0", "", ""))
    }
    @Test fun hangupMustObserveIdleBeforeReportingEnded() {
        assertNull(CallEndCheck.afterRequest(true, 100))
        assertEquals("ENDED", CallEndCheck.afterRequest(false, 300))
        assertEquals("UNVERIFIED", CallEndCheck.afterRequest(true, 2500))
        assertEquals("UNVERIFIED", CallEndCheck.afterRequest(null, 100))
    }
}
