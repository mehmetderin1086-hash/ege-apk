import Foundation

enum VisualQuestionSeeds {
    private static func q(_ text: String, _ options: [String], _ answer: Int, _ explanation: String, _ topic: Topic, _ visual: QuestionVisual) -> Question {
        Question(text:text,options:options,answer:answer,explanation:explanation,category:topic,difficulty:.easy,visual:visual)
    }
    static let questions: [Question] = [
        q("Şekilde kenar uzunlukları verilen dikdörtgenin alanı kaç cm²'dir?",["40","26","13","80"],0,"Dikdörtgenin alanı iki komşu kenarın çarpımıdır: 8 × 5 = 40 cm².",.exam,
          QuestionVisual(kind:.diagram,title:"Kenar uzunlukları",summary:"Dikdörtgenin yatay kenarı 8 cm, düşey kenarı 5 cm olarak verilmiştir. Çizim ölçekli değildir.",elements:[
            VisualElement(shape:.rectangle,x:50,y:52,width:60,height:48),VisualElement(shape:.text,x:50,y:16,label:"8 cm"),VisualElement(shape:.text,x:88,y:52,label:"5 cm") ])),
        q("Görseldeki çalgı, sesin oluşturulma biçimine göre hangi gruptadır?",["Yaylı telli çalgılar","Üflemeli çalgılar","Vurmalı çalgılar","Elektronik klavyeler"],0,"Keman, yayla tellerin titreştirilmesiyle ses çıkaran yaylı telli bir çalgıdır.",.art,
          QuestionVisual(kind:.image,title:"Çalgıyı incele",summary:"Çalgının gövdesi, telleri ve yanında bir yay görülüyor.",imageID:"violin")),
        q("Tabloya göre L örneğinin sıcaklığı K örneğinden kaç °C fazladır?",["15","20","35","5"],0,"L örneği 35 °C, K örneği 20 °C'dir. Aradaki fark 35 − 20 = 15 °C olur.",.science,
          QuestionVisual(kind:.table,title:"Örnek sıcaklıkları",summary:"K, L ve M örneklerinin sıcaklıkları sırasıyla 20, 35 ve 15 santigrat derecedir.",columns:["Örnek","Sıcaklık (°C)"],rows:[["K","20"],["L","35"],["M","15"]])),
        q("Örnek yağış grafiğine göre üç ayın toplam yağışı kaç mm'dir?",["100","80","50","120"],0,"Grafikteki üç değer toplanır: 30 + 50 + 20 = 100 mm. Bunlar alıştırma için oluşturulmuş verilerdir.",.geography,
          QuestionVisual(kind:.barChart,title:"Örnek aylık yağış verileri",summary:"Nisan 30 mm, mayıs 50 mm ve haziran 20 mm yağış olarak gösterilmiştir.",labels:["Nisan","Mayıs","Haziran"],values:[30,50,20],unit:"mm")),
        q("Örnek antrenman grafiğinde hangi iki gün arasında koşulan mesafe azalmıştır?",["Salı–Çarşamba","Pazartesi–Salı","Çarşamba–Perşembe","Pazartesi–Perşembe"],0,"Mesafe salı günü 4 km iken çarşamba günü 3 km'ye iner. Diğer ardışık günlerde artış vardır.",.sport,
          QuestionVisual(kind:.lineChart,title:"Örnek antrenman günlüğü",summary:"Pazartesi 2, salı 4, çarşamba 3 ve perşembe 5 kilometre koşulmuştur.",labels:["Pzt","Salı","Çarş.","Perş."],values:[2,4,3,5],unit:"km")),
        q("Görseldeki yaprağın yeşil görünmesinde başlıca rol oynayan pigment hangisidir?",["Klorofil","Melanin","Hemoglobin","Miyoglobin"],0,"Klorofil ışığın bazı dalga boylarını soğurur; yeşil ışığın daha fazla yansıtılması yaprağın yeşil görünmesine katkı sağlar.",.science,
          QuestionVisual(kind:.image,title:"Yaprağı incele",summary:"Yeşil bir yaprak ve yaprağın dallanan damarları görülüyor.",imageID:"leaf")),
        q("Görseldeki taşıtta pedalın hareketini arka tekerleğe ileten parça hangisidir?",["Zincir","Sele","Gidon","Çamurluk"],0,"Bisiklette zincir, pedalın döndürdüğü ön dişliden arka dişliye hareket aktarır.",.sport,
          QuestionVisual(kind:.image,title:"Mekanizmayı incele",summary:"Taşıt yandan görülüyor; pedallar, dişliler, zincir ve iki tekerlek seçiliyor.",imageID:"bicycle")),
        q("Şekilde gösterilen dört geometrik nesneden kaçı üçgendir?",["2","1","3","4"],0,"Sol üstte ve sağ altta birer üçgen vardır. Diğer iki nesne daire ve dikdörtgendir.",.culture,
          QuestionVisual(kind:.diagram,title:"Şekilleri karşılaştır",summary:"Sol üstte üçgen, sağ üstte daire, sol altta dikdörtgen ve sağ altta üçgen gösteriliyor.",elements:[
            VisualElement(shape:.triangle,x:27,y:27,width:30,height:30,color:.blue),VisualElement(shape:.circle,x:73,y:27,width:25,height:30,color:.gold),
            VisualElement(shape:.rectangle,x:27,y:74,width:34,height:24,color:.pink),VisualElement(shape:.triangle,x:73,y:73,width:30,height:30,color:.violet)])),
        q("Tablodaki İngilizce kelimelere göre 'big' sözcüğünün zıt anlamlısı hangisidir?",["small","fast","warm","new"],0,"Big büyük, small küçük demektir. Bu iki sözcük zıt anlamlıdır.",.language,
          QuestionVisual(kind:.table,title:"Mini kelime tablosu",summary:"Big büyük, small küçük, fast hızlı ve warm sıcak anlamlarıyla verilmiştir.",columns:["İngilizce","Türkçe"],rows:[["big","büyük"],["small","küçük"],["fast","hızlı"],["warm","sıcak"]])),
        q("Örnek sınıf anketi grafiğinde en çok tercih edilen film türü hangisidir?",["Komedi","Animasyon","Belgesel","Üçü de eşit"],0,"Komedi 12 oyla, animasyonun 8 ve belgeselin 4 oyundan daha fazla tercih edilmiştir.",.cinema,
          QuestionVisual(kind:.barChart,title:"Örnek film türü anketi",summary:"Komedi 12, animasyon 8 ve belgesel 4 oy almıştır. Veriler alıştırma içindir.",labels:["Komedi","Animasyon","Belgesel"],values:[12,8,4],unit:"oy")),
        q("Örnek okuma grafiğinde pazartesiden perşembeye günlük sayfa sayısı ne kadar artmıştır?",["15 sayfa","10 sayfa","25 sayfa","5 sayfa"],0,"Pazartesi 10 ve perşembe 25 sayfa okunmuştur. Artış 25 − 10 = 15 sayfadır.",.culture,
          QuestionVisual(kind:.lineChart,title:"Örnek okuma günlüğü",summary:"Günlük sayfa sayısı pazartesi 10, salı 15, çarşamba 20 ve perşembe 25'tir.",labels:["Pzt","Salı","Çarş.","Perş."],values:[10,15,20,25],unit:"sayfa")),
        q("Zaman çizelgesinde 1920 yılına yerleştirilen olay hangisidir?",["TBMM'nin açılması","Cumhuriyet'in ilanı","Atatürk'ün Samsun'a çıkışı","İstanbul'un fethi"],0,"Türkiye Büyük Millet Meclisi 23 Nisan 1920'de açıldı. Samsun'a çıkış 1919, Cumhuriyet'in ilanı 1923'tedir.",.history,
          QuestionVisual(kind:.diagram,title:"Millî Mücadele'den Cumhuriyet'e",summary:"Soldan sağa 1919 Samsun'a çıkış, 1920 TBMM'nin açılması ve 1923 Cumhuriyet'in ilanı yer alıyor. Tarih aralıkları ölçekli değildir.",elements:[
            VisualElement(shape:.arrow,x:12,y:65,endX:90,endY:65),VisualElement(shape:.point,x:18,y:65,color:.blue),VisualElement(shape:.point,x:50,y:65,color:.gold),VisualElement(shape:.point,x:82,y:65,color:.pink),
            VisualElement(shape:.text,x:18,y:37,label:"1919\nSamsun"),VisualElement(shape:.text,x:50,y:37,label:"1920\nTBMM"),VisualElement(shape:.text,x:82,y:37,label:"1923\nCumhuriyet")]))
    ]
}
