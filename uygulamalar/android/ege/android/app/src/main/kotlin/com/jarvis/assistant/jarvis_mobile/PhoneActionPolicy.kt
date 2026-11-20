package com.jarvis.assistant.jarvis_mobile

/** Validate before any activity launch or accessibility action. */
internal object PhoneActionPolicy {
    fun valid(action: String, target: String, query: String, url: String): Boolean {
        if (action !in setOf("open", "click", "long_click", "text", "scroll", "scroll_back", "back", "submit")) return false
        if (action in setOf("click", "long_click", "text", "submit") && target.isBlank()) return false
        if (action != "open" && (query.isNotEmpty() || url.isNotEmpty())) return false
        if (query.isNotEmpty() && url.isNotEmpty()) return false
        return query.length <= 1000 && url.length <= 8192
    }
}
