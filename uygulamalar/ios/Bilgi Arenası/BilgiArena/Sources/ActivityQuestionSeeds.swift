import Foundation

enum ActivityQuestionSeeds {
    static let questions: [Question] = [
        Question(text:"Dinlediğin metne göre Mina'nın çantası hangi renktir?",options:["Mavi","Kırmızı","Sarı","Yeşil"],answer:0,explanation:"Metindeki 'blue bag' ifadesi mavi çanta anlamına gelir. Ulaşım bilgisi sorunun cevabını değiştirmez.",category:.language,difficulty:.easy,
                 activity:.init(kind:.listening,title:"İngilizce kısa dinleme",transcript:"Mina has a blue bag. She takes a bus to school.",language:"en-US")),
        ordered("Sayıları küçükten büyüğe sırala.",title:"Sayı merdiveni",items:["30","10","40","20"],solution:[1,3,0,2],explanation:"Onluklar basamağı karşılaştırılır: 10 < 20 < 30 < 40.",category:.exam,difficulty:.easy),
        matched("İngilizce sözcükleri Türkçe karşılıklarıyla eşleştir.",title:"Sözcük köprüsü",left:["Cat","Book","Water","Sun"],right:["Güneş","Kedi","Su","Kitap"],solution:[1,3,2,0],explanation:"Cat kedi, book kitap, water su ve sun güneş demektir.",category:.language,difficulty:.easy),
        Question(text:"Dinlediğin metne göre Ece kitabı hangi gün ödünç almıştır?",options:["Salı","Cuma","Pazartesi","Cumartesi"],answer:0,explanation:"Ece kitabı salı günü almıştır. Cuma günü ise kitabı geri vermeyi planlamıştır; alma ve geri verme zamanı farklıdır.",category:.culture,difficulty:.easy,
                 activity:.init(kind:.listening,title:"Kısa hikâyeyi dinle",transcript:"Ece salı günü kütüphaneden bir kitap ödünç aldı. Kitabı cuma günü geri vermeyi planladı.",language:"tr-TR")),
        ordered("Olayları gerçekleşme tarihlerine göre eskiden yeniye sırala.",title:"Tarih yolculuğu",items:["TBMM'nin açılması","Cumhuriyet'in ilanı","Samsun'a çıkış","Lozan'ın imzalanması"],solution:[2,0,3,1],explanation:"Samsun'a çıkış 19 Mayıs 1919; TBMM'nin açılması 23 Nisan 1920; Lozan'ın imzalanması 24 Temmuz 1923; Cumhuriyet'in ilanı 29 Ekim 1923'tür.",category:.history,difficulty:.medium),
        matched("Organları temel görevleriyle bire bir eşleştir.",title:"Vücudumuzdaki görevler",left:["Kalp","Beyin","Akciğer","Böbrek"],right:["Kanı süzer","Kanı pompalar","Sinirsel yönetim sağlar","Gaz alışverişi yapar"],solution:[1,2,3,0],explanation:"Kalp kanı pompalar; beyin sinir sisteminin yönetim merkezidir. Akciğerlerde gaz alışverişi, böbreklerde kanın süzülmesi gerçekleşir.",category:.science,difficulty:.easy),
        Question(text:"Dinlediğin anlatımda yönetmen genel plandan sonra hangi çekimi seçmiştir?",options:["Yakın plan","Genel plan","Kuş bakışı","Uzak plan"],answer:0,explanation:"Anlatımda önce mekânı tanıtan genel plan, ardından oyuncunun yüzündeki duyguyu vurgulayan yakın plan kullanılır.",category:.cinema,difficulty:.medium,
                 activity:.init(kind:.listening,title:"Bir sahnenin anlatımı",transcript:"Yönetmen önce sokağı gösteren bir genel plan kullandı. Ardından oyuncunun yüzündeki duyguyu göstermek için yakın plana geçti.",language:"tr-TR")),
        ordered("Normal basınçta, sıfırın altındaki buz sürekli ısıtılıyor. Süreçleri başlangıçtan kaynamaya kadar sırala.",title:"Isınma ve hâl değişimi",items:["Kaynama","Erime","Buzun ısınması","Sıvı suyun ısınması"],solution:[2,1,3,0],explanation:"Önce buz erime sıcaklığına kadar ısınır, sonra erir. Oluşan sıvı su kaynama sıcaklığına kadar ısınır ve ardından kaynama başlar.",category:.science,difficulty:.medium),
        matched("Ülkeleri bulundukları kıtalarla eşleştir.",title:"Dünya üzerinde eşleştir",left:["Japonya","Brezilya","Gana","İtalya"],right:["Afrika","Avrupa","Asya","Güney Amerika"],solution:[2,3,0,1],explanation:"Japonya Asya'da, Brezilya Güney Amerika'da, Gana Afrika'da ve İtalya Avrupa'dadır.",category:.geography,difficulty:.medium),
        Question(text:"İngilizce selamlama ifadesini dinle ve kendin söyle.",options:["A","B","C","D"],answer:0,explanation:"Good morning, sabah kullanılan bir selamlamadır. Buradaki geri bildirim, söylenen ifadenin tanınmasına dayanır; aksan puanı değildir.",category:.language,difficulty:.easy).replacingActivity(.init(kind:.pronunciation,title:"Günaydın de",transcript:"Good morning",language:"en-US")),
        Question(text:"İspanyolca teşekkür ifadesini dinle ve kendin söyle.",options:["A","B","C","D"],answer:0,explanation:"Muchas gracias, çok teşekkür ederim anlamına gelir. Kelimeleri örneği dinleyerek birlikte söylemeyi deneyebilirsin.",category:.language,difficulty:.easy).replacingActivity(.init(kind:.pronunciation,title:"Teşekkür et",transcript:"Muchas gracias",language:"es-ES")),
        Question(text:"Almanca rica ifadesini dinle ve kendin söyle.",options:["A","B","C","D"],answer:0,explanation:"Bitte schön, bağlama göre buyurun veya rica ederim anlamına gelir. Alıştırma hedef ifadenin tanınıp tanınmadığını gösterir.",category:.language,difficulty:.easy).replacingActivity(.init(kind:.pronunciation,title:"Rica ederim de",transcript:"Bitte schön",language:"de-DE"))
    ]
    static func ordered(_ text: String,title: String,items: [String],solution: [Int],explanation: String,category: Topic,difficulty: Difficulty) -> Question {
        base(text,explanation:explanation,category:category,difficulty:difficulty).replacingActivity(.init(kind:.ordering,title:title,items:items,solution:solution))
    }
    static func matched(_ text: String,title: String,left: [String],right: [String],solution: [Int],explanation: String,category: Topic,difficulty: Difficulty) -> Question {
        base(text,explanation:explanation,category:category,difficulty:difficulty).replacingActivity(.init(kind:.matching,title:title,left:left,right:right,solution:solution))
    }
    private static func base(_ text: String,explanation: String,category: Topic,difficulty: Difficulty) -> Question {
        Question(text:text,options:["A","B","C","D"],answer:0,explanation:explanation,category:category,difficulty:difficulty)
    }
}
