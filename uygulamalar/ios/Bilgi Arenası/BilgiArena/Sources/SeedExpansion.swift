import Foundation

/// Bundled, timeless practice content. Each row: question | answer | three distractors | explanation.
enum SeedExpansion {
    private static func group(_ topic: Topic, _ difficulty: Difficulty, _ rows: String) -> [Question] {
        rows.split(separator:"\n").map { line in
            let fields = line.split(separator:"|",omittingEmptySubsequences:false).map { $0.trimmingCharacters(in:.whitespaces) }
            precondition(fields.count == 6)
            return Question(text:fields[0],options:Array(fields[1...4]),answer:0,explanation:fields[5],category:topic,difficulty:difficulty)
        }
    }
    static let questions: [Question] = [
        group(.science,.medium,"""
        Hücrede protein sentezinin gerçekleştiği yapı hangisidir?|Ribozom|Lizozom|Sentrozom|Koful|Ribozomlar, haberci RNA'daki bilgiye göre amino asitleri birleştirir.
        Bir kuvvetin SI birim sistemindeki birimi nedir?|Newton|Joule|Watt|Pascal|Newton kuvvet birimidir; joule enerji, watt güç ve pascal basınç birimidir.
        Atomun kimliğini belirleyen parçacık sayısı hangisidir?|Proton sayısı|Nötron sayısı|Serbest elektron sayısı|Toplam parçacık sayısı|Proton sayısı atom numarasıdır ve bir elementin hangi element olduğunu belirler.
        Işığın boşluktan suya geçerken yön değiştirmesine ne denir?|Kırılma|Buharlaşma|Mıknatıslanma|Yoğuşma|Işık farklı optik ortamlara geçerken hızı değişir; uygun geliş açısında yönü de değişir.
        Saf su, deniz seviyesinde standart atmosfer basıncında kaç °C'de kaynar?|100|0|50|150|Saf suyun kaynama noktası 1 atmosfer basınçta 100 °C'dir; basınç değişirse kaynama sıcaklığı da değişir.
        Bir besin zincirinde üreticilerin temel rolü nedir?|İnorganik maddelerden organik besin üretmek|Yalnız diğer hayvanları tüketmek|Bütün atıkları yok etmek|Güneş ışığını engellemek|Üreticiler organik besin sentezler; bitkiler bunun için çoğunlukla fotosentezi kullanır.
        """),
        group(.science,.hard,"""
        Aynı elementin proton sayısı aynı, nötron sayısı farklı atomlarına ne denir?|İzotop|İzobar|İzoton|Molekül|İzotop atomlar aynı elementtir; nötron sayıları ve dolayısıyla kütle numaraları farklıdır.
        Enzim miktarı sabitken substrat sürekli artırılırsa tepkime hızının bir noktada sabitlenmesinin nedeni nedir?|Aktif bölgelerin doygunluğa ulaşması|Enzimin mutlaka tükenmesi|Substratın elemente dönüşmesi|Sıcaklığın zorunlu olarak sıfırlanması|Tüm aktif bölgeler dolduğunda enzimler kapasiteleri kadar çalışır; daha fazla substrat tek başına hızı artıramaz.
        İdeal bir gazın sıcaklığı sabitken hacmi yarıya indirilirse basıncı nasıl değişir?|İki katına çıkar|Yarıya iner|Değişmez|Dörtte bire iner|Sabit sıcaklık ve gaz miktarında Boyle yasasına göre basınç ile hacmin çarpımı sabittir.
        Bir DNA zincirindeki adeninin karşısına tamamlayıcı zincirde hangi baz gelir?|Timin|Urasil|Guanin|Sitozin|DNA'da adenin timinle, guanin sitozinle eşleşir; urasil RNA'da bulunur.
        Mayozun hangi özelliği döllenmeyle kromozom sayısının kuşaktan kuşağa korunmasını sağlar?|Kromozom sayısını yarıya indirmesi|Her hücrede sayıyı iki katına çıkarması|DNA'yı tamamen yok etmesi|Bütün mutasyonları düzeltmesi|Mayoz haploit üreme hücreleri oluşturur; döllenmede iki haploit takım birleşir.
        Metal bir kaşığın sıcak çayda sapının ısınması baskın olarak hangi ısı aktarımına örnektir?|İletim|Buharlaşma|Donma|Yoğunlaşma|Isı, metal boyunca tanecikler ve serbest elektronların etkileşimiyle iletilir.
        """),
        group(.history,.medium,"""
        Türkiye Büyük Millet Meclisi hangi tarihte açıldı?|23 Nisan 1920|29 Ekim 1923|19 Mayıs 1919|30 Ağustos 1922|Meclis Ankara'da 23 Nisan 1920'de açıldı; bu tarih ulusal egemenlikle ilişkilendirilir.
        Magna Carta hangi ülkede 1215 yılında kabul edildi?|İngiltere|Fransa|İtalya|İspanya|Magna Carta İngiltere'de kralın yetkilerinin sınırlandırılması tarihinde önemli bir belgedir.
        Osmanlı Devleti'nin ilk başkenti olarak kabul edilen şehir hangisidir?|Bursa|Edirne|İstanbul|Ankara|Bursa'nın 1326'da alınmasından sonra şehir Osmanlı'nın ilk başkenti oldu.
        Fransız İhtilali'nin başlangıcı hangi yılla anılır?|1789|1453|1914|1648|Bastille Baskını'nın da gerçekleştiği 1789, Fransız İhtilali'nin başlangıç yılı olarak kabul edilir.
        Kurtuluş Savaşı'nı uluslararası alanda sonuçlandıran barış antlaşması hangisidir?|Lozan Antlaşması|Sevr Antlaşması|Berlin Antlaşması|Karlofça Antlaşması|24 Temmuz 1923 tarihli Lozan Antlaşması yeni Türk devletinin uluslararası tanınmasında belirleyicidir.
        Göbeklitepe hangi ilimizin sınırları içindedir?|Şanlıurfa|Çorum|Konya|Çanakkale|Göbeklitepe, Şanlıurfa yakınlarında yer alan Neolitik Dönem arkeolojik alanıdır.
        """),
        group(.history,.hard,"""
        Osmanlı'nın ilk anayasası Kanun-ı Esasi hangi yıl ilan edildi?|1876|1839|1908|1921|Kanun-ı Esasi 1876'da ilan edildi ve Birinci Meşrutiyet dönemi başladı.
        1648 Westphalia Barışı hangi savaşlar dizisini sona erdirdi?|Otuz Yıl Savaşları|Yüz Yıl Savaşları|Napolyon Savaşları|Balkan Savaşları|Westphalia antlaşmaları, Avrupa'daki Otuz Yıl Savaşları'nı sona erdirdi.
        Anadolu'da yazılı tarihin başlangıcına kaynaklık eden Kültepe tabletleri hangi yazıyla yazılmıştır?|Çivi yazısı|Latin alfabesi|Göktürk alfabesi|Hiyeroglif|Asurlu tüccarların Kültepe'de bıraktığı çivi yazılı belgeler Anadolu'nun yazılı tarihinin erken kaynaklarıdır.
        1839 Tanzimat Fermanı hangi Osmanlı padişahı döneminde ilan edildi?|Abdülmecid|II. Mahmud|III. Selim|II. Abdülhamid|Tanzimat Fermanı, Abdülmecid döneminde Gülhane'de ilan edildi.
        Anadolu Selçukluları ile Moğollar arasında 1243'te yapılan savaş hangisidir?|Kösedağ|Miryokefalon|Malazgirt|Dandanakan|Kösedağ yenilgisi Anadolu Selçuklu Devleti'nin Moğol etkisi altına girmesine yol açtı.
        İlk Türk matbaasını kurmasıyla tanınan İbrahim Müteferrika hangi yüzyılda yaşamıştır?|18. yüzyıl|15. yüzyıl|16. yüzyıl|20. yüzyıl|İbrahim Müteferrika'nın Osmanlı Türkçesiyle kitap basan matbaası 1727'de kuruldu.
        """),
        group(.geography,.medium,"""
        Yerel saat farklarının oluşmasının temel nedeni nedir?|Dünya'nın kendi ekseni etrafında dönmesi|Ay'ın evreleri|Okyanusların tuzluluğu|Kıtaların yükseltisi|Dünya döndükçe farklı boylamlar Güneş karşısından farklı zamanlarda geçer.
        Akdeniz ikliminin tipik yaz özelliği hangisidir?|Sıcak ve kurak|Soğuk ve karlı|Serin ve sürekli yağışlı|Gece gündüz sürekli donlu|Akdeniz ikliminde yazlar sıcak ve kurak, kışlar genellikle ılık ve yağışlıdır.
        Türkiye'nin en uzun kara sınırı hangi ülkeyledir?|Suriye|Yunanistan|Gürcistan|Bulgaristan|Türkiye'nin komşuları arasında en uzun kara sınırı Suriye ile olan sınırıdır.
        Haritada eş yükselti noktalarını birleştiren eğrilere ne denir?|İzohips|İzobar|İzoterm|Meridyen|İzohipsler yükseltisi aynı olan noktaları birleştirir; yer şekillerini göstermede kullanılır.
        Ekvator'dan kutuplara gidildikçe Güneş ışınlarının genel olarak daha eğik gelmesi neyi açıklar?|Ortalama sıcaklığın genel olarak azalmasını|Yer çekiminin tamamen yok olmasını|Denizlerin tatlılaşmasını|Bütün rüzgârların durmasını|Işınlar eğik geldikçe aynı enerji daha geniş alana yayılır; enlem sıcaklık dağılışını etkiler.
        Akarsuyun denize döküldüğü yerde biriktirdiği alüvyonlarla oluşan ova hangisidir?|Delta ovası|Karstik plato|Buzul vadisi|Volkan konisi|Dalga ve akıntı koşulları uygunsa akarsuyun taşıdığı alüvyonlar ağız kesiminde delta oluşturur.
        """),
        group(.geography,.hard,"""
        1/200.000 ölçekli haritada 3 cm gösterilen uzaklık gerçekte kaç kilometredir?|6|0,6|60|600|Haritada 1 cm gerçekte 200.000 cm yani 2 km'dir; 3 cm 6 km eder.
        Kuzey Yarım Küre'de hareket eden hava kütleleri Coriolis etkisiyle hangi yöne sapar?|Hareket yönünün sağına|Hareket yönünün soluna|Daima kuzeye|Daima Güneş'e|Dünya'nın dönüşüne bağlı Coriolis etkisi Kuzey Yarım Küre'de hareketi sağa saptırır.
        Dış kuvvetlerin aşındırmasıyla oluşan mantar kayaların oluşumunda başlıca etken hangisidir?|Rüzgâr|Buzullar|Gelgit|Volkanizma|Rüzgârın taşıdığı kumların yere yakın kesimleri daha fazla aşındırması mantar biçimini oluşturabilir.
        İki meridyen arasındaki boylam farkı 15° ise yerel saat farkı kaç dakikadır?|60|15|30|120|Dünya 24 saatte 360° döner; 1° boylam farkı 4 dakika, 15° fark 60 dakikadır.
        Kireç taşlarının suyla çözünmesiyle oluşan yer şekillerine genel olarak ne denir?|Karstik şekiller|Buzul şekilleri|Volkanik şekiller|Tektonik kıvrımlar|Karstik şekiller, kireç taşı gibi çözünebilen kayaçların su etkisiyle çözünmesi sonucunda gelişir.
        Bir yerde gece ve gündüz süreleri arasındaki yıllık farkın büyüklüğünü temel olarak hangi özellik belirler?|Enlem|Toprak rengi|Nüfus yoğunluğu|Kıyının girintisi|Eksen eğikliği nedeniyle gece-gündüz sürelerinin yıl içindeki değişimi enleme bağlıdır.
        """),
        group(.art,.medium,"""
        Dört Mevsim adlı keman konçertolarının bestecisi kimdir?|Antonio Vivaldi|Ludwig van Beethoven|Frédéric Chopin|Johann Strauss II|Vivaldi'nin Dört Mevsim'i dört keman konçertosundan oluşur ve mevsimleri betimler.
        Don Kişot romanının yazarı kimdir?|Miguel de Cervantes|Victor Hugo|Lev Tolstoy|Charles Dickens|Cervantes'in Don Kişot'u dünya romanının önemli erken örneklerinden biridir.
        Guernica tablosunun ressamı kimdir?|Pablo Picasso|Claude Monet|Salvador Dalí|Rembrandt|Picasso'nun Guernica'sı İspanya İç Savaşı sırasında yaşanan yıkımı konu edinir.
        Mimar Sinan'ın ustalık eseri olarak anılan cami hangisidir?|Selimiye Camii|Süleymaniye Camii|Şehzade Camii|Sultanahmet Camii|Edirne'deki Selimiye Camii, Mimar Sinan'ın ustalık eseri olarak anılır.
        Bir tiyatro oyununda oyuncunun tek başına yaptığı uzun konuşmaya ne denir?|Monolog|Düet|Koro|Pandomim|Monolog tek kişinin konuşmasıdır; diyalog ise karşılıklı konuşmadır.
        Işık ve anlık izlenimlerin öne çıktığı, Monet ile ilişkilendirilen sanat akımı hangisidir?|Empresyonizm|Kübizm|Sürrealizm|Fütürizm|Empresyonizm, Türkçede izlenimcilik olarak da anılır ve ışığın değişken etkisine önem verir.
        """),
        group(.art,.hard,"""
        Bir resimde derinlik etkisi için uzak nesnelerin daha küçük gösterilmesi hangi kavramla ilişkilidir?|Perspektif|Gravür|Kolaj|Mozaik|Perspektif, üç boyutlu mekânın iki boyutlu yüzeyde derinlik etkisiyle gösterilmesini sağlar.
        Müziğin farklı ezgisel çizgilerinin aynı anda birlikte ilerlemesine ne denir?|Kontrpuan|Tek sesli okuma|Sus işareti|Tempo değişimi|Kontrpuan, bağımsız ezgisel çizgilerin birlikte düzenlenmesiyle ilgilidir.
        Tutunamayanlar romanının yazarı kimdir?|Oğuz Atay|Orhan Kemal|Kemal Tahir|Tarık Buğra|Oğuz Atay'ın Tutunamayanlar romanı modern Türk edebiyatının önemli eserlerinden biridir.
        Kafka'nın Dönüşüm adlı eserinin başında böceğe dönüşen karakter kimdir?|Gregor Samsa|Raskolnikov|Jean Valjean|Don Kişot|Gregor Samsa bir sabah kendisini böceğe dönüşmüş halde bulur; eser yabancılaşma temasıyla okunur.
        Resim sanatında ölü doğa olarak da adlandırılan tür hangisidir?|Natürmort|Portre|Peyzaj|Otoportre|Natürmort, meyve, çiçek veya eşyalar gibi cansız nesneleri konu alan resim türüdür.
        Bir heykelin bir yüzeye bağlı olarak kabartma biçiminde yapılmasına ne denir?|Rölyef|Fresk|Vitray|Minyatür|Rölyef yüzeyden yükselen veya yüzeye oyulan kabartmadır; bağımsız bir heykelden bu yönüyle ayrılır.
        """),
        group(.sport,.medium,"""
        Basketbolda serbest atıştan kazanılan sayı kaçtır?|1|2|3|4|Başarılı her serbest atış bir sayıdır; oyun içi atışlar konumuna göre iki veya üç sayı olabilir.
        Teniste sıfır puanı ifade etmek için kullanılan terim hangisidir?|Love|Deuce|Advantage|Let|Tenis puanlamasında love sıfırı, deuce ise belirli bir eşitlik durumunu ifade eder.
        Atletizmde maratonun resmî yarış mesafesi kaç kilometredir?|42,195|40|21,0975|50|Maraton mesafesi 42 kilometre 195 metredir; yarı maraton bunun yarısıdır.
        Voleybolda bir takımın topu rakip sahaya göndermeden önceki normal temas hakkı kaçtır?|3|2|4|5|Takımın normal olarak üç vuruş hakkı vardır; blok teması bu sayıya dahil edilmez.
        Standart bir golf turu genellikle kaç delikten oluşur?|18|9|12|24|Standart tam golf turu 18 delik üzerinden oynanır; bazı sahalar 9 deliklidir.
        Badmintonda oyuncuların raketle karşı tarafa gönderdiği nesne nedir?|Tüytop|Disk|Deri futbol topu|Bovling topu|Badminton, aerodinamik yapısı nedeniyle toptan farklı hareket eden tüytopla oynanır.
        """),
        group(.sport,.hard,"""
        Atletizmde dekatlon kaç farklı yarıştan oluşur?|10|5|7|12|Dekatlon on farklı atletizm yarışının toplam puanıyla değerlendirilir.
        Eskrimde kullanılan üç silahtan biri hangisidir?|Flöre|Kürek|Kroket sopası|Disk|Eskrimde flöre, epe ve kılıç olmak üzere üç silah türü bulunur.
        Satrançta şahın tehdit altında olduğu ve hiçbir yasal hamleyle kurtulamadığı duruma ne denir?|Mat|Pat|Rok|Terfi|Mat durumunda şah tehdidi giderilemez ve oyun biter; patta şah tehdit altında değildir.
        Yüzmede bireysel karışık yarışının ilk stili hangisidir?|Kelebek|Sırtüstü|Kurbağalama|Serbest|Bireysel karışıkta sıra kelebek, sırtüstü, kurbağalama ve serbesttir.
        Basketbolda takımın hücum süresi normalde kaç saniyedir?|24|15|30|45|Hücum saati normalde 24 saniyedir; bazı durumlarda farklı bir süreye sıfırlanabilir.
        Futbolda doğrudan taç atışından top rakip kaleye girerse hangi karar verilir?|Kale vuruşu|Gol|Penaltı|Başlama vuruşu|Taç atışından doğrudan gol olmaz; rakip kaleye girerse kale vuruşu verilir.
        """),
        group(.culture,.medium,"""
        Bilgisayarda bir bayt standart olarak kaç bitten oluşur?|8|4|16|32|Bit iki olası değeri temsil eder; standart bayt sekiz bitten oluşur.
        Bir iddianın gözlem veya deneyle sınanabilir geçici açıklamasına ne denir?|Hipotez|Ön yargı|Slogan|Dedikodu|Hipotez, bilimsel çalışmada sınanabilen bir açıklama veya öngörüdür.
        Bir yılda 366 gün bulunmasına ne ad verilir?|Artık yıl|Işık yılı|Mali yıl|Yarım yıl|Artık yılda şubat 29 gün sürer; böylece takvim yılı 366 gün olur.
        Kabartma noktalarla okuma ve yazma sağlayan sistem hangisidir?|Braille|Mors|İkili kod|Semaphore|Braille, dokunarak okunabilen kabartma nokta örüntülerinden oluşur.
        Bir ürünün tekrar ham maddeye dönüştürülmesine ne denir?|Geri dönüşüm|Buharlaşma|İthalat|Mayalanma|Geri dönüşüm atık malzemenin işlenerek yeniden üretime katılmasını sağlar.
        Güneş ışınlarının su damlacıklarında kırılması ve renklerine ayrılmasıyla görülen olay hangisidir?|Gökkuşağı|Deprem|Gelgit|Kırağı|Su damlacıklarında kırılma, iç yansıma ve renklerin ayrılması gökkuşağını oluşturur.
        """),
        group(.culture,.hard,"""
        Miladi takvimde 1900 yılının artık yıl olmamasının nedeni nedir?|100'e bölünüp 400'e bölünmemesi|4'e bölünmemesi|Bir yüzyılın ilk yılı olması|Şubat ayının hiç bulunmaması|Yüzyıl yılları yalnız 400'e de bölünüyorsa artık yıldır; 1900 bu koşulu sağlamaz.
        İkili sayı sistemindeki 101 sayısının onluk karşılığı kaçtır?|5|3|6|7|101 ikilik sayısı 1×4 + 0×2 + 1×1 hesabıyla 5 eder.
        Aynı koşullarda atılan adil bir zarın çift sayı gelme olasılığı nedir?|1/2|1/3|1/6|2/3|Altı olası sonuçtan 2, 4 ve 6 çift sayıdır; olasılık 3/6 yani 1/2'dir.
        Bir veri grubunda en sık tekrarlanan değere ne denir?|Mod|Medyan|Aritmetik ortalama|Açıklık|Mod en sık gözlenen değerdir; bir veri grubunun birden fazla modu olabilir.
        Bütün kareler dikdörtgense, bir şeklin kare olduğu bilindiğinde hangi sonuç kesin çıkar?|Dikdörtgendir|Eşkenar üçgendir|Çemberdir|Kenar sayısı beştir|Kare, dikdörtgenin özel bir türüdür; bütün açıları dik ve karşılıklı kenarları paraleldir.
        Bir metindeki başka bir kaynağa gönderme yapan açıklama veya işarete ne denir?|Atıf|İstiare|Kafiye|Redif|Atıf, kullanılan bilgi veya görüşün kaynağına gönderme yapar.
        """),
        group(.cinema,.medium,"""
        Bir filmin olaylarının gerçekleşme sırasından daha önceki bir ana dönmesine ne denir?|Geriye dönüş|Yakın plan|Ağır çekim|Pan|Geriye dönüş, anlatının geçmişteki bir olayı göstermesidir; kamera hareketi değildir.
        Kamera sabit konumdayken sağa veya sola çevrilmesine ne denir?|Pan|Dolly|Zoom|Kurgu|Pan, kameranın bulunduğu noktada yatay eksende çevrilmesidir; zoom odak uzaklığının değişmesidir.
        Animasyonda nesnelerin küçük aralıklarla hareket ettirilip tek tek fotoğraflanması hangi tekniktir?|Stop motion|Canlı yayın|Dublaj|Renk düzeltme|Stop motion'da ardışık fotoğraflar oynatılınca fiziksel nesneler hareket ediyormuş gibi görünür.
        Filmin sonunda oyuncu ve ekip adlarının gösterildiği bölüme genel olarak ne denir?|Bitiş jeneriği|Fragman|Storyboard|Sahne provası|Bitiş jeneriği, yapımda görev alan kişileri ve kurumları listeler.
        Çekimden önce sahnelerin çizimlerle planlanmasına verilen ad hangisidir?|Storyboard|Soundtrack|Dublaj|Kostüm provası|Storyboard, çekimlerin görsel sırasını ve kompozisyonunu önceden tasarlamaya yardım eder.
        Gerçek kişi, olay veya konuları araştırmacı bir yaklaşımla ele alan film türü hangisidir?|Belgesel|Müzikal|Fantastik|Romantik komedi|Belgesel gerçek dünyayı konu edinir; yine de anlatım ve kurgu tercihleri içerir.
        """),
        group(.cinema,.hard,"""
        Seyircinin duyduğu ama öyküdeki karakterlerin duymadığı arka plan müziği hangi ses türüne örnektir?|Öykü dışı ses|Diyalog|Öykü içi ses|Set ortam sesi|Öykü dışı ses, sahnenin kurmaca dünyasındaki bir kaynaktan gelmez; fon müziği yaygın bir örnektir.
        Aynı olayın iki farklı mekândaki parçalarını dönüşümlü gösteren kurguya ne denir?|Paralel kurgu|Tek plan|Sabit çekim|Netlik kaydırma|Paralel kurgu, farklı eylemleri dönüşümlü göstererek aralarında zamansal veya tematik ilişki kurar.
        Çekimde alan derinliğinin az olması hangi görüntüyü oluşturur?|Dar bir uzaklık aralığı net görünür|Her uzaklık eşit net görünür|Bütün renkler kaybolur|Görüntü zorunlu olarak ters döner|Sığ alan derinliği belirli bir düzlemi net tutarken önünü ve arkasını bulanıklaştırabilir.
        Bir sahneyi kesintisiz tek çekimle gösteren uzun çekime ne denir?|Plan sekans|Atlamalı kurgu|Bindirme|Kararma|Plan sekans bir sahne veya anlatı bölümünün kesintisiz tek çekimle aktarılmasıdır.
        Filmde hareketli bir nesneyi izlemek için kameranın fiziksel olarak yer değiştirmesine ne denir?|Takip çekimi|Sabit plan|Sadece zoom|Dondurulmuş kare|Takip çekiminde kamera mekân içinde hareket ederek nesneyi izler; zoom'da kamera konumu değişmek zorunda değildir.
        Bir karakterin gördüğü şeyi onun bakış açısından gösteren çekim hangisidir?|Öznel çekim|Genel plan|Üst açı|Establishing shot|Öznel çekim seyirciyi karakterin görsel bakış açısına yerleştirir.
        """),
        group(.language,.easy,"""
        İngilizce 'book' kelimesinin Türkçe karşılığı hangisidir?|Kitap|Kalem|Masa|Kapı|Book bir isim olarak kitap anlamına gelir; bu soruda fiil anlamı kullanılmamıştır.
        İngilizce 'I am a student' cümlesinin karşılığı hangisidir?|Ben öğrenciyim|Sen öğretmensin|Biz doktoruz|Onlar evdeler|I birinci tekil kişidir; a student öğrenci anlamına gelir.
        Almanca 'Guten Morgen' hangi Türkçe selamlamaya karşılık gelir?|Günaydın|İyi geceler|Hoşça kal|Özür dilerim|Guten Morgen sabah kullanılan bir selamlamadır.
        Fransızca 'merci' sözcüğü ne anlama gelir?|Teşekkürler|Merhaba|Lütfen|Yarın|Merci, Fransızcada teşekkür etmek için kullanılır.
        """),
        group(.language,.medium,"""
        İngilizcede 'She ___ to school every day' boşluğuna hangisi gelir?|goes|go|going|gone|Geniş zamanda üçüncü tekil kişiyle go fiili goes biçimini alır.
        İngilizce 'although' bağlacı hangi anlamı taşır?|Her ne kadar ... olsa da|Bu yüzden|Örneğin|Böylece|Although iki ifade arasında karşıtlık veya beklenmedik bir durum kurar.
        İspanyolcada 'biblioteca' hangi mekânı ifade eder?|Kütüphane|Eczane|Fırın|Havaalanı|Biblioteca kütüphane demektir; kitapçı için librería kullanılır.
        İngilizcede 'I have lived here since 2020' cümlesindeki since neyi belirtir?|Başlangıç zamanını|Tekrar sayısını|Gelecek hedefini|Yer adını|Since bir başlangıç noktasını, for ise bir süre uzunluğunu belirtir.
        """),
        group(.language,.hard,"""
        İngilizcede 'If I had studied, I ___ passed' cümlesi nasıl tamamlanır?|would have|will have|would|had|Geçmişte gerçekleşmemiş bir koşul için üçüncü tip koşul yapısında would have ve fiilin üçüncü biçimi kullanılır.
        İngilizcede 'Neither of the answers is correct' ne anlama gelir?|İki cevabın da hiçbiri doğru değildir|İki cevap da doğrudur|Yalnız ilk cevap doğrudur|En az üç cevap doğrudur|Neither iki seçenekten hiçbirini belirtir; both ise ikisini de ifade eder.
        İngilizcede 'The task must be completed by noon' cümlesinin çatısı hangisidir?|Edilgen|Etken|Dönüşlü|İşteş|Must be completed yapısı edilgendir; işi yapan kişi yerine tamamlanacak iş öne çıkarılır.
        İngilizcede 'Despite the rain, they left' ifadesinin anlamı hangisidir?|Yağmura rağmen ayrıldılar|Yağmur yüzünden ayrıldılar|Yağmur başlamadan ayrıldılar|Ayrıldıkları için yağmur yağdı|Despite karşıtlığa rağmen gerçekleşen bir eylemi belirtir; neden bildirmez.
        """),
        group(.exam,.easy,"""
        80 sayısının yüzde 25'i kaçtır?|20|10|25|40|Yüzde 25 dörtte birdir; 80'i 4'e bölünce 20 bulunur.
        Bir üçgenin iç açılarının toplamı Öklid düzleminde kaç derecedir?|180|90|270|360|Öklid geometrisinde üçgenin iç açıları toplamı 180 derecedir.
        'Kalemler' sözcüğündeki '-ler' hangi görevde kullanılmıştır?|Çoğul eki|İyelik eki|Zaman eki|Olumsuzluk eki|Çoğul eki isimlerin birden fazla varlığı karşılamasını sağlar.
        Bitki hücresinde bulunup hayvan hücresinde bulunmayan yapılardan biri hangisidir?|Hücre duvarı|Hücre zarı|Ribozom|Sitoplazma|Bitki hücresinin dışında selüloz içeren hücre duvarı bulunur; diğer üç yapı her iki hücrede de vardır.
        """),
        group(.exam,.medium,"""
        3x + 5 = 20 eşitliğini sağlayan x değeri kaçtır?|5|3|7|15|Her iki taraftan 5 çıkarılınca 3x=15 olur; 3'e bölünce x=5 bulunur.
        Bir ürünün fiyatı 200 TL'den 250 TL'ye çıkarsa artış yüzde kaçtır?|25|20|50|75|Artış 50 TL'dir; başlangıç fiyatına oranı 50/200=0,25 yani yüzde 25'tir.
        'Eve gelince seni ararım' cümlesindeki 'gelince' hangi sözcük türündedir?|Zarf-fiil|İsim-fiil|Sıfat-fiil|Çekimli fiil|Gelince, -ince ekiyle zaman anlamı kuran bir zarf-fiildir.
        Bir devrede direnç sabitken gerilim iki katına çıkarılırsa akım nasıl değişir?|İki katına çıkar|Yarıya iner|Değişmez|Sıfır olur|Ohm yasasına göre I=V/R'dir; direnç sabitken akım gerilimle doğru orantılıdır.
        """),
        group(.exam,.hard,"""
        1'den 100'e kadar olan pozitif tam sayıların toplamı kaçtır?|5050|5000|4950|10000|İlk n pozitif tam sayının toplamı n(n+1)/2'dir; 100×101/2=5050 bulunur.
        İki adil para atıldığında tam birinin yazı gelme olasılığı nedir?|1/2|1/4|3/4|1|YY, YT, TY ve TT eş olasılıklı dört sonuçtur; YT ve TY koşulu sağlar.
        x² − 5x + 6 = 0 denkleminin kökleri hangileridir?|2 ve 3|1 ve 6|−2 ve −3|−1 ve −6|İfade (x−2)(x−3) biçiminde çarpanlarına ayrılır; kökler 2 ve 3'tür.
        Genotipi Aa olan iki bireyin çaprazlanmasında aa genotipli yavrunun olasılığı nedir?|1/4|1/2|3/4|1|Aa×Aa çaprazlamasında AA, Aa, Aa ve aa genotipleri oluşur; aa olasılığı dörtte birdir.
        """)
    ].flatMap { $0 }
}
