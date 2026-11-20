package com.jarvis.assistant.jarvis_mobile
import org.junit.Assert.*
import org.junit.Test
class WakeSpeechGateTest {
    @Test fun englishFallbackRecognizesObservedPronunciationWithoutBroadEggCommands() {
        for (text in listOf("Asistan", "assistant", "Asistan!")) {
            assertTrue(text, WakePhrasePolicy.matchesEnglishFallback(text))
        }
        for (text in listOf("egg", "hey", "Hey egg timer", "they ate an egg", "Hey Ece", "Hey Jarvis")) {
            assertFalse(text, WakePhrasePolicy.matchesEnglishFallback(text))
        }
        assertFalse(WakePhrasePolicy.needsEnglishFallback(true, 32000))
        assertFalse(WakePhrasePolicy.needsEnglishFallback(false, 1000))
        assertFalse(WakePhrasePolicy.needsEnglishFallback(false, 160000))
        assertTrue(WakePhrasePolicy.needsEnglishFallback(false, 64000))
    }
    @Test fun matchesOnlyWakeRequests() {
        for (s in listOf("Asistan", "Asistan saat kaç", "ASİSTAN")) assertTrue(s, WakePhrasePolicy.matches(s))
        for (s in listOf("merhaba", "hey nasılsın", "Hey Jarvis", "Jarvis", "Ege bölgesi", "Ege", "hey gece", "Hey Ece", "altyazı", "", "hey karpuz")) assertFalse(s, WakePhrasePolicy.matches(s))
    }
    @Test fun silenceNeverCreatesClip() {
        val g = WakeSpeechGate()
        repeat(100) { assertNull(g.accept(ByteArray(3200), 0.00001)) }
    }
    @Test fun steadyRoomNoiseSettlesAndLaterQuietSpeechIsStillCaptured() {
        val g = WakeSpeechGate()
        repeat(60) { g.accept(ByteArray(3200), 0.002) }
        repeat(100) { assertNull(g.accept(ByteArray(3200), 0.002)) }
        repeat(6) { assertNull(g.accept(ByteArray(3200), 0.008)) }
        repeat(4) { assertNull(g.accept(ByteArray(3200), 0.002)) }
        assertNotNull(g.accept(ByteArray(3200), 0.002))
    }
    @Test fun shortSpeechEndsAfterSilenceWithoutADeafCooldown() {
        val g = WakeSpeechGate()
        repeat(6) { assertNull(g.accept(ByteArray(3200), 0.01)) }
        repeat(4) { assertNull(g.accept(ByteArray(3200), 0.00001)) }
        assertEquals(11 * 3200, g.accept(ByteArray(3200), 0.00001)!!.size)
        repeat(6) { assertNull(g.accept(ByteArray(3200), 0.01)) }
        repeat(4) { assertNull(g.accept(ByteArray(3200), 0.00001)) }
        assertNotNull(g.accept(ByteArray(3200), 0.00001))
    }
    @Test fun continuousWindowsOverlapSoWakePhraseIsNotSplit() {
        val g = WakeSpeechGate()
        repeat(34) { assertNull(g.accept(ByteArray(3200), 0.01)) }
        assertEquals(35 * 3200, g.accept(ByteArray(3200), 0.01)!!.size)
        repeat(34) { assertNull(g.accept(ByteArray(3200), 0.01)) }
        assertEquals(43 * 3200, g.accept(ByteArray(3200), 0.01)!!.size)
    }
    @Test fun wakePhraseCanFollowPriorSpeechWithoutMatchingOrdinaryNameMentions() {
        assertFalse(WakePhrasePolicy.matches("Hey Ege"))
        assertFalse(WakePhrasePolicy.matches("asistanlık"))
        assertFalse(WakePhrasePolicy.matches("bu Ege hakkında"))
        assertFalse(WakePhrasePolicy.matches("hey karpuz"))
    }
    @Test fun busyAsrKeepsLatestClipAndRejectsOldSessionsAndExpiredAudio() {
        val q = WakeClipQueue()
        q.offer(WakeClipQueue.Clip(byteArrayOf(1), 1, "tiny", 0))
        q.offer(WakeClipQueue.Clip(byteArrayOf(2), 1, "tiny", 100))
        assertArrayEquals(byteArrayOf(2), q.take(1, 200)!!.pcm)
        assertNull(q.take(1, 200))
        q.offer(WakeClipQueue.Clip(byteArrayOf(3), 1, "tiny", 300))
        assertNull(q.take(2, 400))
        q.offer(WakeClipQueue.Clip(byteArrayOf(4), 2, "tiny", 500))
        assertNull(q.take(2, 9000))
        q.offer(WakeClipQueue.Clip(byteArrayOf(5), 2, "tiny", 9000))
        q.clear()
        assertFalse(q.hasPending())
    }
    @Test fun healthCheckRecoversStallsButNeverFightsOtherAppsMicrophoneOwnership() {
        assertFalse(WakeHealth.stalled(10000, 0, 0, 0, false))
        assertFalse(WakeHealth.stalled(20000, 0, 19900, 19500, false))
        assertTrue(WakeHealth.stalled(20000, 0, 19900, 10000, false))
        assertTrue(WakeHealth.stalled(20000, 0, 10000, 19500, false))
        assertFalse(WakeHealth.stalled(20000, 0, 10000, 10000, true))
    }
}
