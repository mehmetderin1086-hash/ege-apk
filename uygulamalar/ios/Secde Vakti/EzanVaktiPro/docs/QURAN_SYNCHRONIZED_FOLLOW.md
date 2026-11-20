# Sesli tilavetle eşzamanlı ok takibi

Kur’an → Kelime → Okla dinle. Works on the currently displayed chapter/page/juz verses, in their displayed order. A saved verse is resumed only if present in that list.

The cursor follows AVAudioPlayer.currentTime, never a fixed reading timer. A 50 ms UI observation updates the cursor from that media time. Playback speed, pause/resume, scrubbing and word taps therefore use the same audio timebase. Ayah skipping, repeat counts (1/3/5), automatic word scrolling, and three explicitly paired reciters are supported. Another application audio action stops this player, and leaving the reader stops pending work.

Timing source: cpfair/quran-align, release-2016-11-24, CC BY 4.0. Bundled readers:
- Alafasy_128kbps
- Husary_64kbps
- Minshawy_Murattal_128kbps

Each table contains 6,236 ayah entries; corresponding recordings are fetched from the identically named EveryAyah directories. The app checks text word count and recording duration against the table before enabling word highlighting. Missing/mismatched timing means ayah audio without a guessed word cursor. Multiword spans highlight their whole range. Silence has no cursor. This is automated alignment, not a claim of human-reviewed boundaries for all Quran words.

Source statistics were removed to reduce bundle size. 55 invalid time spans (zero-length or reversed) were removed: 21 Alafasy, 15 Husary, 19 Minshawy. Retained indices/timestamps were not stretched or interpolated. Full license and attribution are bundled in QuranTiming, and an attribution link appears in playback settings.

Audio uses an atomic disk cache capped at 200 MiB with the next ayah prefetched; cached ayahs can be replayed offline. Initial playback requires network. Quran Foundation API attempts returned 403 in this session; the implementation uses bundled licensed alignment data instead of depending on that API.

Validation: interval boundaries, silence, grouped words, mismatched text, table integrity, playback cancellation state; UI test with real Fatiha playback showing the active word and pause/resume/stop; source recordings checked against Fatiha timing endpoints. Physical installation and app launch are separate from user listening acceptance.
