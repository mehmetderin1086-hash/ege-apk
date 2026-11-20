import Foundation

enum Seed {
    static let questions: [Question] = {
        let rows: [(Topic, String, [String], String)] = [
            (.science,"Dünya'nın doğal uydusu hangisidir?",["Ay","Mars","Venüs","Güneş"],"Ay, Dünya'nın bilinen tek doğal uydusudur."),
            (.science,"Suyun kimyasal formülü hangisidir?",["H₂O","CO₂","O₂","NaCl"],"Bir su molekülünde iki hidrojen ve bir oksijen atomu bulunur."),
            (.science,"Bitkiler fotosentez sırasında havadan hangi gazı alır?",["Karbondioksit","Oksijen","Azot","Helyum"],"Fotosentezde karbondioksit ve su kullanılarak organik madde üretilir."),
            (.science,"Güneş Sistemi'nin en büyük gezegeni hangisidir?",["Jüpiter","Mars","Merkür","Venüs"],"Jüpiter, Güneş Sistemi'ndeki en büyük gezegendir."),
            (.science,"İnsan vücudunda kanı pompalayan organ hangisidir?",["Kalp","Akciğer","Böbrek","Mide"],"Kalp, kasılarak kanın dolaşım sisteminde hareket etmesini sağlar."),
            (.science,"Ses boşlukta nasıl yayılır?",["Yayılmaz","Işık hızında","Sadece geceleri","Su dalgasıyla"],"Ses mekanik bir dalgadır; yayılması için maddesel bir ortam gerekir."),
            (.history,"Türkiye Cumhuriyeti hangi yıl ilan edildi?",["1923","1919","1938","1920"],"Türkiye Cumhuriyeti 29 Ekim 1923 tarihinde ilan edildi."),
            (.history,"İstanbul'un fethi hangi yıl gerçekleşti?",["1453","1071","1299","1517"],"İstanbul, 1453 yılında II. Mehmet döneminde fethedildi."),
            (.history,"Kurtuluş Savaşı sırasında açılan Büyük Millet Meclisi hangi şehirdeydi?",["Ankara","İzmir","İstanbul","Bursa"],"Türkiye Büyük Millet Meclisi 23 Nisan 1920'de Ankara'da açıldı."),
            (.history,"Malazgirt Meydan Muharebesi hangi yılda yapıldı?",["1071","1453","1923","1699"],"Malazgirt Muharebesi, 1071 yılında Selçuklular ile Bizans arasında gerçekleşti."),
            (.history,"Yazıyı ilk geliştiren uygarlık hangisidir?",["Sümerler","Hititler","Frigler","Urartular"],"Sümerler, Mezopotamya'da çivi yazısının ilk örneklerini geliştirdi."),
            (.history,"Nutuk adlı eserin yazarı kimdir?",["Mustafa Kemal Atatürk","Namık Kemal","Ziya Gökalp","Yahya Kemal Beyatlı"],"Nutuk, Mustafa Kemal Atatürk'ün Kurtuluş Savaşı ve Cumhuriyet'in kuruluşunu anlattığı söylevdir."),
            (.geography,"Türkiye'nin yüzölçümü bakımından en büyük ili hangisidir?",["Konya","Ankara","İstanbul","İzmir"],"Konya, Türkiye'nin yüzölçümü bakımından en büyük ilidir."),
            (.geography,"Türkiye'nin başkenti neresidir?",["Ankara","İstanbul","Bursa","İzmir"],"Ankara, 13 Ekim 1923'te Türkiye'nin başkenti oldu."),
            (.geography,"Dünyanın yüzölçümü en büyük okyanusu hangisidir?",["Pasifik Okyanusu","Atlas Okyanusu","Hint Okyanusu","Arktik Okyanusu"],"Pasifik, diğer adıyla Büyük Okyanus, yüzölçümü en büyük okyanustur."),
            (.geography,"Mısır'dan geçerek Akdeniz'e dökülen nehir hangisidir?",["Nil","Amazon","Tuna","Fırat"],"Nil Nehri kuzeye akar ve Mısır'da Akdeniz'e ulaşır."),
            (.geography,"Ekvator Dünya'yı hangi iki yarım küreye ayırır?",["Kuzey ve Güney","Doğu ve Batı","Asya ve Avrupa","Kara ve Deniz"],"Ekvator, Dünya'yı Kuzey ve Güney yarım kürelerine ayıran hayalî çizgidir."),
            (.geography,"Türkiye'nin en büyük gölü hangisidir?",["Van Gölü","Tuz Gölü","Beyşehir Gölü","Eğirdir Gölü"],"Van Gölü, yüzölçümü bakımından Türkiye'nin en büyük gölüdür."),
            (.art,"İstiklâl Marşı'nın sözlerini kim yazmıştır?",["Mehmet Âkif Ersoy","Tevfik Fikret","Orhan Veli","Yunus Emre"],"İstiklâl Marşı'nın sözleri Mehmet Âkif Ersoy tarafından yazılmıştır."),
            (.art,"Mona Lisa tablosunun ressamı kimdir?",["Leonardo da Vinci","Vincent van Gogh","Pablo Picasso","Claude Monet"],"Mona Lisa, Rönesans sanatçısı Leonardo da Vinci'nin eseridir."),
            (.art,"İnce Memed romanının yazarı kimdir?",["Yaşar Kemal","Orhan Pamuk","Sait Faik","Sabahattin Ali"],"İnce Memed, Yaşar Kemal'in roman serisidir."),
            (.art,"Bir orkestrayı yöneten kişiye ne denir?",["Şef","Solist","Koreograf","Küratör"],"Orkestra şefi, müzisyenleri tempo ve yorum bakımından yönlendirir."),
            (.art,"Geleneksel ebru sanatı hangi yüzey üzerinde yapılır?",["Su","Taş","Cam","Ahşap"],"Ebruda boyalar yoğunlaştırılmış su yüzeyinde şekillendirilip kâğıda aktarılır."),
            (.art,"Dede Korkut Hikâyeleri hangi edebiyatın ürünüdür?",["Türk edebiyatı","Latin edebiyatı","İskandinav edebiyatı","Japon edebiyatı"],"Dede Korkut Hikâyeleri, Oğuz Türklerinin kültürünü yansıtan anlatılardır."),
            (.sport,"Bir futbol takımı sahada kaleci dahil kaç oyuncuyla başlar?",["11","9","10","12"],"Futbolda bir takım sahaya kaleci dahil en fazla 11 oyuncuyla çıkar."),
            (.sport,"Basketbolda serbest atış isabeti kaç puandır?",["1","2","3","4"],"Başarılı bir serbest atış basketbolda bir puan kazandırır."),
            (.sport,"Olimpiyat simgesinde kaç halka bulunur?",["5","4","6","7"],"Olimpiyat simgesi birbirine geçen beş halkadan oluşur."),
            (.sport,"Teniste sıfır sayı İngilizce hangi kelimeyle ifade edilir?",["Love","Zero","Blank","Nil"],"Teniste sıfır puan için geleneksel olarak 'love' sözcüğü kullanılır."),
            (.sport,"Voleybolda bir takım sahada kaç oyuncuyla bulunur?",["6","5","7","11"],"Salon voleybolunda her takımın sahada altı oyuncusu vardır."),
            (.sport,"Maratonun standart mesafesi yaklaşık kaç kilometredir?",["42,195","10","21","100"],"Standart maraton mesafesi 42 kilometre 195 metredir."),
            (.culture,"Bir yılda kaç ay vardır?",["12","10","11","13"],"Miladi takvimde bir yıl on iki aydan oluşur."),
            (.culture,"Türk alfabesinde kaç harf vardır?",["29","26","28","30"],"1928'de kabul edilen Türk alfabesi 29 harften oluşur."),
            (.culture,"Bir düzine kaç adettir?",["12","10","6","20"],"Düzine, on iki adetlik bir sayma birimidir."),
            (.culture,"Hangi gün haftanın ilk günüdür?",["Pazartesi","Salı","Pazar","Cuma"],"Türkiye'de kullanılan ISO hafta düzeninde hafta pazartesi başlar."),
            (.culture,"Hangisi bir renk değildir?",["Üçgen","Mavi","Yeşil","Sarı"],"Üçgen geometrik bir şekildir; diğer seçenekler renktir."),
            (.culture,"Hangi ay 28 gün çeker?",["Bütün aylar","Yalnızca şubat","Yalnızca ocak","Yalnızca nisan"],"Bütün aylar en az 28 gün içerir; şubat normal yılda 28 gündür."),
            (.cinema,"Film çekiminde sahneleri yöneten kişi kimdir?",["Yönetmen","Besteci","Seyirci","Dağıtımcı"],"Yönetmen, filmin sanatsal ve teknik anlatımını yönlendirir."),
            (.cinema,"Kamera önünde bir karakteri canlandıran kişiye ne denir?",["Oyuncu","Montajcı","Senarist","Yapımcı"],"Oyuncu, film veya dizide bir karakteri canlandırır."),
            (.cinema,"Çekilen görüntülerin sıralanması işlemine ne ad verilir?",["Kurgu","Dublaj","Dekor","Afiş"],"Kurgu, çekilen görüntü ve seslerin seçilip düzenlenmesidir."),
            (.cinema,"Filmin öyküsünü ve sahnelerini yazan kişi kimdir?",["Senarist","Işıkçı","Oyuncu","Seyirci"],"Senarist, filmin ya da dizinin senaryosunu yazar."),
            (.cinema,"Bir filmin müziklerine genel olarak ne denir?",["Film müziği","Jenerik","Fragman","Senaryo"],"Film müziği, yapım için bestelenen veya seçilen müzikleri kapsar."),
            (.cinema,"Bir filmin kısa tanıtım videosu nedir?",["Fragman","Perde","Kulis","Altyazı"],"Fragman, bir yapımın tanıtımı için hazırlanan kısa görüntü seçkisidir.")
        ]
        return rows.map { row in
            let indexed = row.2.enumerated().shuffled()
            return Question(text: row.1, options: indexed.map(\.element), answer: indexed.firstIndex { $0.offset == 0 }!, explanation: row.3, category: row.0, difficulty: .easy)
        } + SeedExpansion.questions + VisualQuestionSeeds.questions + ActivityQuestionSeeds.questions
    }()
}
