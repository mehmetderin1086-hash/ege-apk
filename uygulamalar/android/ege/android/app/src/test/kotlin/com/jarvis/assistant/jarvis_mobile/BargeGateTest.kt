package com.jarvis.assistant.jarvis_mobile

import org.junit.Assert.*
import org.junit.Test

class BargeGateTest {
    @Test fun steadyEchoDoesNotInterrupt() {
        val gate = BargeGate()
        repeat(1000) { assertFalse(gate.process(0.012)) }
    }
    @Test fun shortClickDoesNotInterrupt() {
        val gate = BargeGate()
        repeat(30) { gate.process(0.004) }
        repeat(5) { assertFalse(gate.process(0.12)) }
        repeat(20) { assertFalse(gate.process(0.004)) }
        assertFalse(gate.triggered)
    }
    @Test fun sustainedNearEndTriggersExactlyOnce() {
        val gate = BargeGate()
        repeat(30) { gate.process(0.005) }
        var detections = 0
        repeat(30) { if (gate.process(0.08)) detections++ }
        assertEquals(1, detections)
        assertTrue(gate.triggered)
    }
    @Test fun newSessionDoesNotRetainOldDetection() {
        val first = BargeGate()
        repeat(30) { first.process(0.005) }
        repeat(20) { first.process(0.08) }
        assertTrue(first.triggered)
        val next = BargeGate()
        assertFalse(next.triggered)
        repeat(25) { assertFalse(next.process(0.08)) }
    }
}
