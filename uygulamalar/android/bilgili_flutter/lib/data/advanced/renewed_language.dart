// Broad language blocks combine items from the same teaching domain.
// The selected words, claims, conditions and events supply evidence used
// in the response, rather than furnishing cosmetic scenario identifiers.
import 'common.dart';

typedef _Lex = (String, String);
typedef _TextBuilder = AdvancedItem Function(int);

AdvancedFamily _langFamily(
  String key,
  String title,
  Topic topic,
  bool uni,
  BloomLevel bloom,
  _TextBuilder build, {
  ActivityKind? activity,
  bool blank = false,
  CreationTask Function(AdvancedItem, int)? creation,
}) => AdvancedFamily(
  key: 'renew_lang_$key',
  title: title,
  topic: topic,
  level: uni ? StudyLevel.universite : StudyLevel.lise,
  difficulty: uni ? Difficulty.hard : Difficulty.medium,
  count: 5000,
  bloom: bloom,
  build: build,
  activityKind: activity,
  shortAnswer: blank,
  creation: creation,
);

List<_Lex> _entries(String source) => source
    .trim()
    .split('\n')
    .map((l) {
      final parts = l.split('|');
      return (parts[0], parts[1]);
    })
    .toList(growable: false);

int _choose(int n, int k) {
  if (n < k) return 0;
  var r = 1;
  for (var j = 1; j <= k; j++) {
    r = r * (n - j + 1) ~/ j;
  }
  return r;
}

List<T> _subset<T>(List<List<T>> groups, int n, int index, {int quota = 5000}) {
  final total = groups.fold<int>(0, (sum, g) => sum + _choose(g.length, n));
  if (total < quota) throw StateError('Yetersiz içerik grubu: $total');
  var offset = index * total ~/ quota;
  for (final group in groups) {
    final size = _choose(group.length, n);
    if (offset >= size) {
      offset -= size;
      continue;
    }
    final results = <T>[];
    var lo = 0;
    for (var slots = n; slots > 0; slots--) {
      for (var j = lo; j < group.length; j++) {
        final after = _choose(group.length - j - 1, slots - 1);
        if (offset >= after) {
          offset -= after;
          continue;
        }
        results.add(group[j]);
        lo = j + 1;
        break;
      }
    }
    return results;
  }
  throw RangeError.index(index, groups);
}

const _arrangements = [
  [1, 2, 0],
  [2, 0, 1],
  [1, 0, 2],
  [0, 2, 1],
  [2, 1, 0],
];
AdvancedItem _match(List<_Lex> x, int i, String title, String prompt) {
  final p = _arrangements[i % _arrangements.length];
  final left = [for (final e in x) e.$1], right = [for (final j in p) x[j].$2];
  final solution = [for (var j = 0; j < 3; j++) p.indexOf(j)];
  String seq(List<int> v) => v.map((n) => (n + 1).toString()).join(' – ');
  final order = [
    const [0, 1, 2],
    ..._arrangements,
  ].where((z) => seq(z) != seq(solution)).take(3);
  return AdvancedItem(
    prompt,
    seq(solution),
    [for (final z in order) seq(z)],
    [for (final e in x) '${e.$1} → ${e.$2}'].join(' • '),
    activity: QuestionActivity(
      kind: ActivityKind.matching,
      title: title,
      left: left,
      right: right,
      solution: solution,
    ),
  );
}

final _literaryTerms = _entries("""
Anlatıcı|Öykü dünyasını okura aktaran söyleyiş konumu
Başkişi|Olay örgüsünün merkezindeki kişi
Karşıt karakter|Merkezdeki kişinin amaçlarına engel oluşturan kişi
Bakış açısı|Anlatının olayları hangi bilgi sınırı ve konumdan sunduğu
Olay örgüsü|Anlatıdaki olayların düzenlenişi ve birbirine bağlanışı
İç monolog|Bir kişinin sessiz iç konuşmasının doğrudan aktarılması
Diyalog|İki ya da daha çok kişinin karşılıklı konuşması
Geriye dönüş|Anlatının sürmekte olan zamandan önceki bir olaya dönmesi
İleriye sıçrama|Anlatının henüz gerçekleşmemiş sonraki bir olayı önden sunması
Özetleme|Uzun bir olay süresinin kısa bir anlatım içinde sıkıştırılması
Betimleme|Kişi, nesne veya çevrenin ayırt edici özellikleriyle canlandırılması
Çatışma|Birbirine karşıt isteklerin ya da güçlerin gerilim oluşturması
Doruk noktası|Olay örgüsünde gerilimin en yüksek düzeye ulaştığı aşama
Serim|Kişilerin, ortamın ve başlangıç durumunun tanıtıldığı bölüm
Çözüm|Başlıca olay düğümlerinin bir sonuca bağlandığı bölüm
Epigraf|Bir eserin ya da bölümün başına alınan kısa alıntı
Mahlas|Yazarın veya şairin eserlerinde kullandığı takma ad
Redif|Dize sonlarında aynı görevdeki eklerin veya aynı anlamdaki sözlerin yinelenmesi
Uyak|Redif dışında, dize sonlarında görülen ses benzerliği
Dize|Şiirin bir satırı
Beyit|İki dizeden oluşan nazım birimi
Dörtlük|Dört dizeden oluşan nazım birimi
Hece ölçüsü|Dizelerdeki hece sayısı eşitliğine dayanan ölçü
Aruz|Hecelerin uzunluk ve kısalık değerlerinin düzenine dayanan ölçü
Aliterasyon|Yakın sözcüklerde ünsüz seslerin belirgin biçimde yinelenmesi
Asonans|Yakın sözcüklerde ünlü seslerin belirgin biçimde yinelenmesi
Tezat|Birbirine karşıt kavramların yan yana getirilmesi
Teşhis|İnsan dışındaki bir varlığa insana özgü nitelik verilmesi
İntak|İnsan dışındaki bir varlığın konuşturulması
Mübalağa|Bir niteliğin etkisini artırmak üzere aşırı büyütülmesi veya küçültülmesi
Telmih|Bilinen bir olay, kişi veya anlatıya örtük gönderme yapılması
İstifham|Yanıt almaktan çok anlatımı güçlendirmek için soru sorulması
Sone|Kökeni İtalyan şiirine dayanan on dört dizelik sabit nazım biçimi
Mesnevi|Her beytinin iki dizesi kendi arasında uyaklanan nazım biçimi
Gazete tefrikası|Bir eserin gazetede bölümler hâlinde art arda yayımlanması
Monografi|Belirli bir kişi, eser ya da konu üzerine odaklanmış inceleme
""");

final _functionalEnglish = _entries("""
bring up|görüşmede bir konuyu gündeme getirmek
call off|önceden planlanmış bir etkinliği iptal etmek
carry out|bir planı ya da araştırmayı uygulamak
catch up with|geride kaldıktan sonra birinin düzeyine yetişmek
check in|varışta otele ya da uçuşa kaydolmak
check out of|hesabı kapatıp otelden ayrılmak
come across|bir şeye aramadan rastlamak
come up with|bir sorun için yeni bir fikir üretmek
cut down on|tüketilen ya da yapılan şeyin miktarını azaltmak
drop off|bir yolcuyu araçla bir yere bırakmak
figure out|düşünerek bir sorunun çözümünü bulmak
fill in|formdaki boş yerleri doldurmak
find out|araştırarak daha önce bilinmeyen bir bilgiyi öğrenmek
get along with|biriyle iyi geçinmek
get over|bir hastalığı veya sarsıntıyı atlatmak
give back|ödünç alınan şeyi sahibine geri vermek
give up|çabalamaktan veya bir alışkanlıktan vazgeçmek
go over|bir metni ya da konuyu gözden geçirmek
hand in|ödevi değerlendirilmek üzere teslim etmek
hand out|gruptakilere tek tek materyal dağıtmak
hold on|telefon görüşmesinde hatta beklemek
leave out|bir öğeyi bütünün dışında bırakmak
look after|birinin bakımını üstlenmek
look forward to|gelecekte olacak bir şeyi istekle beklemek
look into|bir olayı ayrıntılı biçimde incelemek
look up|bilgiyi sözlük ya da başvuru kaynağında aramak
make up for|bir eksikliği veya kaybı telafi etmek
pass on|kendisine ulaşan bir iletiyi başkasına aktarmak
pick up|birini araçla bulunduğu yerden almak
point out|bir ayrıntıya açıkça dikkat çekmek
put away|kullanılan eşyayı ait olduğu yere kaldırmak
put off|yapılması planlanan işi daha ileri bir zamana ertelemek
run out of|eldeki bir şeyin tamamını tüketip onsuz kalmak
set off|bir yolculuğa çıkmak
sign up for|bir kursa veya etkinliğe yazılmak
sort out|karışmış bir durumu düzene koyup çözmek
turn down|bir teklifi geri çevirmek
turn up|beklenen yerde ortaya çıkmak
""");

final _linguistics = _entries("""
Fonem|Bir dilde sözcük anlamını ayırt edebilen en küçük ses birimi
Alofon|Aynı fonemin anlam ayırt etmeyen sesletim gerçekleşmesi
Minimal çift|Aynı konumda tek bir ses birimiyle ayrılan, ayrı anlamlı iki sözcük
Biçimbirim|Dilde anlam veya dilbilgisel işlev taşıyan en küçük birim
Alomorf|Aynı biçimbirimin koşullara bağlı biçimsel değişkesi
Türetim|Bir tabandan yeni bir sözlükbirim oluşturma işlemi
Çekim|Bir sözlükbirimi sözdizimsel ve dilbilgisel bağlama göre biçimlendirme
Birleşik sözcük|Birden fazla sözlüksel tabanın tek bir sözcükte birleşmesi
Sıfır biçimbirim|Bir dilbilgisel karşıtlığın görünür bir ses parçası olmadan belirtilmesi
Geçişlilik|Bir eylemin doğrudan nesne alabilmesiyle ilgili özellik
Eşgüdüm|Aynı sözdizimsel düzeydeki birimleri birbirine bağlama
Alta sıralama|Bir tümceyi başka bir tümcenin içinde bağımlı kılma
Gösterim|Bir ifadenin yorumunun konuşucu, yer veya söyleyiş zamanı gibi bağlam öğelerine dayanması
Öngönderim|Bir ifadenin anlamını metinde daha sonra geçen bir öğeden alması
Artgönderim|Bir ifadenin metinde daha önce geçen bir öğeye dönerek yorumlanması
Önvarsayım|Bir sözcenin arka planda kabul edilmiş saydığı içerik
Sezdirim|Söylenenlerden bağlam ve konuşma ilkeleriyle çıkarılan ek anlam
Edimsöz gücü|Sözcenin rica, uyarı veya söz verme gibi gerçekleştirdiği eylemin türü
Eşdizimlilik|Belirli sözcüklerin kullanımda beklenenden sık birlikte görülmesi
Çokanlamlılık|Aynı sözcüğün birbiriyle ilişkili birden fazla anlam taşıması
Eşseslilik|Anlamca ilgisiz biçimlerin aynı şekilde sesletilmesi
Altanlamlılık|Bir sözcüğün anlamının daha genel bir sözcüğün kapsamına girmesi
Parça-bütün ilişkisi|Bir sözcükle gösterilen varlığın diğerinin bileşeni olması
Söylem belirleyicisi|Sözceler arasındaki ilişkiyi ya da konuşmanın akışını işaretleyen öğe
Konuşma sırası|Bir katılımcının etkileşimde sözü elinde tuttuğu bölüm
Komşuluk çifti|Soru ve yanıt gibi, ilk hamlenin belirli bir karşılık beklettiği ikili
Onarım|Etkileşim sırasında konuşma, işitme veya anlamayla ilgili bir sorunu giderme
Kod değiştirme|Aynı etkileşim içinde birden fazla dil veya dil çeşidi arasında geçiş yapma
Toplumdilsel değişken|Farklı biçimlerde gerçekleşebilen ve kullanımı toplumsal dağılım gösterebilen dil öğesi
İdiyolekt|Tek bir kişinin kendine özgü dil kullanım örüntüsü
Derlem|Dil araştırması için sistemli biçimde bir araya getirilmiş metin veya konuşma bütünü
Tür sıklığı|Bir örüntüyü örnekleyen ayrı sözcük türlerinin sayısı
Örnekçe sıklığı|Bir dilsel öğenin derlemdeki toplam geçiş sayısı
Sözlükselleşme|Bir biçim veya ifadenin yerleşik bir sözlük birimi durumuna gelmesi
Dilbilgiselleşme|Bir dilsel öğenin zamanla daha dilbilgisel bir işlev kazanması
Toplumdilbilim|Dil biçimleri ile toplumsal koşullar arasındaki ilişkiyi araştıran alan
Sesbilgisi|Konuşma seslerinin üretim, akustik ve algı özelliklerini inceleyen alan
""");

final _researchEnglish = _entries("""
consistent with|does not contradict the proposed explanation
rules out|excludes a proposed possibility
calls into question|gives a reason to doubt a claim
accounts for|provides an explanation for a pattern
draws on|uses a source as a basis
builds on|develops an earlier contribution further
bears on|is relevant to the issue under discussion
hinges on|depends crucially on a condition
holds constant|keeps a factor fixed across comparisons
gives rise to|brings about a consequence
is confined to|is restricted in scope to a specified domain
stems from|originates in an identified source
corroborates|adds independent support to earlier evidence
replicates|repeats a study or finding in a new investigation
contrasts with|differs from a comparison case in a marked way
converges with|arrives at a compatible result through another route
takes precedence over|has higher priority than a competing consideration
serves as a proxy for|acts as an indirect measure of something else
underestimates|assigns a value below the actual level
falls short of|does not reach a stated standard
leaves open|does not settle an unresolved possibility
broadly speaking|introduces a generalization that allows exceptions
in the aggregate|considers observations together as a whole
by contrast|signals a difference from the preceding case
in particular|narrows attention to one specific instance
for instance|introduces an illustrative example
in other words|restates a point using different wording
nevertheless|signals that a point holds despite a preceding obstacle
as a result|introduces a consequence of what precedes
in the interim|locates an event in an intervening period
in retrospect|adopts the viewpoint of looking back afterwards
in principle|describes what is theoretically possible
at most|sets an inclusive upper bound
at least|sets an inclusive lower bound
approximately|marks a quantity as an estimate rather than exact
respectively|pairs listed items in the order already given
conversely|introduces a relation from the opposite direction
""");

AdvancedItem _termsTr(int i) => _match(
  _subset([_literaryTerms], 3, i),
  i,
  'Türkçe edebiyat terimleri',
  'Üç edebiyat terimini kendi tanımıyla eşleştirin.',
);
AdvancedItem _termsEn(int i) => _match(
  _subset([_functionalEnglish], 3, i),
  i,
  'Phrasal verbs in context',
  'İngilizce öbek eylemleri burada verilen kullanım anlamlarıyla eşleştirin.',
);
AdvancedItem _termsLing(int i) => _match(
  _subset([_linguistics], 3, i),
  i,
  'Dilbilim kavramları',
  'Kuramsal terimleri ayırt edici özellikleriyle eşleştirin.',
);
AdvancedItem _researchTerms(int i) => _match(
  _subset([_researchEnglish], 3, i),
  i,
  'Language of academic argument',
  'Match each expression to its function in an academic argument.',
);

final _authorPairs = <List<_Lex>>[
  [
    ("Aşk-ı Memnu", "Halit Ziya Uşaklıgil"),
    ("Yaban", "Yakup Kadri Karaosmanoğlu"),
    ("Çalıkuşu", "Reşat Nuri Güntekin"),
    ("Ateşten Gömlek", "Halide Edib Adıvar"),
    ("Dokuzuncu Hariciye Koğuşu", "Peyami Safa"),
    ("Huzur", "Ahmet Hamdi Tanpınar"),
    ("Kuyucaklı Yusuf", "Sabahattin Ali"),
    ("Devlet Ana", "Kemal Tahir"),
    ("İnce Memed", "Yaşar Kemal"),
    ("Bereketli Topraklar Üzerinde", "Orhan Kemal"),
    ("Küçük Ağa", "Tarık Buğra"),
    ("Tutunamayanlar", "Oğuz Atay"),
    ("Ölmeye Yatmak", "Adalet Ağaoğlu"),
    ("Aylak Adam", "Yusuf Atılgan"),
    ("Beyaz Kale", "Orhan Pamuk"),
    ("Mahrem", "Elif Şafak"),
    ("Sevgili Arsız Ölüm", "Latife Tekin"),
    ("Puslu Kıtalar Atlası", "İhsan Oktay Anar"),
    ("Rübab-ı Şikeste", "Tevfik Fikret"),
    ("Göl Saatleri", "Ahmet Haşim"),
    ("Kendi Gök Kubbemiz", "Yahya Kemal Beyatlı"),
    ("Otuz Beş Yaş", "Cahit Sıtkı Tarancı"),
    ("Çocuk ve Allah", "Fazıl Hüsnü Dağlarca"),
    ("Vazgeçemediğim", "Orhan Veli Kanık"),
    ("Rahatı Kaçan Ağaç", "Melih Cevdet Anday"),
    ("Perçemli Sokak", "Oktay Rifat"),
    ("Kapalı Çarşı", "Behçet Necatigil"),
    ("Üvercinka", "Cemal Süreya"),
    ("Dünyanın En Güzel Arabistanı", "Turgut Uyar"),
    ("Yerçekimli Karanfil", "Edip Cansever"),
    ("Galile Denizi", "İlhan Berk"),
    ("Rüzgâr Saati", "Gülten Akın"),
    ("Ben Sana Mecburum", "Attilâ İlhan"),
    ("Fahriye Abla", "Ahmet Muhip Dıranas"),
    ("Kaldırımlar", "Necip Fazıl Kısakürek"),
  ],
  [
    ("Sefiller", "Victor Hugo"),
    ("Goriot Baba", "Honoré de Balzac"),
    ("Madame Bovary", "Gustave Flaubert"),
    ("Germinal", "Émile Zola"),
    ("Üç Silahşorlar", "Alexandre Dumas"),
    ("Denizler Altında Yirmi Bin Fersah", "Jules Verne"),
    ("Savaş ve Barış", "Lev Tolstoy"),
    ("Suç ve Ceza", "Fyodor Dostoyevski"),
    ("Babalar ve Oğullar", "İvan Turgenyev"),
    ("Ölü Canlar", "Nikolay Gogol"),
    ("İki Şehrin Hikâyesi", "Charles Dickens"),
    ("Gurur ve Önyargı", "Jane Austen"),
    ("Adsız Sansız Bir Jude", "Thomas Hardy"),
    ("Mrs Dalloway", "Virginia Woolf"),
    ("Dava", "Franz Kafka"),
    ("Bozkırkurdu", "Hermann Hesse"),
    ("Buddenbrooklar", "Thomas Mann"),
    ("Gülün Adı", "Umberto Eco"),
    ("Ağaca Tüneyen Baron", "Italo Calvino"),
    ("Körlük", "José Saramago"),
    ("Bin Dokuz Yüz Seksen Dört", "George Orwell"),
    ("Yüzyıllık Yalnızlık", "Gabriel García Márquez"),
    ("Seksek", "Julio Cortázar"),
    ("Ruhlar Evi", "Isabel Allende"),
    ("Ficciones", "Jorge Luis Borges"),
    ("Kent ve Köpekler", "Mario Vargas Llosa"),
    ("Gazap Üzümleri", "John Steinbeck"),
    ("Yaşlı Adam ve Deniz", "Ernest Hemingway"),
    ("Martin Eden", "Jack London"),
    ("Tom Sawyer'ın Maceraları", "Mark Twain"),
    ("Sevilen", "Toni Morrison"),
    ("Sahilde Kafka", "Haruki Murakami"),
    ("Things Fall Apart", "Chinua Achebe"),
    ("Saray Gezisi", "Naguib Mahfouz"),
    ("Hamlet", "William Shakespeare"),
    ("Cimri", "Molière"),
    ("Bir Bebek Evi", "Henrik Ibsen"),
    ("Vişne Bahçesi", "Anton Çehov"),
    ("Cesaret Ana ve Çocukları", "Bertolt Brecht"),
    ("Kanlı Düğün", "Federico García Lorca"),
    ("Kral Oidipus", "Sophokles"),
    ("Salome", "Oscar Wilde"),
    ("Satıcının Ölümü", "Arthur Miller"),
    ("Arzu Tramvayı", "Tennessee Williams"),
    ("Keşanlı Ali Destanı", "Haldun Taner"),
    ("Fehim Paşa Konağı", "Turgut Özakman"),
  ],
];

AdvancedItem _works(int i) => _match(
  _subset(_authorPairs, 3, i),
  i,
  'Eser ve yazar',
  'Okuma listesindeki üç eseri yazarlarıyla eşleştirin.',
);

AdvancedItem _bookAudio(int i) {
  final w = _subset(_authorPairs, 3, i);
  final a = w[0].$1, b = w[1].$1, c = w[2].$1;
  final reverse = i.isOdd;
  final selected = reverse ? b : c, backup = reverse ? c : b;
  final audio = reverse
      ? 'Listemde ilk sırada $a vardı. Fakat onun bütün kopyaları ödünçteymiş. $c için ayırma sırasına girdim. Bugün çantama koyup götürdüğüm kitap ise $b.'
      : 'Başta $a için gelmiştim. Sonra fikrimi değiştirdim. $b kütüphaneye dönünce bana haber verecekler. Şimdilik eve $c ile gidiyorum.';
  return AdvancedItem(
    'Konuşmacının bugün aldığı kitap ile daha sonra edinmek için beklediği kitabı sırasıyla belirleyin.',
    '$selected / $backup',
    ['$backup / $selected', '$a / $backup', '$selected / $a'],
    'İlk tercih ile gerçekleşen ödünç alma farklıdır. Bugün alınan “$selected”, beklenen “$backup”tır.',
    activity: QuestionActivity(
      kind: ActivityKind.listening,
      title: 'Kitaplıkta değişen tercih',
      language: 'tr-TR',
      transcript: audio,
    ),
  );
}

const _venues = [
  'the main hall',
  'the east studio',
  'the library',
  'the media room',
  'the music room',
  'the courtyard',
  'the lecture theatre',
  'the west lobby',
  'the seminar room',
  'the training room',
  'the dance studio',
  'the conference room',
  'the sports hall',
  'the art room',
  'the reading room',
  'the exhibition hall',
  'the computer room',
  'the language lab',
  'the rehearsal room',
  'the community centre',
];
String _timeEn(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  return '${h % 12 == 0 ? 12 : h % 12}:${m.toString().padLeft(2, '0')} ${h < 12 ? 'a.m.' : 'p.m.'}';
}

AdvancedItem _announcement(int i) {
  final a = i % 25, b = i ~/ 25 % 20, c = i ~/ 500;
  final oldTime = 480 + 15 * a,
      newTime = oldTime + (c.isEven ? 1 : -1) * (c ~/ 2 + 1) * 10;
  final former = _venues[(b + 3 + c) % 20],
      venue = _venues[b],
      before = _timeEn(oldTime),
      after = _timeEn(newTime);
  final msg = switch (c % 4) {
    0 =>
      'A quick correction to the workshop notice. It originally said $before in $former. The confirmed arrangements are $after in $venue. Please update your calendar.',
    1 =>
      'The sign outside $former still shows $before. That was the first plan. For today only, meet us in $venue at $after.',
    2 =>
      'If the equipment arrived, the group was going to meet in $former at $before. It did not arrive. We are using $venue instead, and the new starting time is $after.',
    _ =>
      'I almost sent the old reminder: $former, $before. Please ignore that version. We have booked $venue, and the session will start at $after.',
  };
  return AdvancedItem(
    'Listen to the update. Which time and place should a participant put in the calendar?',
    '$after / $venue',
    ['$before / $venue', '$after / $former', '$before / $former'],
    'İlk duyuru değiştirilmiştir. Geçerli zaman $after, geçerli yer $venue olarak bildirilir.',
    activity: QuestionActivity(
      kind: ActivityKind.listening,
      title: 'A revised arrangement',
      language: 'en-US',
      transcript: msg,
    ),
  );
}

final _pronGroups = <List<String>>[
  'asked baked brushed checked clapped cooked crossed danced dressed dropped finished fixed helped hoped jumped kissed laughed looked missed packed passed picked pushed reached stopped talked tapped touched washed watched worked'
      .split(' '),
  'allowed answered arrived believed called changed cleaned climbed closed covered cried delivered described enjoyed explained filled followed gained joined lived loved moved opened played pulled raised received returned showed smiled stayed used'
      .split(' '),
  'accepted added admitted affected avoided collected completed connected decided demanded depended divided edited ended expected folded founded greeted guided heated included invited lasted landed limited needed noted painted planted posted printed protected recorded repeated rested shouted started tested treated visited waited wanted'
      .split(' '),
  'books caps cats checks clocks cups desks drinks drops forks gifts hats hopes kicks lamps lips locks maps mats parks peaks pets picks pipes plates pots rocks seats shops socks stops taps tents tips tops tracks trips'
      .split(' '),
  'bags beads bells birds boards bowls boys cards chairs clouds coins days dogs doors dreams ears eggs films flags floors friends games gloves goals hands hills homes jars keys knees legs lines meals names pens phones plays rings roads rooms schools shoes songs stars streams tables teams tools trees vans walls wings words years zones'
      .split(' '),
  'arches badges batches benches boxes bridges brushes buses buzzes cages cases catches changes churches classes coaches crashes dishes dresses edges faces fences flashes foxes fridges glasses guesses inches judges kisses matches messages misses noises pages patches peaches places prices prizes races roses sizes stages stitches touches washes watches wishes'
      .split(' '),
];
const _sounds = ['/t/', '/d/', '/ɪd/', '/s/', '/z/', '/ɪz/'];
AdvancedItem _pronunciation(int i) {
  // Take a balanced portion from each phonological class, using an injective
  // map for every class. All three words illustrate the same target ending.
  final group = i % 6, k = i ~/ 6, words = _pronGroups[group];
  final selected = _subset([words], 3, k, quota: 834);
  final phrase = selected.join(', ') + '.';
  final sound = _sounds[group];
  final wrong = [
    for (final s in _sounds)
      if (s != sound) s,
  ].take(3).toList();
  return AdvancedItem(
    'Örnek sesi dinleyin. Üç sözcüğü sırayla, çekim eklerini belirgin söyleyerek tekrar edin. Üç ekteki ortak sesletime dikkat edin.',
    sound,
    wrong,
    'Bu alıştırmada üç sözcüğün de çekim eki $sound olarak sesletilir. Model sırayla $phrase',
    activity: QuestionActivity(
      kind: ActivityKind.pronunciation,
      title: 'İngilizce çekim eklerinin sesletimi',
      language: 'en-US',
      transcript: phrase,
    ),
  );
}

typedef _Gap = (String, String, String, String);
const _trGaps = <_Gap>[
  (
    'Dudaklarını aralayıp derin bir nefes almak için ___ açtı.',
    'ağız',
    'ağzını',
    'ağızını',
  ),
  (
    'Aynaya bakınca ___ ucundaki boyayı fark etti.',
    'burun',
    'burnunun',
    'burununun',
  ),
  ('At, ağır yükü çekmek için ___ öne eğdi.', 'boyun', 'boynunu', 'boyununu'),
  ('Yolcu, paltosunun ıslak ___ silkti.', 'omuz', 'omzunu', 'omuzunu'),
  ('Koşucu, mendiliyle terleyen ___ sildi.', 'alın', 'alnını', 'alınını'),
  ('Sağlık görevlisi, hastanın ___ dinledi.', 'göğüs', 'göğsünü', 'göğüsünü'),
  ('Duvara çarpınca sol ___ ovuşturdu.', 'dirsek', 'dirseğini', 'dirsekini'),
  ('Saatçi, yeni saati müşterinin ___ taktı.', 'bilek', 'bileğine', 'bilekine'),
  (
    'Tavşan yaklaşan sesi duyunca sol ___ dikti.',
    'kulak',
    'kulağını',
    'kulakını',
  ),
  ('Garson, boş ___ masadan kaldırdı.', 'tabak', 'tabağı', 'tabakı'),
  ('Aşçı, karıştırmak için tahta ___ eline aldı.', 'kaşık', 'kaşığı', 'kaşıkı'),
  ('Usta, ekmek ___ dikkatle bileyledi.', 'bıçak', 'bıçağını', 'bıçakını'),
  ('Çocuk, su dolu ___ iki eliyle tuttu.', 'bardak', 'bardağı', 'bardakı'),
  ('Kedi, süt ___ başında bekliyordu.', 'çanak', 'çanağının', 'çanakının'),
  ('Elek yerine çay ___ kullandı.', 'süzgeç', 'süzgecini', 'süzgeçini'),
  ('Sebzeci, iri bir ___ ikiye böldü.', 'havuç', 'havucu', 'havuçu'),
  ('Bahçıvan, olgunlaşan ___ dalından kesti.', 'kabak', 'kabağı', 'kabakı'),
  ('Çiftçi, sonbaharda ___ sürmeye başladı.', 'toprak', 'toprağı', 'toprakı'),
  ('Fırtına, yol kenarındaki genç ___ devirdi.', 'ağaç', 'ağacı', 'ağaçı'),
  ('Arı, mor ___ üzerine kondu.', 'çiçek', 'çiçeğin', 'çiçekin'),
  (
    'Botanikçi, düşen ___ iki yüzünü de inceledi.',
    'yaprak',
    'yaprağın',
    'yaprakın',
  ),
  ('Terzi, mavi ___ yakasını düzeltti.', 'gömlek', 'gömleğin', 'gömlekin'),
  ('Dansçı, uzun ___ ucunu topladı.', 'etek', 'eteğinin', 'etekinin'),
  ('Sporcu, ıslanan ___ değiştirdi.', 'çorap', 'çorabını', 'çorapını'),
  (
    'Rüzgâr artınca çocuk babasının ___ giydi.',
    'yelek',
    'yeleğini',
    'yelekini',
  ),
  ('Okur, bitirdiği ___ arkadaşına verdi.', 'kitap', 'kitabı', 'kitapı'),
  ('Öğretmen, boş ___ ikiye katladı.', 'kâğıt', 'kâğıdı', 'kâğıtı'),
  ('Çevirmen, başvuru için bu ___ seçti.', 'sözlük', 'sözlüğü', 'sözlükü'),
  ('Bakıcı, ahşap ___ menteşesini yağladı.', 'dolap', 'dolabın', 'dolapın'),
  ('Yolcu, başının altındaki ___ düzeltti.', 'yastık', 'yastığı', 'yastıkı'),
  ('Usta, kırılan ___ onardı.', 'yatak', 'yatağı', 'yatakı'),
  ('Veteriner, yaralı ___ muayene etti.', 'köpek', 'köpeği', 'köpeki'),
  ('Fotoğrafçı, açıklıktaki ___ görüntüledi.', 'geyik', 'geyiği', 'geyiki'),
  ('Çocuk, havuzdaki ___ bir süre izledi.', 'ördek', 'ördeği', 'ördeki'),
  ('Balıkçı, küçük ___ yeniden suya bıraktı.', 'balık', 'balığı', 'balıkı'),
  (
    'Gezgin, karşı kıyıdaki ___ fotoğrafını çekti.',
    'kayık',
    'kayığın',
    'kayıkın',
  ),
  ('Gezginler, tarihî ___ yürüyerek keşfetti.', 'şehir', 'şehri', 'şehiri'),
  ('Postacı, dar ___ başında durdu.', 'sokak', 'sokağın', 'sokakın'),
  ('Şoför, kalabalık ___ yaklaşırken yavaşladı.', 'durak', 'durağa', 'duraka'),
];
AdvancedItem _turkishEditing(int i) {
  final t = _subset([_trGaps], 3, i);
  String option(int mask) =>
      [for (var n = 0; n < 3; n++) (mask & (1 << n)) == 0 ? t[n].$3 : t[n].$4]
          .join(' / ');
  final prompt = [
    for (var n = 0; n < 3; n++) '${n + 1}. ${t[n].$1} (${t[n].$2})',
  ].join('\n');
  return AdvancedItem(
    '$prompt\nBu üç bağımsız cümlede boşlukları hem bağlama hem yazıma uygun olarak hangi dizi tamamlar?',
    option(0),
    [option(1), option(2), option(4)],
    'Bağlamın gerektirdiği ek getirildiğinde standart biçimler sırasıyla ${option(0)} olur. Ekten önce kökün ses yapısını koruyup korumadığına dikkat edin.',
  );
}

typedef _Verb = (String, String, String, String, String);
const _verbs = <_Verb>[
  ('the curator', 'choose', 'chose', 'chosen', 'the opening image'),
  ('the editor', 'write', 'wrote', 'written', 'the caption'),
  ('the printer', 'make', 'made', 'made', 'a test copy'),
  ('the designer', 'draw', 'drew', 'drawn', 'the floor plan'),
  ('the assistant', 'take', 'took', 'taken', 'a photograph'),
  ('the technician', 'find', 'found', 'found', 'a spare cable'),
  ('the archivist', 'bring', 'brought', 'brought', 'the original letter'),
  ('the guide', 'give', 'gave', 'given', 'a short introduction'),
  ('the artist', 'send', 'sent', 'sent', 'a signed print'),
  ('the editor', 'read', 'read', 'read', 'the revised text'),
  ('the manager', 'buy', 'bought', 'bought', 'a display case'),
  ('the carpenter', 'build', 'built', 'built', 'a narrow shelf'),
  ('the coordinator', 'meet', 'met', 'met', 'the volunteers'),
  ('the photographer', 'leave', 'left', 'left', 'a contact sheet'),
  ('the librarian', 'keep', 'kept', 'kept', 'the loan receipt'),
  ('the conservator', 'wear', 'wore', 'worn', 'a protective mask'),
  ('the volunteer', 'hold', 'held', 'held', 'the frame steady'),
  ('the director', 'speak', 'spoke', 'spoken', 'to the donors'),
  ('the researcher', 'see', 'saw', 'seen', 'the early sketch'),
  ('the treasurer', 'pay', 'paid', 'paid', 'the shipping fee'),
  ('the camera operator', 'shoot', 'shot', 'shot', 'a short interview'),
  ('the musician', 'sing', 'sang', 'sung', 'the opening song'),
  ('the producer', 'sell', 'sold', 'sold', 'the last ticket'),
  ('the instructor', 'teach', 'taught', 'taught', 'a drawing class'),
  ('the registrar', 'lend', 'lent', 'lent', 'the backup scanner'),
  ('the courier', 'drive', 'drove', 'driven', 'the delivery van'),
  ('the narrator', 'tell', 'told', 'told', 'the artist’s story'),
  ('the steward', 'put', 'put', 'put', 'the chairs away'),
  ('the organiser', 'set', 'set', 'set', 'a new deadline'),
  ('the helper', 'cut', 'cut', 'cut', 'the mounting board'),
  ('the assistant', 'stick', 'stuck', 'stuck', 'a label on the box'),
  ('the critic', 'think', 'thought', 'thought', 'about the closing scene'),
  ('the sculptor', 'break', 'broke', 'broken', 'the mold'),
  ('the student', 'hide', 'hid', 'hidden', 'the unfinished sketch'),
  ('the stagehand', 'hang', 'hung', 'hung', 'the backdrop'),
  ('the conductor', 'begin', 'began', 'begun', 'the rehearsal'),
  ('the presenter', 'show', 'showed', 'shown', 'an early slide'),
  ('the illustrator', 'tear', 'tore', 'torn', 'the damaged sheet'),
];

AdvancedItem _englishGaps(int i) {
  final x = _subset([_verbs], 3, i);
  final clauses = <String>[], right = <String>[], mistakes = <String>[];
  for (var j = 0; j < 3; j++) {
    final r = x[j], perfect = (j + i) % 3 != 0;
    clauses.add(
      perfect
          ? 'By noon, ${r.$1} had already ___ ${r.$5}. (${r.$2})'
          : 'Yesterday, ${r.$1} ___ ${r.$5}. (${r.$2})',
    );
    right.add(perfect ? r.$4 : r.$3);
    // Some verbs have identical past and participle, so use a specifically
    // incompatible finite/present construction when forms coincide.
    final ordinary = r.$2;
    final candidate = perfect ? r.$3 : r.$4;
    mistakes.add(
      candidate != right.last
          ? candidate
          : ordinary != right.last
          ? ordinary
          : 'will ${r.$2}',
    );
  }
  final opts = [
    for (var j = 0; j < 3; j++)
      [for (var k = 0; k < 3; k++) k == j ? mistakes[k] : right[k]].join(' / '),
  ];
  return AdvancedItem(
    '${clauses.join('\n')}\nÜç bağımsız cümlede verilen fiillerin hangi biçimleri kullanılmalıdır?',
    right.join(' / '),
    opts,
    '“Yesterday” ile tamamlanmış olay için yalın geçmiş zaman kullanılır. “Had already” sonrasında geçmiş zaman ortacı gelir. Gerekli biçimler ${right.join(', ')}.',
  );
}

const _schoolEvents = [
  'Oyuncu kostümünü denedi',
  'Işıkçı sahne ışıklarını ayarladı',
  'Yönetmen açılış sahnesini izledi',
  'Sahne amiri perdeyi kontrol etti',
  'Müzisyen gitarının akordunu yaptı',
  'Gişe görevlisi biletleri saydı',
  'Dansçı sahnedeki işaretleri kontrol etti',
  'Oyuncu son repliğini tekrarladı',
  'Dekoratör pano yerini işaretledi',
  'Teknisyen hoparlörü taşıdı',
  'Koro şefi giriş notasını verdi',
  'Yapımcı program metnini okudu',
  'Makyajcı renk provasını yaptı',
  'Görevli yan kapıyı açtı',
  'Sunucu anonsunu kaydetti',
  'Fotoğrafçı ışık ölçümü yaptı',
  'Afiş tasarımcısı son baskıyı getirdi',
  'Kostümcü ceketi ütüledi',
  'Ses sorumlusu yaka mikrofonunu taktı',
  'Aksesuar ekibi sandalyeyi yerleştirdi',
  'Suflör metnini hazırladı',
  'Reji asistanı yoklama aldı',
  'Yazar kısa bir selamlama yazdı',
  'Dans eğitmeni ısınmayı başlattı',
  'Kameraman tripodu kurdu',
  'Gönüllü ilk sırayı numaraladı',
  'Sahne işçisi sehpayı sabitledi',
  'Gözcü acil çıkışı denetledi',
  'Başoyuncu maskesini seçti',
  'Kemancı notasını işaretledi',
  'Piyanist taburesini ayarladı',
  'Davulcu bagetlerini aradı',
  'Kuklacı ipleri çözdü',
  'Anlatıcı sesini ısıttı',
  'Kıyafet sorumlusu şapkayı paketledi',
  'Sahne ressamı fonu onardı',
  'Işık tasarımcısı filtreyi değiştirdi',
  'Koreograf dönüş işaretini gösterdi',
];
const _academicEvents = [
  'The panel registered the study',
  'The team released the questionnaire',
  'The archive issued a reader permit',
  'The editor circulated the codebook',
  'The fieldworker logged a pilot interview',
  'The auditor signed the consent checklist',
  'The data manager locked the initial file',
  'The analyst documented the exclusions',
  'The chair approved the revised protocol',
  'The librarian supplied a catalogue record',
  'The author deposited the transcript',
  'The reviewer flagged a missing appendix',
  'The coordinator booked the interview room',
  'The ethics office requested clarification',
  'The statistician checked the sampling weights',
  'The transcriber returned the draft',
  'The translator annotated a disputed term',
  'The partner institution sent a letter',
  'The researcher filed a field note',
  'The committee set a review date',
  'The team verified the archive reference',
  'The supervisor approved the abstract',
  'The panel examined a duplicate record',
  'The archivist located a second copy',
  'The journal acknowledged the submission',
  'The lab released the coding guide',
  'The assistant checked the anonymization',
  'The designer revised a figure',
  'The evaluator compared the two rubrics',
  'The analyst recorded an assumption',
  'The author added a source note',
  'The editor approved the proof',
  'The investigator wrote a limitations paragraph',
  'The team stored the revision history',
  'The coordinator confirmed the interview slot',
  'The reviewer questioned the unit of analysis',
  'The librarian checked the edition number',
  'The team catalogued the recording',
];
AdvancedItem _ordering(int i, bool english) {
  final selected = _subset([english ? _academicEvents : _schoolEvents], 3, i);
  final semantic = _arrangements[(i ~/ 5) % 5], p = _arrangements[i % 5];
  final a = selected[semantic[0]],
      b = selected[semantic[1]],
      c = selected[semantic[2]];
  final correctOrder = [a, b, c], items = [for (final k in p) correctOrder[k]];
  final solution = [for (var k = 0; k < 3; k++) p.indexOf(k)];
  final from = english
      ? 'An editor is rebuilding a timeline from two notes. The note about “$b” says “$c” was still to come. Another note says “$b” had not yet happened when “$a” took place. Reconstruct the sequence.'
      : 'Tiyatro günlüğündeki iki notu birlikte okuyun. “$b” anında “$c” henüz gerçekleşmemişti. “$a” anında ise “$b” hâlâ bekleniyordu. Bu üç olayı eskiden yeniye sıralayın.';
  String seq(List<int> v) => v.map((n) => (n + 1).toString()).join(' → ');
  final wrong = [
    const [0, 1, 2],
    ..._arrangements,
  ].where((e) => seq(e) != seq(solution)).take(3);
  return AdvancedItem(
    from,
    seq(solution),
    [for (final v in wrong) seq(v)],
    'Birinci zaman ilişkisi ortadaki olayın sonuncudan önce olduğunu, ikinci ilişki ilk olayın ortadakinden önce olduğunu gösterir. Sıra: ${correctOrder.join(" → ")}.',
    activity: QuestionActivity(
      kind: ActivityKind.ordering,
      title: english
          ? 'Reconstruct the research timeline'
          : 'Tiyatro günlüğünün zaman sırası',
      items: items,
      solution: solution,
    ),
  );
}

AdvancedItem _schoolOrder(int i) => _ordering(i, false);
AdvancedItem _academicOrder(int i) => _ordering(i, true);

final _editorActions = _entries("""
define the main term|ana terimi tanımlamak
identify the sample frame|örnekleme çerçevesini belirtmek
restore the missing citation|eksik kaynak göndermesini eklemek
explain the exclusion rule|dışlama kuralını açıklamak
label the figure axes|şeklin eksenlerini adlandırmak
name the comparison group|karşılaştırma grubunu belirtmek
state the unit of analysis|analiz birimini yazmak
distinguish the two editions|iki baskıyı birbirinden ayırmak
report the response rate|yanıt oranını bildirmek
describe the consent procedure|onam sürecini açıklamak
clarify the time window|incelenen zaman aralığını netleştirmek
acknowledge the missing records|kayıp kayıtları belirtmek
quote the original wording|özgün ifadeyi alıntılamak
correct the table heading|tablo başlığını düzeltmek
separate results from interpretation|bulguları yorumdan ayırmak
document the translation decision|çeviri kararını belgelemek
justify the coding threshold|kodlama eşiğini gerekçelendirmek
describe the interview setting|görüşmenin yapıldığı ortamı tanımlamak
check the page reference|sayfa göndermesini denetlemek
add the version date|sürüm tarihini eklemek
identify the funding source|finansman kaynağını açıklamak
supply the archive identifier|arşiv tanımlayıcısını vermek
specify the search terms|tarama ifadelerini belirtmek
report the recruitment method|katılımcı bulma yöntemini bildirmek
qualify the causal claim|nedensellik iddiasını sınırlamak
include the original units|özgün ölçü birimlerini eklemek
define the baseline period|başlangıç dönemini tanımlamak
disclose the coding disagreement|kodlayıcıların anlaşmazlığını belirtmek
explain the choice of denominator|payda seçimini açıklamak
describe the follow-up procedure|izlem işlemini anlatmak
distinguish the two speakers|iki konuşmacıyı birbirinden ayırmak
cite the primary source|birincil kaynağa gönderme yapmak
list the eligibility criteria|uygunluk ölçütlerini listelemek
mark the reconstructed passages|yeniden oluşturulmuş bölümleri işaretlemek
summarize the pilot findings|pilot çalışma bulgularını özetlemek
describe the sampling interval|örnekleme aralığını açıklamak
document the correction history|düzeltme geçmişini belgelemek
state the uncertainty range|belirsizlik aralığını belirtmek
""");

AdvancedItem _reviewAudio(int i) {
  final x = _subset([_editorActions], 3, i), p = _arrangements[i % 5];
  final a = x[p[0]], b = x[p[1]], c = x[p[2]];
  final message = i.isEven
      ? 'The old review asked us to ${a.$1}, but the editor withdrew that request. Before acceptance we must ${b.$1}. We may ${c.$1} in the web supplement later; acceptance does not depend on it.'
      : 'Let me clarify the decision. It would be useful to ${c.$1}, but that can wait. We no longer need to ${a.$1}. The revision will only be accepted if we ${b.$1}.';
  return AdvancedItem(
    'Dinlediğiniz editör kararına göre, kabul için zorunlu düzeltme ile sonraya bırakılabilen düzeltme sırasıyla hangileridir?',
    '${b.$2} / ${c.$2}',
    ['${c.$2} / ${b.$2}', '${a.$2} / ${c.$2}', '${b.$2} / ${a.$2}'],
    'Kabul koşulu “${b.$1}” eylemidir. “${c.$1}” daha ileri bir tarihe bırakılabilir. “${a.$1}” talebi geri alınmıştır.',
    activity: QuestionActivity(
      kind: ActivityKind.listening,
      title: 'A decision after peer review',
      transcript: message,
      language: 'en-US',
    ),
  );
}

final _observations = <String>[
  'perdenin kapalı kaldığını',
  'ışığın birden söndüğünü',
  'zilin iki kez çaldığını',
  'yan kapının açık olduğunu',
  'koridorun boşaldığını',
  'masada bir mektup kaldığını',
  'saatin durduğunu',
  'sandığın yerinden oynadığını',
  'pencerenin aralık olduğunu',
  'çekmecenin kilitli kaldığını',
  'duvardaki resmin kaldırıldığını',
  'avluda bir fener yandığını',
  'piyanonun kapağının kapandığını',
  'sahneye bir sandalye konduğunu',
  'merdivende bir palto kaldığını',
  'köşedeki aynanın örtüldüğünü',
  'antrede bir bavul durduğunu',
  'yerde bir bilet bulunduğunu',
  'kütüphanede radyo çaldığını',
  'vazonun masadan alındığını',
  'sarı zarfın yırtıldığını',
  'son sıranın boş olduğunu',
  'çanın sustuğunu',
  'halının kenarının kıvrıldığını',
  'fincanın devrildiğini',
  'bahçe kapısının kapandığını',
  'perdenin ipinin çözüldüğünü',
  'küçük lambanın yandığını',
  'yolcu listesinin kaybolduğunu',
  'defterin açık bırakıldığını',
  'arka sıraya birinin oturduğunu',
  'girişte bir gazete asılı olduğunu',
  'odada tütsü yakıldığını',
  'merdiven ışığının söndüğünü',
  'kırmızı şemsiyenin unutulduğunu',
  'mührün bozulduğunu',
  'balkon kapısının kilitlendiğini',
  'gramofonun sustuğunu',
];
AdvancedItem _voice(int i) {
  final x = _subset([_observations], 3, i), p = _arrangements[i % 5];
  final direct = x[p[0]], hearsay = x[p[1]], guess = x[p[2]];
  String up(String text) =>
      (text[0] == 'i' ? 'İ' : text[0].toUpperCase()) + text.substring(1);
  final passage = i.isEven
      ? '“${up(hearsay)} sonradan bekçiden öğrendim. ${up(direct)} kendim gözlemledim. ${up(guess)} ise yalnızca tahmin ediyorum.”'
      : '“${up(guess)} sanıyorum. Bekçinin anlattığı şey $hearsay gösteriyor. Bizzat oradaydım ve $direct doğrudan gözlemledim.”';
  return AdvancedItem(
    '$passage\nBu kurmaca anlatıda anlatıcının doğrudan gözlemi ile başkasının sözüne dayanan bilgiyi sırasıyla hangi ikili verir?',
    '${up(direct)} / $hearsay',
    [
      '${up(hearsay)} / $direct',
      '${up(guess)} / $hearsay',
      '${up(direct)} / $guess',
    ],
    'Kişisel tanıklık “$direct”, aktarılan bilgi “$hearsay” önermesine dayanır. “$guess” anlatıcının çıkarımıdır.',
  );
}

AdvancedItem _revision(int i) {
  final a = i % 25, b = i ~/ 25 % 20, c = i ~/ 500;
  final initial = 31 + a, sites = 2 + c;
  final finalN = 42 + b == initial ? 70 : 42 + b;
  final gain = (finalN - initial) * sites / (sites + 5);
  final magnitude = gain.abs().toStringAsFixed(1).replaceAll('.', ',');
  final dir = gain > 0 ? 'yükseldi' : 'düştü';
  final inverse = gain > 0 ? 'düştü' : 'yükseldi';
  final common =
      'Kurmaca bir araştırma notu: “Eşit sayıda metnin incelendiği gönüllü sınıfların $sites tanesinde yazma ölçütünü karşılayan metinlerin oranı %$initial düzeyinden %$finalN düzeyine geçti. Diğer 5 sınıfta oran her iki ölçümde de %$initial idi. Dış karşılaştırma grubu yoktu.”';
  return AdvancedItem(
    '$common Hangi redaksiyon, incelenen tüm sınıfları birleştirerek değişimi ve kanıtın kapsamını doğru aktarır?',
    'İncelenen metinler birleştirildiğinde oran yaklaşık $magnitude yüzde puan $dir.',
    [
      'İncelenen metinler birleştirildiğinde oran yaklaşık $magnitude yüzde puan $inverse.',
      'Tüm ülkede ölçütü karşılayan metinlerin oranı tam olarak %$finalN oldu.',
      'Uygulamanın bütün öğrencilerde nedensel etkisi kanıtlandı.',
    ],
    'Eşit sayıda metin içeren $sites sınıfta değişim ${finalN - initial} yüzde puandır. Diğer 5 sınıfta sıfırdır. Birleşik değişim ($finalN − $initial) × $sites / ${sites + 5} olur. Gözlenen kapsamın dışına genelleme ve nedensel çıkarım desteklenmez.',
  );
}

AdvancedItem _modalEditing(int i) {
  final x = _subset([_editorActions], 3, i), p = _arrangements[i % 5];
  final a = x[p[0]], b = x[p[1]], c = x[p[2]];
  final brief =
      'The journal requires authors to ${a.$1}. They are encouraged, but not required, to ${b.$1}. A separate editor is handling the next task, so the authors must not ${c.$1} in this round.';
  String label(_Lex x, _Lex y, _Lex z) => '${x.$2} / ${y.$2} / ${z.$2}';
  return AdvancedItem(
    '$brief\nBir Türkçe yönerge hazırlanıyor. “Zorunlu, önerilen, bu turda yazara yasak” başlıkları altında sırasıyla hangi eylemler yer almalıdır?',
    label(a, b, c),
    [label(b, a, c), label(a, c, b), label(c, b, a)],
    '“Requires” zorunluluk, “encouraged, but not required” isteğe bağlı öneri, “must not” yasak bildirir. Her kip ifadesinin kapsamı izleyen eylemdir.',
  );
}

AdvancedItem _brief(int i) {
  final x = _subset([_editorActions], 3, i), p = _arrangements[i % 5];
  final a = x[p[0]], b = x[p[1]], c = x[p[2]];
  String order(_Lex x, _Lex y) => '${x.$1} → ${y.$1}';
  return AdvancedItem(
    'Yazım ekibine İngilizce bir iş devri mesajı hazırlıyorsunuz. Notlar: “${a.$1}” teslimden önce zorunlu; “${b.$1}” ancak birinci iş tamamlandıktan sonra yapılacak; “${c.$1}” bu sürümün dışında. Metninizde kuracağınız önkoşul zincirini seçin.',
    order(a, b),
    [order(b, a), order(a, c), order(c, b)],
    'Önkoşul ${a.$1}, ona bağlı iş ${b.$1} olur. Kapsam dışında kalan görev zincire eklenmez.',
  );
}

CreationTask _briefTask(AdvancedItem item, int i) {
  final x = _subset([_editorActions], 3, i), p = _arrangements[i % 5];
  return CreationTask(
    'Uluslararası bir dergiye metin hazırlayan meslektaşınıza 2–3 cümlelik bir İngilizce iş devri mesajı yazın. Teslimden önce ${x[p[0]].$1} zorunlu, ${x[p[1]].$1} bu işin bitmesine bağlı ve ${x[p[2]].$1} mevcut sürümün kapsamı dışında. Emir listesini kopyalamadan ilişkileri açıklayın.',
    [
      'Teslim koşulunu kip veya nazik ama bağlayıcı bir dilekle açık ifade etmek.',
      'İkinci eylemin birinciye bağımlılığını örneğin “once” veya “only after” ile korumak.',
      'Kapsam dışında kalan eylemi ayrı belirtmek ve alıcıya uygun kısa, profesyonel bir mesaj kurmak.',
    ],
  );
}

AdvancedItem _scopeBlank(int i) {
  final x = _subset([_editorActions], 3, i), p = _arrangements[i % 5];
  final a = x[p[0]].$1, b = x[p[1]].$1, c = x[p[2]].$1;
  final requested = i.isEven;
  final rule = requested
      ? 'If the editor sends a query, the author must $a. Otherwise, the author must $b. The author may $c in either case.'
      : 'The author must $a unless the board requests a second reading. If it does, the author must $b instead. The author may also $c.';
  final event = requested
      ? 'The editor has sent a query.'
      : 'The board has requested a second reading.';
  final answer = (requested ? a : b).split(' ').first;
  final others = <String>{
    for (final work in [a, b, c, 'submit', 'review', 'revise', 'publish'])
      work.split(' ').first,
  }..remove(answer);
  return AdvancedItem(
    '$rule $event Copy only the first English verb of the action that is now compulsory: “The author must ___ …”',
    answer,
    others.take(3).toList(),
    'Gerçekleşen koşul, “${requested ? a : b}” eylemini zorunlu kılar. “May” ile verilen eylem seçenek olarak kalır. İstenen ilk fiil “$answer”dır.',
  );
}

final renewedLanguageFamilies = <AdvancedFamily>[
  _langFamily(
    'tr_terms',
    'Edebiyat terimlerini ayırt etme',
    Topic.literature,
    false,
    BloomLevel.hatirlama,
    _termsTr,
    activity: ActivityKind.matching,
  ),
  _langFamily(
    'phrasal',
    'Bağlamda İngilizce öbek eylemler',
    Topic.language,
    false,
    BloomLevel.anlama,
    _termsEn,
    activity: ActivityKind.matching,
  ),
  _langFamily(
    'author',
    'Karşılaştırmalı okuma listeleri',
    Topic.literature,
    false,
    BloomLevel.hatirlama,
    _works,
    activity: ActivityKind.matching,
  ),
  _langFamily(
    'reservation',
    'Ödünç alma diyaloğunu dinleme',
    Topic.literature,
    false,
    BloomLevel.anlama,
    _bookAudio,
    activity: ActivityKind.listening,
  ),
  _langFamily(
    'notice',
    'Duyuruda değişen planı dinleme',
    Topic.language,
    false,
    BloomLevel.anlama,
    _announcement,
    activity: ActivityKind.listening,
  ),
  _langFamily(
    'endings',
    'İngilizce eklerin sesletimi',
    Topic.language,
    false,
    BloomLevel.uygulama,
    _pronunciation,
    activity: ActivityKind.pronunciation,
  ),
  _langFamily(
    'tr_edits',
    'Cümle bağlamında Türkçe çekim',
    Topic.literature,
    false,
    BloomLevel.uygulama,
    _turkishEditing,
  ),
  _langFamily(
    'en_edits',
    'Simple past ve past participle',
    Topic.language,
    false,
    BloomLevel.uygulama,
    _englishGaps,
  ),
  _langFamily(
    'stage',
    'Günlük notlarından olay sırası',
    Topic.literature,
    false,
    BloomLevel.analiz,
    _schoolOrder,
    activity: ActivityKind.ordering,
  ),
  _langFamily(
    'linguistics',
    'Dilbilim terimleri',
    Topic.language,
    true,
    BloomLevel.hatirlama,
    _termsLing,
    activity: ActivityKind.matching,
  ),
  _langFamily(
    'discourse',
    'Akademik İngilizcede söylem işlevleri',
    Topic.language,
    true,
    BloomLevel.anlama,
    _researchTerms,
    activity: ActivityKind.matching,
  ),
  _langFamily(
    'research_sequence',
    'Akademik kayıtta zaman ilişkileri',
    Topic.language,
    true,
    BloomLevel.analiz,
    _academicOrder,
    activity: ActivityKind.ordering,
  ),
  _langFamily(
    'peer_review',
    'Hakem kararını dinleyerek yorumlama',
    Topic.language,
    true,
    BloomLevel.analiz,
    _reviewAudio,
    activity: ActivityKind.listening,
  ),
  _langFamily(
    'voice',
    'Anlatıda bilgi kaynağı ve tanıklık',
    Topic.literature,
    true,
    BloomLevel.analiz,
    _voice,
  ),
  _langFamily(
    'bounded',
    'Bilimsel Türkçede kapsam denetimi',
    Topic.literature,
    true,
    BloomLevel.degerlendirme,
    _revision,
  ),
  _langFamily(
    'modal',
    'Çeviride zorunluluk ve izin',
    Topic.language,
    true,
    BloomLevel.analiz,
    _modalEditing,
  ),
  _langFamily(
    'handover',
    'İngilizce iş devri mesajı yazma',
    Topic.language,
    true,
    BloomLevel.yaratma,
    _brief,
    creation: _briefTask,
  ),
  _langFamily(
    'scope',
    'Koşulları yorumlayıp İngilizce fiili tamamlama',
    Topic.language,
    true,
    BloomLevel.uygulama,
    _scopeBlank,
    blank: true,
  ),
];
