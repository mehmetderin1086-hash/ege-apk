package com.jarvis.assistant.jarvis_mobile

/** Bounded, monotonic screen observation; READY is not proof of task completion. */
internal class PhoneScreenWait(
    private val startedAt: Long,
    private val baseline: String?,
    private val expectChange: Boolean,
    private val timeoutMs: Long = 3000,
) {
    enum class State { WAIT, READY, UNCHANGED, TIMEOUT }
    private var last: String? = null
    private var stableSince = startedAt
    private var changed = false

    fun observe(now: Long, fingerprint: String?, hasControls: Boolean, loading: Boolean): State {
        if (now - startedAt >= timeoutMs) return State.TIMEOUT
        if (fingerprint == null || !hasControls || loading) {
            last = null
            stableSince = now
            return State.WAIT
        }
        if (last != fingerprint) {
            last = fingerprint
            stableSince = now
        }
        changed = fingerprint != baseline
        if (now - stableSince < 200) return State.WAIT
        if (!expectChange && now - startedAt >= 200) return State.READY
        if (changed && now - startedAt >= 250) return State.READY
        // No visible change: report uncertainty, never automatically repeat a click.
        return if (now - startedAt >= 650) State.UNCHANGED else State.WAIT
    }
}
