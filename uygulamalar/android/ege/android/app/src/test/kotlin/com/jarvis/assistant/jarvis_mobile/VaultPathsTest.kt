package com.jarvis.assistant.jarvis_mobile

import org.junit.Assert.*
import org.junit.Test

class VaultPathsTest {
    @Test fun exportsStayInsideManagedFolder() {
        assertTrue(VaultPaths.valid("Ege/Sohbetler/session-1.md"))
        for (path in listOf("../private.md", "Ege/../private.md", "Ege//file.md", "Ege/file.exe", "Ege/notes\\file.md", "/Ege/file.md")) assertFalse(path, VaultPaths.valid(path))
    }
    @Test fun turkishSearchTermsAreBoundedAndNormalized() {
        assertEquals(listOf("megaboz", "fotograflari"), VaultPaths.terms("Bana Megaboz fotoğrafları"))
        assertTrue(VaultPaths.terms("a b c").isEmpty())
    }
    @Test fun longPressCannotRunWithoutATargetOrWithNavigationArguments() {
        assertFalse(PhoneActionPolicy.valid("long_click", "", "", ""))
        assertFalse(PhoneActionPolicy.valid("long_click", "@1:2", "query", ""))
        assertTrue(PhoneActionPolicy.valid("long_click", "@1:2", "", ""))
    }
}
