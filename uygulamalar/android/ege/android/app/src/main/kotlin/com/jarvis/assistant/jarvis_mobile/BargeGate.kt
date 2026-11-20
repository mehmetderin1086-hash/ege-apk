package com.jarvis.assistant.jarvis_mobile

/** Conservative near-end speech gate, applied AFTER hardware echo cancellation. */
class BargeGate {
    private var elapsed = 0
    private var sustained = 0
    private var floor = 0.006
    var triggered = false
        private set

    fun process(rms: Double, milliseconds: Int = 20): Boolean {
        if (triggered) return false
        elapsed += milliseconds
        if (elapsed <= 500) {
            floor = floor * 0.9 + rms * 0.1
            return false
        }
        val threshold = maxOf(0.018, floor * 3.0)
        if (rms > threshold) sustained += milliseconds else {
            sustained = 0
            floor = floor * 0.98 + rms * 0.02
        }
        if (sustained < 180) return false
        triggered = true
        return true
    }
}
