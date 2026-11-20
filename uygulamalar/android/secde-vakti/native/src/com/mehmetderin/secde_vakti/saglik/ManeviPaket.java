package com.mehmetderin.secde_vakti.saglik;

import android.content.Context;
import android.content.Intent;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.HapticFeedbackConstants;
import android.view.View;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Calendar;
import java.util.List;

/**
 * Vakte Özel Manevî Paket:
 *  - Bulunulan vakit penceresine göre dinamik başlıklı özet kart (Vakitler sekmesi için)
 *  - Tam alt sayfa: Vaktin Âyeti (DailyVerses.json), Günün Sahih Hadîs-i Şerîfi (30 hadis + yenile),
 *    Vaktin Nebevî Duâsı ve Sabah/Akşam Ezkârı (Duas.json + Arapça/okunuş/meal),
 *    Günün Esmâü'l-Hüsnâ'sı & Zikirmatik entegrasyonu.
 */
public final class ManeviPaket {

    /** Kart/metin paylaşım geri çağrısı. */
    public static interface PaylasEylem {
        void paylas(String arapca, String metin, String kaynak);
    }

    private static final String[] VAKIT_PAKET_BASLIKLARI = {
            "SEHER VAKTİ MANEVÎ PAKETİ",      // 0: fajr (İmsak – Güneş)
            "KUŞLUK VAKTİ MANEVÎ PAKETİ",     // 1: sunrise (Güneş – Öğle)
            "ÖĞLE VAKTİ MANEVÎ PAKETİ",       // 2: dhuhr (Öğle – İkindi)
            "İKİNDİ VAKTİ MANEVÎ PAKETİ",     // 3: asr (İkindi – Akşam)
            "AKŞAM VAKTİ MANEVÎ PAKETİ",      // 4: maghrib (Akşam – Yatsı)
            "GECE VE TEHECCÜD PAKETİ"         // 5: isha (Yatsı – İmsak)
    };

    /** EsmaulHusna.json içindeki 100 ismin birebir sırasıyla harekeli Arapça hat karşılıkları. */
    private static final String[] ESMA_ARAPCA = {
            "اللّٰهُ", "الرَّحْمٰنُ", "الرَّحِيمُ", "الْمَلِكُ", "الْقُدُّوسُ",
            "السَّلَامُ", "الْمُؤْمِنُ", "الْمُهَيْمِنُ", "الْعَزِيزُ", "الْجَبَّارُ",
            "الْمُتَكَبِّرُ", "الْخَالِقُ", "الْبَارِئُ", "الْمُصَوِّرُ", "الْغَفَّارُ",
            "الْقَهَّارُ", "الْوَهَّابُ", "الرَّزَّاقُ", "الْفَتَّاحُ", "الْعَلِيمُ",
            "الْقَابِضُ", "الْبَاسِطُ", "الْخَافِضُ", "الرَّافِعُ", "الْمُعِزُّ",
            "الْمُذِلُّ", "السَّمِيعُ", "الْبَصِيرُ", "الْحَكَمُ", "الْعَدْلُ",
            "اللَّطِيفُ", "الْخَبِيرُ", "الْحَلِيمُ", "الْعَظِيمُ", "الْغَفُورُ",
            "الشَّكُورُ", "الْعَلِيُّ", "الْكَبِيرُ", "الْحَفِيظُ", "الْمُقِيتُ",
            "الْحَسِيبُ", "الْجَلِيلُ", "الْكَرِيمُ", "الرَّقِيبُ", "الْمُجِيبُ",
            "الْوَاسِعُ", "الْحَكِيمُ", "الْوَدُودُ", "الْمَجِيدُ", "الْبَاعِثُ",
            "الشَّهِيدُ", "الْحَقُّ", "الْوَكِيلُ", "الْقَوِيُّ", "الْمَتِينُ",
            "الْوَلِيُّ", "الْحَمِيدُ", "الْمُحْصِي", "الْمُبْدِئُ", "الْمُعِيدُ",
            "الْمُحْيِي", "الْمُمِيتُ", "الْحَيُّ", "الْقَيُّومُ", "الْوَاجِدُ",
            "الْمَاجِدُ", "الْوَاحِدُ", "الْأَحَدُ", "الصَّمَدُ", "الْقَادِرُ",
            "الْمُقْتَدِرُ", "الْمُقَدِّمُ", "الْمُؤَخِّرُ", "الْأَوَّلُ", "الْآخِرُ",
            "الظَّاهِرُ", "الْبَاطِنُ", "الْوَالِي", "الْمُتَعَالِي", "الْبَرُّ",
            "التَّوَّابُ", "الْمُنْتَقِمُ", "الْعَفُوُّ", "الرَّؤُوفُ", "مَالِكُ الْمُلْكِ",
            "ذُو الْجَلَالِ وَالْإِكْرَامِ", "الْمُقْسِطُ", "الْجَامِعُ", "الْغَنِيُّ", "الْمُغْنِي",
            "الْمَانِعُ", "الضَّارُّ", "النَّافِعُ", "النُّورُ", "الْهَادِي",
            "الْبَدِيعُ", "الْبَاقِي", "الْوَارِثُ", "الرَّشِيدُ", "الصَّبُورُ"
    };

    /** JSON okunamazsa devreye giren yerleşik Esmâ yedekleri {ad, anlam}. */
    private static final String[][] ESMA_YEDEK = {
            {"Allah", "Varlığı zorunlu olan ve bütün övgülere lâyık bulunan yüce zât."},
            {"Er-Rahmân", "Dünyada bütün mahlûkata merhamet eden."},
            {"Er-Rahîm", "Âhirette yalnız mü'minlere sonsuz şefkat ve merhamet eden."},
            {"Es-Selâm", "Her türlü tehlikeden selâmete çıkaran, kalplere esenlik veren."},
            {"El-Fettâh", "Her türlü zorluğu açan ve hayır kapılarını aralayan."},
            {"Er-Rezzâk", "Bütün mahlûkatın maddî ve mânevî rızkını ihsân eden."},
            {"El-Latîf", "En ince işleri bilen, kullarına sezdirmeden lütuf ve ihsânda bulunan."},
            {"El-Vedûd", "Sâlih kullarını çok seven ve sevilmeye en lâyık olan."},
            {"El-Vekîl", "Kendisine tevekkül edenlerin işlerini en güzel biçimde yoluna koyan."},
            {"El-Hayy", "Ezeli ve ebedî diri olan, her şeye hayat veren."},
            {"El-Kayyûm", "Varlığı kendinden olan, gökleri ve yeri ayakta tutan."},
            {"Eş-Şekûr", "Az bir ibâdete ve şükre kat kat mükâfat ihsân eden."}
    };

    /**
     * Buhârî, Müslim, Tirmizî ve Riyâzü's-Sâlihîn'den seçilmiş 30 sahih hadîs-i şerîf:
     * {kısa Arapça ibâre, Türkçe metin, kaynak}.
     */
    private static final String[][] SAHIH_HADISLER = {
            {"إِنَّمَا الْأَعْمَالُ بِالنِّيَّاتِ",
                    "Ameller ancak niyetlere göredir ve herkese niyet ettiği şey vardır.",
                    "Buhârî, Bed'ü'l-Vahy 1; Müslim, İmâre 155"},
            {"رَكْعَتَا الْفَجْرِ خَيْرٌ مِنَ الدُّنْيَا وَمَا فِيهَا",
                    "Sabah namazının iki rek'at sünneti, dünya ve içindekilerden daha hayırlıdır.",
                    "Müslim, Müsâfirîn 96; Tirmizî, Salât 190"},
            {"مَنْ صَلَّى الْبَرْدَيْنِ دَخَلَ الْجَنَّةَ",
                    "Serinlik vakitlerinin iki namazını (sabah ve ikindi namazlarını) vaktinde kılan kimse cennete girer.",
                    "Buhârî, Mevâkît 26; Müslim, Mesâcid 215"},
            {"الطُّهُورُ شَطْرُ الْإِيمَانِ وَالْحَمْدُ لِلّٰهِ تَمْلَأُ الْمِيزَانَ",
                    "Temizlik îmânın yarısıdır. 'Elhamdülillah' mîzânı doldurur; 'Sübhânallah ve Elhamdülillah' ise göklerle yer arasını doldurur.",
                    "Müslim, Tahâret 1; Riyâzü's-Sâlihîn 25"},
            {"خَيْرُكُمْ مَنْ تَعَلَّمَ الْقُرْآنَ وَعَلَّمَهُ",
                    "Sizin en hayırlınız, Kur'ân-ı Kerîm'i öğrenen ve öğreteninizdir.",
                    "Buhârî, Fedâilü'l-Kur'ân 21; Tirmizî, Fedâilü'l-Kur'ân 15"},
            {"الدُّعَاءُ هُوَ الْعِبَادَةُ",
                    "Duâ, ibâdetin tâ kendisidir (özüdür).",
                    "Tirmizî, Tefsîru'l-Kur'ân 2; Riyâzü's-Sâlihîn 1465"},
            {"كَلِمَتَانِ خَفِيفَتَانِ عَلَى اللِّسَانِ ثَقِيلَتَانِ فِي الْمِيزَانِ",
                    "Dile hafif, mîzanda ağır ve Rahmân'a çok sevimli iki söz vardır: Sübhânallâhi ve bihamdihî, Sübhânallâhi'l-azîm.",
                    "Buhârî, Daavât 65; Müslim, Zikir 31"},
            {"أَقْرَبُ مَا يَكُونُ الْعَبْدُ مِنْ رَبِّهِ وَهُوَ سَاجِدٌ",
                    "Kulun Rabbine en yakın olduğu hâl secde hâlidir; öyleyse secdede duâyı çoğaltın.",
                    "Müslim, Salât 215; Riyâzü's-Sâlihîn 1428"},
            {"الْكَلِمَةُ الطَّيِّبَةُ صَدَقَةٌ",
                    "Güzel söz sadakadır; namaza giderken atılan her adım sadakadır.",
                    "Buhârî, Edeb 34; Müslim, Zekât 56"},
            {"تَبَسُّمُكَ فِي وَجْهِ أَخِيكَ لَكَ صَدَقَةٌ",
                    "Mü'min kardeşinin yüzüne tebessüm etmen senin için bir sadakadır.",
                    "Tirmizî, Birr 36; Riyâzü's-Sâlihîn 887"},
            {"مَنْ سَلَكَ طَرِيقًا يَلْتَمِسُ فِيهِ عِلْمًا سَهَّلَ اللّٰهُ لَهُ طَرِيقًا إِلَى الْجَنَّةِ",
                    "Kim ilim öğrenmek için bir yola girerse, Allah ona cennete giden yolu kolaylaştırır.",
                    "Müslim, Zikir 38; Tirmizî, İlim 2"},
            {"يَسِّرُوا وَلَا تُعَسِّرُوا وَبَشِّرُوا وَلَا تُنَفِّرُوا",
                    "Kolaylaştırınız, zorlaştırmayınız; müjdeleyiniz, nefret ettirmeyiniz.",
                    "Buhârî, İlim 11; Müslim, Cihâd 6"},
            {"أَحَبُّ الْأَعْمَالِ إِلَى اللّٰهِ أَدْوَمُهَا وَإِنْ قَلَّ",
                    "Allah katında amellerin en sevimlisi, az da olsa devamlı yapılanıdır.",
                    "Buhârî, Rikâk 18; Müslim, Müsâfirîn 218"},
            {"الرَّاحِمُونَ يَرْحَمُهُمُ الرَّحْمٰنُ",
                    "Merhamet edenlere Rahmân olan Allah merhamet eder. Yeryüzündekilere merhamet edin ki göktekiler de size merhamet etsin.",
                    "Tirmizî, Birr 16; Riyâzü's-Sâlihîn 225"},
            {"لَا يُؤْمِنُ أَحَدُكُمْ حَتّٰى يُحِبَّ لِأَخِيهِ مَا يُحِبُّ لِنَفْسِهِ",
                    "Sizden biriniz kendisi için istediğini mü'min kardeşi için de istemedikçe kâmil îmâna erişemez.",
                    "Buhârî, Îmân 7; Müslim, Îmân 71"},
            {"عَجَبًا لِأَمْرِ الْمُؤْمِنِ إِنَّ أَمْرَهُ كُلَّهُ خَيْرٌ",
                    "Mü'minin durumu ne hoş ve hayret vericidir! Onun her işi hayırdır: Bir sevince erişirse şükreder, hayır olur; bir sıkıntı gelirse sabreder, yine hayır olur.",
                    "Müslim, Zühd 64; Riyâzü's-Sâlihîn 27"},
            {"أَفْضَلُ الصَّلَاةِ بَعْدَ الْفَرِيضَةِ صَلَاةُ اللَّيْلِ",
                    "Farz namazlardan sonra en fazîletli namaz, gece yarısında kılınan (teheccüd) namazıdır.",
                    "Müslim, Sıyâm 202; Tirmizî, Mevâkît 207"},
            {"مَنْ صَلَّى الْعِشَاءَ فِي جَمَاعَةٍ فَكَأَنَّمَا قَامَ نِصْفَ اللَّيْلِ",
                    "Kim yatsı namazını cemaatle kılarsa gecenin yarısını, sabah namazını da cemaatle kılarsa bütün geceyi ibâdetle geçirmiş gibi olur.",
                    "Müslim, Mesâcid 260; Tirmizî, Mevâkît 51"},
            {"مَثَلُ الَّذِي يَذْكُرُ رَبَّهُ وَالَّذِي لَا يَذْكُرُ رَبَّهُ مَثَلُ الْحَيِّ وَالْمَيِّتِ",
                    "Rabbini zikreden kimse ile zikretmeyen kimsenin misâli, diri ile ölünün misâli gibidir.",
                    "Buhârî, Daavât 66; Riyâzü's-Sâlihîn 1434"},
            {"مَنْ لَا يَشْكُرُ النَّاسَ لَا يَشْكُرُ اللّٰهَ",
                    "İnsanlara teşekkür etmeyen, Allah'a da hakkıyla şükretmiş olmaz.",
                    "Tirmizî, Birr 35"},
            {"اتَّقِ اللّٰهَ حَيْثُمَا كُنْتَ وَأَتْبِعِ السَّيِّئَةَ الْحَسَنَةَ تَمْحُهَا",
                    "Nerede olursan ol Allah'a karşı takvâ sahibi ol; kötülüğün peşinden hemen bir iyilik yap ki onu silip süpürsün ve insanlara güzel ahlâkla muâmele et.",
                    "Tirmizî, Birr 55; Riyâzü's-Sâlihîn 61"},
            {"الدِّينُ النَّصِيحَةُ",
                    "Din samîmiyettir: Allah'a, Kitâbına, Resûlüne ve bütün Müslümanlara karşı içtenlik ve hayırhahlıktır.",
                    "Müslim, Îmân 95; Buhârî, Îmân 42"},
            {"لَيْسَ الشَّدِيدُ بِالصُّرَعَةِ إِنَّمَا الشَّدِيدُ الَّذِي يَمْلِكُ نَفْسَهُ عِنْدَ الْغَضَبِ",
                    "Asıl pehlivan güreşte rakiplerini yenen değil, öfke ânında nefsine hâkim olabilendir.",
                    "Buhârî, Edeb 76; Müslim, Birr 107"},
            {"مَا نَقَصَتْ صَدَقَةٌ مِنْ مَالٍ",
                    "Sadaka malı eksiltmez; Allah affeden kulunun ancak izzet ve şerefini artırır; Allah için tevâzu göstereni Allah mutlaka yükseltir.",
                    "Müslim, Birr 69; Tirmizî, Birr 82"},
            {"خَيْرُكُمْ خَيْرُكُمْ لِأَهْلِهِ",
                    "Sizin en hayırlınız, ailesine karşı en hayırlı ve şefkatli davrananınızdır.",
                    "Tirmizî, Menâkıb 63; Riyâzü's-Sâlihîn 278"},
            {"إِنَّ اللّٰهَ لَا يَنْظُرُ إِلٰى صُوَرِكُمْ وَأَمْوَالِكُمْ وَلٰكِنْ يَنْظُرُ إِلٰى قُلُوبِكُمْ وَأَعْمَالِكُمْ",
                    "Şüphesiz Allah sizin sûretlerinize ve mallarınıza bakmaz; lâkin kalplerinize ve amellerinize bakar.",
                    "Müslim, Birr 34; Riyâzü's-Sâlihîn 7"},
            {"مَنْ قَرَأَ آيَةَ الْكُرْسِيِّ دُبُرَ كُلِّ صَلَاةٍ مَكْتُوبَةٍ",
                    "Kim her farz namazın ardından Âyetü'l-Kürsî'yi okursa, cennete girmesiyle arasında ölümden başka bir engel kalmaz.",
                    "Nesâî, es-Sünenü'l-Kübrâ, Amelü'l-Yevm 100"},
            {"مِنْ حُسْنِ إِسْلَامِ الْمَرْءِ تَرْكُهُ مَا لَا يَعْنِيهِ",
                    "Kişinin kendisini ilgilendirmeyen boş işleri terk etmesi, Müslümanlığının güzelliğindendir.",
                    "Tirmizî, Zühd 11; Riyâzü's-Sâlihîn 67"},
            {"مَنْ صَلَّى عَلَيَّ صَلَاةً صَلَّى اللّٰهُ عَلَيْهِ بِهَا عَشْرًا",
                    "Kim bana bir defa salât ü selâm getirirse, Allah da ona bunun karşılığında on rahmet indirir.",
                    "Müslim, Salât 70; Tirmizî, Vitir 21"},
            {"اللّٰهُمَّ أَعِنِّي عَلٰى ذِكْرِكَ وَشُكْرِكَ وَحُسْنِ عِبَادَتِكَ",
                    "Resûlullah (s.a.v.) Muâz b. Cebel'in elinden tutarak buyurdu: Ey Muâz! Her namazın sonunda 'Allah'ım! Seni zikretmek, Sana şükretmek ve Sana güzelce kulluk etmek için bana yardım eyle' duâsını sakın bırakma.",
                    "Ebû Dâvûd, Vitir 26; Riyâzü's-Sâlihîn 384"}
    };

    /** Vakte özel sabah/akşam ezkârı ve nebevî duâlar {başlık, Arapça, okunuş, meal, kaynak}. */
    private static final String[][] NEBEVI_EZKAR = {
            {"Sabah Zikri (Seher ve Kuşluk)",
                    "أَصْبَحْنَا وَأَصْبَحَ الْمُلْكُ لِلّٰهِ، وَالْحَمْدُ لِلّٰهِ، لَا إِلٰهَ إِلَّا اللّٰهُ وَحْدَهُ لَا شَرِيكَ لَهُ",
                    "Asbahnâ ve asbaha'l-mülkü lillâh, velhamdülillâh, lâ ilâhe illallâhu vahdehû lâ şerîke leh.",
                    "Sabaha eriştik, mülk de Allah'ın olarak sabaha erişti. Hamd Allah'a mahsustur; O'ndan başka ilâh yoktur, tektir ve ortağı yoktur.",
                    "Müslim, Zikir 74"},
            {"Seyyidü'l-İstiğfâr (Sabah ve Akşam)",
                    "اَللّٰهُمَّ أَنْتَ رَبِّي لَا إِلٰهَ إِلَّا أَنْتَ، خَلَقْتَنِي وَأَنَا عَبْدُكَ، وَأَنَا عَلٰى عَهْدِكَ وَوَعْدِكَ مَا اسْتَطَعْتُ",
                    "Allâhümme ente Rabbî lâ ilâhe illâ ente, halaktenî ve ene abdüke, ve ene alâ ahdike ve va'dike mesteta'tü...",
                    "Allah'ım! Sen benim Rabbimsin, Senden başka ilâh yoktur. Beni Sen yarattın ve ben Senin kulunum; gücüm yettiğince Sana verdiğim söz ve vaad üzereyim.",
                    "Buhârî, Daavât 2"},
            {"İnşirâh ve İş Kolaylığı Duâsı",
                    "رَبِّ اشْرَحْ لِي صَدْرِي وَيَسِّرْ لِي أَمْرِي",
                    "Rabbişrah lî sadrî ve yessir lî emrî.",
                    "Rabbim! Gönlüme genişlik ve ferahlık ver, işimi bana kolaylaştır.",
                    "Tâhâ 20/25-26"},
            {"Namaz Sonrası Selâm ve Sekînet Duâsı",
                    "اَللّٰهُمَّ أَنْتَ السَّلَامُ وَمِنْكَ السَّلَامُ تَبَارَكْتَ يَا ذَا الْجَلَالِ وَالْإِكْرَامِ",
                    "Allâhümme ente's-selâmü ve minke's-selâm, tebârekte yâ ze'l-celâli ve'l-ikrâm.",
                    "Allah'ım! Sen Selâm'sın, esenlik ve güven ancak Sendendir. Ey celâl ve ikrâm sahibi Rabbimiz, şânın ne yücedir!",
                    "Müslim, Mesâcid 135"},
            {"Akşam Zikri ve Muhâfaza Duâsı",
                    "أَمْسَيْنَا وَأَمْسَى الْمُلْكُ لِلّٰهِ، بِسْمِ اللّٰهِ الَّذِي لَا يَضُرُّ مَعَ اسْمِهِ شَيْءٌ فِي الْأَرْضِ وَلَا فِي السَّمَاءِ وَهُوَ السَّمِيعُ الْعَلِيمُ",
                    "Emseynâ ve emse'l-mülkü lillâh. Bismillâhillezî lâ yedurru mea'smihî şey'ün fi'l-ardı ve lâ fi's-semâi ve hüve's-Semîu'l-Alîm.",
                    "Akşama eriştik, mülk de Allah'ın olarak akşama erişti. İsmi anıldığında ne yerde ne gökte hiçbir şeyin zarar veremeyeceği Allah'ın adıyla! O her şeyi işiten ve bilendir.",
                    "Ebû Dâvûd, Edeb 101; Tirmizî, Daavât 13"},
            {"Gece ve Teheccüd Nûr Duâsı",
                    "رَبَّنَا آتِنَا فِي الدُّنْيَا حَسَنَةً وَفِي الْآخِرَةِ حَسَنَةً وَقِنَا عَذَابَ النَّارِ",
                    "Rabbenâ âtinâ fi'd-dünyâ haseneten ve fi'l-âhireti haseneten ve kınâ azâbe'n-nâr.",
                    "Rabbimiz! Bize dünyada da iyilik ve güzellik ver, âhirette de iyilik ver ve bizi ateş azâbından koru.",
                    "Bakara 2/201; Buhârî, Daavât 55"}
    };

    /** Günün Esmâü'l-Hüsnâ'sı verisi. */
    static final class EsmaBilgi {
        final int siraNo; // 1..99/100
        final String arapca;
        final String ad;
        final String anlam;
        final String zikirAdi;
        final String zikirArapca;

        EsmaBilgi(int siraNo, String arapca, String ad, String anlam, String zikirAdi, String zikirArapca) {
            this.siraNo = siraNo;
            this.arapca = arapca;
            this.ad = ad;
            this.anlam = anlam;
            this.zikirAdi = zikirAdi;
            this.zikirArapca = zikirArapca;
        }
    }

    /** Âyet verisi. */
    private static final class AyetBilgi {
        final String arapca;
        final String meal;
        final String kaynak;

        AyetBilgi(String arapca, String meal, String kaynak) {
            this.arapca = arapca;
            this.meal = meal;
            this.kaynak = kaynak;
        }
    }

    /** Duâ verisi. */
    private static final class DuaBilgi {
        final String baslik;
        final String arapca;
        final String okunus;
        final String meal;
        final String kaynak;

        DuaBilgi(String baslik, String arapca, String okunus, String meal, String kaynak) {
            this.baslik = baslik;
            this.arapca = arapca;
            this.okunus = okunus;
            this.meal = meal;
            this.kaynak = kaynak;
        }
    }

    private ManeviPaket() {}

    // ================================================================ VAKİTLER SEKMESİ KOMPAKT KART

    /** Vakitler sekmesinde gösterilen dinamik başlıklı, kompakt ve ilham verici manevî paket kartı. */
    public static View vakitPaketiKarti(final DurumAktivitesi a,
                                        final VakitTakvimi.Takvim takvimGirdi,
                                        final PaylasEylem paylasici) {
        final TemaMotoru.Durum tema = TemaMotoru.aktif(a);
        final VakitTakvimi.Takvim t = takvimGirdi != null ? takvimGirdi : VakitTakvimi.oku(a);

        final int pencere = vakitPenceresi(t);
        final int yilGunu = Calendar.getInstance().get(Calendar.DAY_OF_YEAR);
        final String baslik = VAKIT_PAKET_BASLIKLARI[pencere];
        final String[] hadis = SAHIH_HADISLER[(yilGunu * 5 + pencere) % SAHIH_HADISLER.length];
        final EsmaBilgi esma = gununEsmasi(a, yilGunu);

        LinearLayout k = kart(a, tema);

        // Üst etiket
        TextView ustEtiket = yazi(a, tema, "✦  " + baslik, 11, tema.vurgu, true);
        ustEtiket.setLetterSpacing(0.06f);
        k.addView(ustEtiket);
        a.bosluk(k, 4);

        // Günün/Vaktin Sahih Hadîs-i Şerîfi
        k.addView(yazi(a, tema, "“" + hadis[1] + "”", 14, tema.metin, false));
        k.addView(yazi(a, tema, "— " + hadis[2], 11, tema.silik, true));
        a.bosluk(k, 10);

        // Günün Esmâsı şeridi (Arapça hat + Türkçe ad + anlam)
        LinearLayout esmaKutu = new LinearLayout(a);
        esmaKutu.setOrientation(LinearLayout.HORIZONTAL);
        esmaKutu.setGravity(Gravity.CENTER_VERTICAL);
        esmaKutu.setPadding(a.dp(12), a.dp(10), a.dp(12), a.dp(10));
        GradientDrawable eg = new GradientDrawable();
        eg.setCornerRadius(a.dp(14));
        eg.setColor(tema.acik ? 0x141E6B55 : 0x26000000);
        eg.setStroke(Math.max(1, a.dp(1)), (tema.vurgu & 0x00FFFFFF) | 0x44000000);
        esmaKutu.setBackground(eg);

        LinearLayout esmaSol = new LinearLayout(a);
        esmaSol.setOrientation(LinearLayout.VERTICAL);
        esmaSol.addView(yazi(a, tema, "GÜNÜN ESMÂSI · " + esma.ad.toUpperCase(Metinler.TR), 11, tema.vurgu, true));
        esmaSol.addView(yazi(a, tema, esma.anlam, 13, tema.soluk, false));
        esmaKutu.addView(esmaSol, new LinearLayout.LayoutParams(0, -2, 1f));

        TextView esmaArapca = yazi(a, tema, esma.arapca, 28, tema.vurgu, false);
        esmaArapca.setTypeface(Varlik.kuranYazisi(a));
        esmaArapca.setPadding(a.dp(12), 0, a.dp(2), 0);
        esmaKutu.addView(esmaArapca);

        k.addView(esmaKutu);

        // Eylem düğmeleri: [ Tüm Paketi Gör › | Kart Paylaş ]
        LinearLayout dugmeSatir = new LinearLayout(a);
        dugmeSatir.setOrientation(LinearLayout.HORIZONTAL);

        TextView tumDugme = dugme(a, tema, "Tüm Paketi Gör ›", true,
                v -> sayfaAc(a, t, paylasici));
        TextView paylasDugme = dugme(a, tema, "Kart Paylaş", false,
                v -> paylas(a, paylasici, hadis[0],
                        hadis[1] + "\n\nGünün Esmâsı: " + esma.ad + " (" + esma.arapca + ") — " + esma.anlam,
                        hadis[2]));

        dugmeSatir.addView(tumDugme, a.yarim(true));
        dugmeSatir.addView(paylasDugme, a.yarim(false));
        k.addView(dugmeSatir);

        return k;
    }

    // ================================================================ TAM ALT SAYFA: GÜNÜN MANEVÎ PAKETİ

    /** Günün Manevî Paketi tam ekran alt sayfasını açar. */
    public static void sayfaAc(final DurumAktivitesi a,
                               final VakitTakvimi.Takvim takvimGirdi,
                               final PaylasEylem paylasici) {
        if (a == null) return;
        a.guvenli("maneviPaket", () -> {
            final VakitTakvimi.Takvim t = takvimGirdi != null ? takvimGirdi : VakitTakvimi.oku(a);
            final TemaMotoru.Durum tema = TemaMotoru.aktif(a);
            final int pencere = vakitPenceresi(t);
            final int yilGunu = Calendar.getInstance().get(Calendar.DAY_OF_YEAR);

            final LinearLayout dis = a.sutun();

            // Üst vakit başlığı
            TextView ustAciklama = yazi(a, tema,
                    VAKIT_PAKET_BASLIKLARI[pencere] + "  ·  Âyet · Hadîs · Duâ · Esmâ",
                    13, tema.vurgu, true);
            dis.addView(ustAciklama);
            a.bosluk(dis, 10);

            // 1) VAKTİN ÂYETİ (DailyVerses.json)
            final List<AyetBilgi> ayetler = gunlukAyetleriOku(a);
            final int[] ayetIdx = {(yilGunu + pencere) % Math.max(1, ayetler.size())};
            LinearLayout ayetKart = kart(a, tema);
            ayetKart.addView(yazi(a, tema, "1 · VAKTİN ÂYET-İ KERÎMESİ", 11, tema.vurgu, true));

            final TextView ayetArapca = yazi(a, tema, "", 24, tema.metin, false);
            ayetArapca.setTypeface(Varlik.kuranYazisi(a));
            ayetArapca.setGravity(Gravity.RIGHT);
            ayetArapca.setLineSpacing(0, 1.38f);
            ayetKart.addView(ayetArapca);

            final TextView ayetMeal = yazi(a, tema, "", 16, tema.metin, false);
            ayetKart.addView(ayetMeal);
            final TextView ayetKaynak = yazi(a, tema, "", 12, tema.vurgu, true);
            ayetKart.addView(ayetKaynak);

            final Runnable ayetGuncelle = () -> {
                AyetBilgi ab = ayetler.get(ayetIdx[0] % ayetler.size());
                if (ab.arapca != null && !ab.arapca.isEmpty()) {
                    ayetArapca.setVisibility(View.VISIBLE);
                    ayetArapca.setText(ab.arapca);
                } else {
                    ayetArapca.setVisibility(View.GONE);
                }
                ayetMeal.setText("“" + ab.meal + "”");
                ayetKaynak.setText("— " + ab.kaynak);
            };
            ayetGuncelle.run();

            LinearLayout ayetEylem = new LinearLayout(a);
            ayetEylem.addView(dugme(a, tema, "Başka Âyet ↻", false, v -> {
                ayetIdx[0] = (ayetIdx[0] + 1) % ayetler.size();
                ayetGuncelle.run();
                yumusakBelir(ayetMeal);
            }), a.yarim(true));
            ayetEylem.addView(dugme(a, tema, "Kart Paylaş", true, v -> {
                AyetBilgi ab = ayetler.get(ayetIdx[0] % ayetler.size());
                paylas(a, paylasici, ab.arapca, ab.meal, ab.kaynak);
            }), a.yarim(false));
            ayetKart.addView(ayetEylem);
            dis.addView(ayetKart);

            // 2) GÜNÜN HADÎS-İ ŞERÎFİ (30 sahih hadis + Başka Hadîs ↻)
            final int[] hadisIdx = {(yilGunu * 5 + pencere) % SAHIH_HADISLER.length};
            LinearLayout hadisKart = kart(a, tema);
            hadisKart.addView(yazi(a, tema, "2 · GÜNÜN HADÎS-İ ŞERÎFİ", 11, tema.vurgu, true));

            final TextView hadisArapca = yazi(a, tema, "", 22, tema.metin, false);
            hadisArapca.setTypeface(Varlik.kuranYazisi(a));
            hadisArapca.setGravity(Gravity.RIGHT);
            hadisArapca.setLineSpacing(0, 1.35f);
            hadisKart.addView(hadisArapca);

            final TextView hadisMetin = yazi(a, tema, "", 15, tema.metin, false);
            hadisKart.addView(hadisMetin);
            final TextView hadisKaynak = yazi(a, tema, "", 12, tema.vurgu, true);
            hadisKart.addView(hadisKaynak);

            final Runnable hadisGuncelle = () -> {
                String[] h = SAHIH_HADISLER[hadisIdx[0] % SAHIH_HADISLER.length];
                hadisArapca.setText(h[0]);
                hadisMetin.setText("“" + h[1] + "”");
                hadisKaynak.setText("— " + h[2]);
            };
            hadisGuncelle.run();

            LinearLayout hadisEylem = new LinearLayout(a);
            hadisEylem.addView(dugme(a, tema, "Başka Hadîs ↻", false, v -> {
                hadisIdx[0] = (hadisIdx[0] + 1) % SAHIH_HADISLER.length;
                hadisGuncelle.run();
                yumusakBelir(hadisMetin);
            }), a.yarim(true));
            hadisEylem.addView(dugme(a, tema, "Kart Paylaş", true, v -> {
                String[] h = SAHIH_HADISLER[hadisIdx[0] % SAHIH_HADISLER.length];
                paylas(a, paylasici, h[0], h[1], h[2]);
            }), a.yarim(false));
            hadisKart.addView(hadisEylem);
            dis.addView(hadisKart);

            // 3) VAKTİN NEBEVÎ DUÂSI VE SABAH/AKŞAM EZKÂRI (Duas.json + vakit ezkârı)
            final List<DuaBilgi> dualar = nebeviDualariOku(a, pencere);
            final int[] duaIdx = {0};
            LinearLayout duaKart = kart(a, tema);
            duaKart.addView(yazi(a, tema, "3 · VAKTİN NEBEVÎ DUÂSI VE EZKÂRI", 11, tema.vurgu, true));

            final TextView duaBaslik = yazi(a, tema, "", 17, tema.metin, true);
            duaKart.addView(duaBaslik);

            final TextView duaArapca = yazi(a, tema, "", 23, tema.vurgu, false);
            duaArapca.setTypeface(Varlik.kuranYazisi(a));
            duaArapca.setGravity(Gravity.RIGHT);
            duaArapca.setLineSpacing(0, 1.38f);
            duaKart.addView(duaArapca);

            final TextView duaOkunus = yazi(a, tema, "", 14, tema.metin, true);
            duaKart.addView(duaOkunus);
            final TextView duaMeal = yazi(a, tema, "", 14, tema.soluk, false);
            duaKart.addView(duaMeal);
            final TextView duaKaynak = yazi(a, tema, "", 12, tema.silik, true);
            duaKart.addView(duaKaynak);

            final Runnable duaGuncelle = () -> {
                DuaBilgi d = dualar.get(duaIdx[0] % dualar.size());
                duaBaslik.setText(d.baslik);
                if (d.arapca != null && !d.arapca.isEmpty()) {
                    duaArapca.setVisibility(View.VISIBLE);
                    duaArapca.setText(d.arapca);
                } else {
                    duaArapca.setVisibility(View.GONE);
                }
                duaOkunus.setText("Okunuşu: " + d.okunus);
                duaMeal.setText("Anlamı: " + d.meal);
                duaKaynak.setText("— " + d.kaynak);
            };
            duaGuncelle.run();

            LinearLayout duaEylem = new LinearLayout(a);
            duaEylem.addView(dugme(a, tema, "Başka Duâ ↻", false, v -> {
                duaIdx[0] = (duaIdx[0] + 1) % dualar.size();
                duaGuncelle.run();
                yumusakBelir(duaMeal);
            }), a.yarim(true));
            duaEylem.addView(dugme(a, tema, "Duâyı Paylaş", true, v -> {
                DuaBilgi d = dualar.get(duaIdx[0] % dualar.size());
                paylas(a, paylasici, d.arapca, d.okunus + "\n\n" + d.meal, d.baslik + " · " + d.kaynak);
            }), a.yarim(false));
            duaKart.addView(duaEylem);
            dis.addView(duaKart);

            // 4) GÜNÜN ESMÂÜ'L-HÜSNÂ'SI VE ZİKİR ÖNERİSİ
            final EsmaBilgi esma = gununEsmasi(a, yilGunu);
            LinearLayout esmaKart = kart(a, tema);
            esmaKart.addView(yazi(a, tema, "4 · GÜNÜN ESMÂÜ'L-HÜSNÂ'SI VE ZİKİR ÖNERİSİ", 11, tema.vurgu, true));

            TextView buyukArapca = yazi(a, tema, esma.arapca, 42, tema.vurgu, false);
            buyukArapca.setTypeface(Varlik.kuranYazisi(a));
            buyukArapca.setGravity(Gravity.CENTER);
            esmaKart.addView(buyukArapca);

            TextView buyukAd = yazi(a, tema, esma.ad + "  (" + esma.zikirAdi + ")", 20, tema.metin, true);
            buyukAd.setGravity(Gravity.CENTER);
            esmaKart.addView(buyukAd);

            TextView buyukAnlam = yazi(a, tema, esma.anlam, 14, tema.soluk, false);
            buyukAnlam.setGravity(Gravity.CENTER);
            esmaKart.addView(buyukAnlam);
            a.bosluk(esmaKart, 8);

            LinearLayout tefekkurKutu = new LinearLayout(a);
            tefekkurKutu.setOrientation(LinearLayout.VERTICAL);
            tefekkurKutu.setPadding(a.dp(12), a.dp(10), a.dp(12), a.dp(10));
            GradientDrawable tg = new GradientDrawable();
            tg.setCornerRadius(a.dp(14));
            tg.setColor(tema.acik ? 0x121E6B55 : 0x24000000);
            tefekkurKutu.setBackground(tg);
            tefekkurKutu.addView(yazi(a, tema,
                    "Günlük Zikir Tavsiyesi: Bugün namaz tesbihâtının ardından 99 defa “" + esma.zikirAdi
                            + "” zikrini kalp huzûruyla çekerek bu ilâhî ismin hayâtınızdaki tecellîsini tefekkür edebilirsiniz.",
                    13, tema.iyi, false));
            esmaKart.addView(tefekkurKutu);

            LinearLayout esmaDugmeler = new LinearLayout(a);
            esmaDugmeler.addView(dugme(a, tema, "Zikirmatik'te Çek ›", true, v -> zikirmatikteCek(a, esma)), a.yarim(true));
            esmaDugmeler.addView(dugme(a, tema, "Esmâ Paylaş", false,
                    v -> paylas(a, paylasici, esma.arapca, esma.ad + " — " + esma.anlam, "Esmâü'l-Hüsnâ")), a.yarim(false));
            esmaKart.addView(esmaDugmeler);
            dis.addView(esmaKart);

            ScrollView sv = a.sayfa(dis);
            sv.setPadding(0, 0, 0, 0);
            a.altSayfa("Günün Manevî Paketi", sv, "kandil");
        });
    }

    // ================================================================ VERİ VE İŞ MANTIĞI

    /** Mevcut vakte göre 0..5 pencere indeksini döndürür. */
    private static int vakitPenceresi(VakitTakvimi.Takvim t) {
        if (t != null) {
            VakitTakvimi.An simdiki = t.simdiki();
            if (simdiki != null && simdiki.namaz != null) {
                switch (simdiki.namaz) {
                    case "fajr":
                        return 0;
                    case "sunrise":
                        return 1;
                    case "dhuhr":
                        return 2;
                    case "asr":
                        return 3;
                    case "maghrib":
                        return 4;
                    case "isha":
                        return 5;
                    default:
                        break;
                }
            }
        }
        int saat = Calendar.getInstance().get(Calendar.HOUR_OF_DAY);
        if (saat >= 4 && saat < 7) return 0;
        if (saat >= 7 && saat < 12) return 1;
        if (saat >= 12 && saat < 15) return 2;
        if (saat >= 15 && saat < 18) return 3;
        if (saat >= 18 && saat < 21) return 4;
        return 5;
    }

    /** Yılın gününe göre deterministik olarak EsmaulHusna.json'dan Günün Esmâsı'nı seçer. */
    static EsmaBilgi gununEsmasi(Context c, int yilGunu) {
        try {
            String ham = Varlik.flutterMetin(c, "assets/data/EsmaulHusna.json");
            if (ham != null && !ham.isEmpty()) {
                JSONArray dizi = new JSONArray(ham);
                if (dizi.length() > 0) {
                    int idx = Math.abs(yilGunu - 1) % dizi.length();
                    JSONObject o = dizi.getJSONObject(idx);
                    String ad = o.optString("name", "Er-Rahmân").trim();
                    String anlam = o.optString("meaning", "").trim();
                    String arapca = idx < ESMA_ARAPCA.length ? ESMA_ARAPCA[idx] : ESMA_ARAPCA[0];
                    return esmaOlustur(idx + 1, arapca, ad, anlam);
                }
            }
        } catch (Throwable ignored) {
        }
        int yIdx = Math.abs(yilGunu - 1) % ESMA_YEDEK.length;
        String ad = ESMA_YEDEK[yIdx][0];
        String anlam = ESMA_YEDEK[yIdx][1];
        String arapca = yIdx == 0 ? "اللّٰهُ" : "الرَّحْمٰنُ";
        return esmaOlustur(yIdx + 1, arapca, ad, anlam);
    }

    private static EsmaBilgi esmaOlustur(int sira, String arapca, String ad, String anlam) {
        String zikirAdi;
        if ("Allah".equalsIgnoreCase(ad)) {
            zikirAdi = "Yâ Allah";
        } else if (ad.startsWith("Mâlikü")) {
            zikirAdi = "Yâ Mâlike'l-Mülk";
        } else if (ad.startsWith("Zü'l-")) {
            zikirAdi = "Yâ Ze'l-Celâli ve'l-İkrâm";
        } else if (ad.length() > 3 && ad.charAt(2) == '-') {
            zikirAdi = "Yâ " + ad.substring(3);
        } else {
            zikirAdi = "Yâ " + ad;
        }
        String zikirArapca = "اللّٰهُ".equals(arapca) ? "يَا اَللّٰهُ" : ("يَا " + arapca.replaceFirst("^الْ|^ال", ""));
        return new EsmaBilgi(sira, arapca, ad, anlam, zikirAdi, zikirArapca);
    }

    /** DailyVerses.json içinden Kur'ân âyetlerini (ve varsa eşleşen Arapça metni) yükler. */
    private static List<AyetBilgi> gunlukAyetleriOku(Context c) {
        List<AyetBilgi> liste = new ArrayList<>();
        try {
            String ham = Varlik.flutterMetin(c, "assets/data/DailyVerses.json");
            if (ham != null && !ham.isEmpty()) {
                JSONArray dizi = new JSONArray(ham);
                for (int i = 0; i < dizi.length(); i++) {
                    JSONObject o = dizi.optJSONObject(i);
                    if (o == null) continue;
                    String metin = o.optString("text", "").trim();
                    String kaynak = o.optString("source", "").trim();
                    if (metin.isEmpty() || kaynak.startsWith("Buhârî")) continue;
                    liste.add(new AyetBilgi(bilinenAyetArapcasi(kaynak), metin, kaynak));
                }
            }
        } catch (Throwable ignored) {
        }
        if (liste.isEmpty()) {
            liste.add(new AyetBilgi(
                    "فَإِنَّ مَعَ الْعُسْرِ يُسْرًا",
                    "Şüphesiz zorlukla beraber bir kolaylık vardır.",
                    "İnşirah 94/6"));
            liste.add(new AyetBilgi(
                    "أَلَا بِذِكْرِ اللّٰهِ تَطْمَئِنُّ الْقُلُوبُ",
                    "Bilesiniz ki kalpler ancak Allah'ı anmakla huzur bulur.",
                    "Ra'd 13/28"));
            liste.add(new AyetBilgi(
                    "ادْعُونِي أَسْتَجِبْ لَكُمْ",
                    "Rabbiniz şöyle buyurdu: Bana duâ edin ki size karşılık vereyim.",
                    "Mü'min 40/60"));
        }
        return liste;
    }

    private static String bilinenAyetArapcasi(String kaynak) {
        if (kaynak == null) return "";
        if (kaynak.contains("94/6")) return "إِنَّ مَعَ الْعُسْرِ يُسْرًا";
        if (kaynak.contains("13/28")) return "أَلَا بِذِكْرِ اللّٰهِ تَطْمَئِنُّ الْقُلُوبُ";
        if (kaynak.contains("40/60")) return "ادْعُونِي أَسْتَجِبْ لَكُمْ";
        if (kaynak.contains("2/152")) return "فَاذْكُرُونِي أَذْكُرْكُمْ وَاشْكُرُوا لِي وَلَا تَكْفُرُونِ";
        if (kaynak.contains("2/153")) return "يَا أَيُّهَا الَّذِينَ آمَنُوا اسْتَعِينُوا بِالصَّبْرِ وَالصَّلَاةِ ۚ إِنَّ اللّٰهَ مَعَ الصَّابِرِينَ";
        if (kaynak.contains("2/201")) return "رَبَّنَا آتِنَا فِي الدُّنْيَا حَسَنَةً وَفِي الْآخِرَةِ حَسَنَةً وَقِنَا عَذَابَ النَّارِ";
        if (kaynak.contains("2/286")) return "لَا يُكَلِّفُ اللّٰهُ نَفْسًا إِلَّا وُسْعَهَا";
        if (kaynak.contains("65/3")) return "وَمَنْ يَتَوَكَّلْ عَلَى اللّٰهِ فَهُوَ حَسْبُهُ";
        if (kaynak.contains("20/25")) return "رَبِّ اشْرَحْ لِي صَدْرِي وَيَسِّرْ لِي أَمْرِي";
        if (kaynak.contains("14/40")) return "رَبِّ اجْعَلْنِي مُقِيمَ الصَّلَاةِ وَمِنْ ذُرِّيَّتِي";
        if (kaynak.contains("39/53")) return "لَا تَقْنَطُوا مِنْ رَحْمَةِ اللّٰهِ";
        if (kaynak.contains("49/10")) return "إِنَّمَا الْمُؤْمِنُونَ إِخْوَةٌ فَأَصْلِحُوا بَيْنَ أَخَوَيْكُمْ";
        return "";
    }

    /** Vakte uygun nebevî ezkârı başa koyarak Duas.json ile birleştirir. */
    private static List<DuaBilgi> nebeviDualariOku(Context c, int pencere) {
        List<DuaBilgi> liste = new ArrayList<>();
        // Önce mevcut vaktin özel nebevî zikri
        int ilk = Math.max(0, Math.min(NEBEVI_EZKAR.length - 1, pencere));
        String[] vEzk = NEBEVI_EZKAR[ilk];
        liste.add(new DuaBilgi(vEzk[0], vEzk[1], vEzk[2], vEzk[3], vEzk[4]));

        for (int i = 0; i < NEBEVI_EZKAR.length; i++) {
            if (i == ilk) continue;
            String[] e = NEBEVI_EZKAR[i];
            liste.add(new DuaBilgi(e[0], e[1], e[2], e[3], e[4]));
        }

        try {
            String ham = Varlik.flutterMetin(c, "assets/data/Duas.json");
            if (ham != null && !ham.isEmpty()) {
                JSONArray dizi = new JSONArray(ham);
                for (int i = 0; i < dizi.length(); i++) {
                    JSONObject o = dizi.optJSONObject(i);
                    if (o == null) continue;
                    String baslik = o.optString("title", "").trim();
                    String okunus = o.optString("reading", "").trim();
                    String meal = o.optString("meaning", "").trim();
                    String kaynak = o.optString("source", "").trim();
                    if (!baslik.isEmpty() && !meal.isEmpty()) {
                        liste.add(new DuaBilgi(baslik, bilinenDuaArapcasi(baslik), okunus, meal, kaynak));
                    }
                }
            }
        } catch (Throwable ignored) {
        }
        return liste;
    }

    private static String bilinenDuaArapcasi(String baslik) {
        if (baslik == null) return "";
        if (baslik.contains("Yûnus")) return "لَا إِلٰهَ إِلَّا أَنْتَ سُبْحَانَكَ إِنِّي كُنْتُ مِنَ الظَّالِمِينَ";
        if (baslik.contains("Rabbenâ Duası")) return "رَبَّنَا آتِنَا فِي الدُّنْيَا حَسَنَةً وَفِي الْآخِرَةِ حَسَنَةً وَقِنَا عَذَابَ النَّارِ";
        if (baslik.contains("İstiğfar")) return "أَسْتَغْفِرُ اللّٰهَ الْعَظِيمَ وَأَتُوبُ إِلَيْهِ";
        if (baslik.contains("Salavât")) return "اَللّٰهُمَّ صَلِّ عَلٰى سَيِّدِنَا مُحَمَّدٍ وَعَلٰى آلِ سَيِّدِنَا مُحَمَّدٍ";
        if (baslik.contains("Sağlam İman")) return "رَبَّنَا لَا تُزِغْ قُلُوبَنَا بَعْدَ إِذْ هَدَيْتَنَا وَهَبْ لَنَا مِنْ لَدُنْكَ رَحْمَةً";
        return "";
    }

    /** Günün Esmâsı'nı Zikirmatik'e ekler/seçer ve Zikir sekmesine geçer. */
    private static void zikirmatikteCek(DurumAktivitesi a, EsmaBilgi esma) {
        try {
            Zikir z = new Zikir(a);
            List<Zikir.Tanim> tum = z.tumTanimlar();
            int bulunan = -1;
            for (int i = 0; i < tum.size(); i++) {
                Zikir.Tanim dt = tum.get(i);
                if (esma.zikirAdi.equalsIgnoreCase(dt.ad) || esma.ad.equalsIgnoreCase(dt.ad)) {
                    bulunan = i;
                    break;
                }
            }
            if (bulunan >= 0) {
                z.sec(bulunan);
            } else {
                z.ozelEkle(esma.zikirAdi, esma.zikirArapca, esma.anlam, 99);
            }
            while (a.altSayfaSayisi() > 0) {
                a.altSayfaKapat();
            }
            a.sekmeyeGec(DurumAktivitesi.S_ZIKIR);
            Toast.makeText(a, esma.zikirAdi + " · Zikirmatik'te seçildi (Hedef: 99)", Toast.LENGTH_SHORT).show();
        } catch (Throwable t) {
            Toast.makeText(a, "Zikirmatik açılamadı", Toast.LENGTH_SHORT).show();
        }
    }

    private static void paylas(Context c, PaylasEylem paylasici, String arapca, String metin, String kaynak) {
        String temizArapca = arapca == null ? "" : arapca;
        String temizMetin = metin == null ? "" : metin;
        String temizKaynak = kaynak == null ? "Secde Vakti" : kaynak;
        if (paylasici != null) {
            paylasici.paylas(temizArapca, temizMetin, temizKaynak);
            return;
        }
        try {
            StringBuilder b = new StringBuilder();
            if (!temizArapca.isEmpty()) b.append(temizArapca).append("\n\n");
            b.append("“").append(temizMetin).append("”\n— ").append(temizKaynak).append("\n\nSecde Vakti");
            Intent i = new Intent(Intent.ACTION_SEND);
            i.setType("text/plain");
            i.putExtra(Intent.EXTRA_TEXT, b.toString());
            c.startActivity(Intent.createChooser(i, "Manevî Kartı Paylaş"));
        } catch (Throwable ignored) {
        }
    }

    // ================================================================ GÖRÜNÜM YARDIMCILARI

    private static void yumusakBelir(View v) {
        v.setAlpha(0.25f);
        v.setTranslationY(TemaMotoru.dp(v.getContext(), 6));
        v.animate().alpha(1f).translationY(0).setDuration(260).start();
    }

    private static LinearLayout kart(DurumAktivitesi a, TemaMotoru.Durum tema) {
        LinearLayout k = new LinearLayout(a);
        k.setOrientation(LinearLayout.VERTICAL);
        k.setPadding(a.dp(16), a.dp(14), a.dp(16), a.dp(14));
        k.setBackground(tema.kartArkaPlani(a));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(0, 0, 0, a.dp(12));
        k.setLayoutParams(lp);
        return k;
    }

    private static TextView yazi(Context c, TemaMotoru.Durum tema, String metin, int bazSp, int renk, boolean kalin) {
        TextView t = new TextView(c);
        t.setText(metin);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, TemaMotoru.olcekliSp(c, bazSp));
        t.setTextColor(renk);
        t.setTypeface(kalin ? Typeface.create("sans-serif-medium", Typeface.NORMAL) : Typeface.DEFAULT);
        t.setLineSpacing(0, 1.16f);
        int p = TemaMotoru.dp(c, 2);
        t.setPadding(0, p, 0, p);
        if (!tema.acik) {
            t.setShadowLayer(TemaMotoru.dp(c, 4), 0, TemaMotoru.dp(c, 1), 0x55000000);
        }
        return t;
    }

    private static TextView dugme(DurumAktivitesi a, TemaMotoru.Durum tema,
                                  String metin, boolean birincil, View.OnClickListener tik) {
        TextView b = yazi(a, tema, metin, 14, birincil ? tema.birincilDugmeYaziRengi() : tema.metin, true);
        b.setShadowLayer(0, 0, 0, 0);
        b.setGravity(Gravity.CENTER);
        b.setMinHeight(a.dp(42));
        b.setPadding(a.dp(12), a.dp(8), a.dp(12), a.dp(8));
        b.setBackground(birincil ? tema.birincilDugme(a, 15) : tema.ikincilDugme(a, 15));
        b.setClickable(true);
        a.basmaEfekti(b);
        b.setOnClickListener(v -> {
            v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            tik.onClick(v);
        });
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(0, a.dp(10), 0, 0);
        b.setLayoutParams(lp);
        return b;
    }
}
