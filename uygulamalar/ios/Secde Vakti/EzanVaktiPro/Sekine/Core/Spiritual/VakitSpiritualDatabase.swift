import Foundation
import SwiftUI

/// Her namaz vakti için özel hazırlanan Ayet, Hadis, Dua, Sesli Tilavet ve Video paketi.
struct VakitSpiritualPacket: Identifiable, Hashable {
    let id: String
    let prayer: Prayer
    let badgeTitle: String
    let subtitle: String
    let arabicVerse: String
    let turkishVerse: String
    let verseTransliteration: String
    let verseSource: String
    let globalAyahNumber: Int
    let hadithArabic: String
    let hadithTurkish: String
    let hadithSource: String
    let duaTurkish: String
    let videoFileName: String
    let gradientColors: [UInt]
}

enum VakitSpiritualDatabase {
    static let packets: [VakitSpiritualPacket] = [
        // 1. İMSAK & SABAH VAKTİ
        VakitSpiritualPacket(
            id: "fajr-1",
            prayer: .fajr,
            badgeTitle: "İMSAK & SABAH VAKTİ",
            subtitle: "Seher Vakti · Meleklerin Şahit Olduğu Namaz",
            arabicVerse: "وَأَقِمِ الصَّلَاةَ طَرَفَيِ النَّهَارِ وَزُلَفًا مِّنَ اللَّيْلِ ۚ إِنَّ الْحَسَنَاتِ يُذْهِبْنَ السَّيِّئَاتِ",
            turkishVerse: "Gündüzün iki ucunda ve gecenin gündüze yakın saatlerinde namaz kıl. Şüphesiz iyilikler kötülükleri giderir. Bu, öğüt alanlar için bir hatırlatmadır.",
            verseTransliteration: "Ve ekımis salâte tarafeyin nehâri ve zülefen minel leyl, innel hasenâti yüzhibnes seyyiât.",
            verseSource: "Hûd Sûresi, 114. Ayet · İsrâ 78",
            globalAyahNumber: 1,
            hadithArabic: "رَكْعَتَا الْفَجْرِ خَيْرٌ مِنَ الدُّنْيَا وَمَا فِيهَا",
            hadithTurkish: "Sabah namazının iki rekât sünneti, dünya ve içindekilerden daha hayırlıdır. Sabah namazını kılan kimse Allah'ın himayesindedir.",
            hadithSource: "Müslim, Müsâfirîn 96",
            duaTurkish: "Allah'ım! Bu yeni günün evvelini salah ve huzur, ortasını kurtuluş, sonunu ise başarı ve mağfiret eyle.",
            videoFileName: "vakit_fajr",
            gradientColors: [0x0B162C, 0x1B3B6F]
        ),
        // 2. GÜNEŞ & İŞRAK VAKTİ
        VakitSpiritualPacket(
            id: "sunrise-1",
            prayer: .sunrise,
            badgeTitle: "GÜNEŞ & İŞRAK VAKTİ",
            subtitle: "Günün İlk Işıkları · Şükür, Zikir ve Bereket",
            arabicVerse: "اللَّهُ نُورُ السَّمَاوَاتِ وَالْأَرْضِ ۚ مَثَلُ نُورِهِ كَمِشْكَاةٍ فِيهَا مِصْبَاحٌ",
            turkishVerse: "Allah, göklerin ve yerin nûrudur. O’nun nûrunun temsili, içinde lamba bulunan bir kandillik gibidir. Allah dilediğini kendi nûruna iletir.",
            verseTransliteration: "Allâhu nûrus semâvâti vel ard, meselu nûrihî ke mişkâtin fîhâ misbâh.",
            verseSource: "Nûr Sûresi, 35. Ayet · Âyetel Kürsî",
            globalAyahNumber: 262,
            hadithArabic: "مَنْ صَلَّى الْغَدَاةَ فِي جَمَاعَةٍ ثُمَّ قَعَدَ يَذْكُرُ اللَّهَ حَتَّى تَطْلُعَ الشَّمْسُ ثُمَّ صَلَّى رَكْعَتَيْنِ كَانَتْ لَهُ كَأَجْرِ حَجَّةٍ وَعُمْرَةٍ تَامَّةٍ",
            hadithTurkish: "Kim sabah namazını cemaatle kılar, sonra güneş doğuncaya kadar oturup Allah’ı zikreder ve ardından iki rekât (işrak) namazı kılarsa, ona tam bir hac ve umre sevabı verilir.",
            hadithSource: "Tirmizî, Cum'a 59",
            duaTurkish: "Allah'ım! Senden faydalı ilim, helal ve temiz rızık, katında kabul olunan salih amel dilerim.",
            videoFileName: "vakit_sunrise",
            gradientColors: [0x2C1810, 0xD47A22]
        ),
        // 3. ÖĞLE VAKTİ
        VakitSpiritualPacket(
            id: "dhuhr-1",
            prayer: .dhuhr,
            badgeTitle: "ÖĞLE NAMAZI VAKTİ",
            subtitle: "Gün Ortası Huzur · Gökyüzü Kapılarının Açıldığı An",
            arabicVerse: "حَافِظُوا عَلَى الصَّلَوَاتِ وَالصَّلَاةِ الْوُسْطَىٰ وَقُومُوا لِلَّهِ قَانِتِينَ",
            turkishVerse: "Namazlara ve orta namaza devam edin. Allah’a gönülden boyun eğerek ve huşû içinde namaza durun.",
            verseTransliteration: "Hâfizû ales salavâti ves salâtil vustâ ve kûmû lillâhi kânitîn.",
            verseSource: "Bakara Sûresi, 238. Ayet",
            globalAyahNumber: 2,
            hadithArabic: "إِنَّ أَوَّلَ مَا يُحَاسَبُ بِهِ الْعَبْدُ يَوْمَ الْقِيَامَةِ مِنْ عَمَلِهِ صَلَاتُهُ",
            hadithTurkish: "Kulun kıyamet gününde amellerinden ilk hesaba çekileceği şey namazdır. Namazı tam ve düzgün olursa kurtuluşa erer ve kazanır.",
            hadithSource: "Tirmizî, Mevâkît 188",
            duaTurkish: "Rabbim! Beni ve soyumdan gelenleri namazı dosdoğru kılanlardan eyle. Rabbimiz, duamı kabul buyur.",
            videoFileName: "vakit_dhuhr",
            gradientColors: [0x0A2E36, 0x146B78]
        ),
        // 4. İKİNDİ VAKTİ
        VakitSpiritualPacket(
            id: "asr-1",
            prayer: .asr,
            badgeTitle: "İKİNDİ NAMAZI VAKTİ",
            subtitle: "Asr Vakti · Ömrün ve Zamanın Kıymeti",
            arabicVerse: "وَالْعَصْرِ ۝ إِنَّ الْإِنسَانَ لَفِي خُسْرٍ ۝ إِلَّا الَّذِينَ آمَنُوا وَعَمِلُوا الصَّالِحَاتِ وَتَوَاصَوْا بِالْحَقِّ وَتَوَاصَوْا بِالصَّبْرِ",
            turkishVerse: "Asra yemin olsun ki insan gerçekten ziyandadır. Ancak iman edip sâlih ameller işleyenler, birbirlerine hakkı ve sabrı tavsiye edenler müstesna.",
            verseTransliteration: "Vel asr. İnnel insâne lefî husr. İllellezîne âmenû ve amilus sâlihâti ve tevâsav bil hakkı ve tevâsav bis sabr.",
            verseSource: "Asr Sûresi, 1-3. Ayetler",
            globalAyahNumber: 3,
            hadithArabic: "لَنْ يَلِجَ النَّارَ أَحَدٌ صَلَّى قَبْلَ طُلُوعِ الشَّمْسِ وَقَبْلَ غُرُوبِهَا",
            hadithTurkish: "Güneş doğmadan önce (sabah) ve batmadan önce (ikindi) namaz kılan hiçbir kimse cehenneme girmez.",
            hadithSource: "Müslim, Mesâcid 213",
            duaTurkish: "Allah'ım! Ömrümüzün kalan kısmını geçen kısmından daha hayırlı ve bereketli kıl.",
            videoFileName: "vakit_asr",
            gradientColors: [0x2B1D0E, 0x9E6B24]
        ),
        // 5. AKŞAM VAKTİ
        VakitSpiritualPacket(
            id: "maghrib-1",
            prayer: .maghrib,
            badgeTitle: "AKŞAM NAMAZI VAKTİ",
            subtitle: "Gündüzün Uğurlanışı · Tesbih ve Mağfiret Vakti",
            arabicVerse: "فَسُبْحَانَ اللَّهِ حِينَ تُمْسُونَ وَحِينَ تُصْبِحُونَ ۝ وَلَهُ الْحَمْدُ فِي السَّمَاوَاتِ وَالْأَرْضِ",
            turkishVerse: "Haydi siz, akşama ulaştığınızda ve sabaha kavuştuğunuzda Allah’ı tesbih edin. Göklerde ve yerde hamd O’na mahsustur.",
            verseTransliteration: "Fe sübhânallâhi hîne tümsûne ve hîne tusbihûn. Ve lehül hamdü fis semâvâti vel ard.",
            verseSource: "Rûm Sûresi, 17-18. Ayetler",
            globalAyahNumber: 4,
            hadithArabic: "لَا تَزَالُ أُمَّتِي بِخَيْرٍ أَوْ قَالَ عَلَى الْفِطْرَةِ مَا لَمْ يُؤَخِّرُوا الْمَغْرِبَ إِلَى أَنْ تَشْتَبِكَ النُّجُومُ",
            hadithTurkish: "Ümmetim, akşam namazını yıldızlar birbirine karışacak kadar geciktirmedikleri müddetçe hayır ve fıtrat üzere olmaya devam ederler.",
            hadithSource: "Ebû Dâvûd, Salât 6",
            duaTurkish: "Rabbimiz! Bize dünyada da iyilik ve güzellik ver, ahirette de iyilik ver ve bizi ateş azabından koru.",
            videoFileName: "vakit_maghrib",
            gradientColors: [0x1E102B, 0x7A285B]
        ),
        // 6. YATSI VAKTİ
        VakitSpiritualPacket(
            id: "isha-1",
            prayer: .isha,
            badgeTitle: "YATSI NAMAZI VAKTİ",
            subtitle: "Gece Huzuru · Kalplerin Sekînet Bulduğu Vakit",
            arabicVerse: "الَّذِينَ آمَنُوا وَتَطْمَئِنُّ قُلُوبُهُم بِذِكْرِ اللَّهِ ۗ أَلَا بِذِكْرِ اللَّهِ تَطْمَئِنُّ الْقُلُوبُ",
            turkishVerse: "Onlar, iman eden ve kalpleri Allah’ı anmakla huzura kavuşan kimselerdir. Bilesiniz ki kalpler ancak Allah’ı anmakla huzur bulur.",
            verseTransliteration: "Ellezîne âmenû ve tatmeinnu kulûbühüm bi zikrillâh, elâ bi zikrillâhi tatmeinnul kulûb.",
            verseSource: "Ra'd Sûresi, 28. Ayet",
            globalAyahNumber: 5,
            hadithArabic: "مَنْ صَلَّى الْعِشَاءَ فِي جَمَاعَةٍ فَكَأَنَّمَا قَامَ نِصْفَ اللَّيْلِ وَمَنْ صَلَّى الصُّبْحَ فِي جَمَاعَةٍ فَكَأَنَّمَا صَلَّى اللَّيْلَ كُلَّهُ",
            hadithTurkish: "Kim yatsı namazını cemaatle kılarsa gecenin yarısını, sabah namazını da cemaatle kılarsa gecenin tamamını ibadetle geçirmiş gibi olur.",
            hadithSource: "Müslim, Mesâcid 260",
            duaTurkish: "Allah'ım! Senin adınla uyur ve Senin adınla uyanırım. Kalbimi dinin üzere sabit kıl.",
            videoFileName: "vakit_isha",
            gradientColors: [0x070B19, 0x152244]
        )
    ]

    static func packet(for prayer: Prayer) -> VakitSpiritualPacket {
        packets.first(where: { $0.prayer == prayer }) ?? packets[0]
    }
}
