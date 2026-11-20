package com.jarvis.assistant.jarvis_mobile

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class WhisperDisabledTest {
    @Test fun legacyEntryPointCannotLoadOrRunWhisper() {
        val result = JarvisWhisper.transcribe("missing-model", byteArrayOf(), "tr", true, "", 1)
        assertEquals(false, result["ok"])
        assertTrue(result["error"].toString().contains("devre dışı"))
    }
}
