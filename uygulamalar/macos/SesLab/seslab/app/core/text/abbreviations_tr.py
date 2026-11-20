"""Türkçe kısaltma sözlükleri — normalizasyon ve cümle parçalama tarafından paylaşılır.

İki sınıf kısaltma vardır:
- TITLE_ABBREVS: unvan/adres kısaltmaları ("Dr. Ahmet"). Açılırken nokta ASLA
  korunmaz; ardından büyük harf gelmesi cümle sonu anlamına gelmez.
- TAIL_ABBREVS: liste sonu kısaltmaları ("elma, armut vb."). Bunlar gerçek cümle
  sonunda da durabilir; açılırken sonraki sözcük büyük harfle başlıyorsa nokta
  korunur ("vb. Şimdi" → "ve benzeri. Şimdi").
"""

TITLE_ABBREVS: dict[str, str] = {
    # Unvanlar
    "Dr.": "Doktor",
    "Dt.": "Diş Hekimi",
    "Prof.": "Profesör",
    "Doç.": "Doçent",
    "Yrd.": "Yardımcı",
    "Av.": "Avukat",
    "Uzm.": "Uzman",
    "Op.": "Operatör",
    "Ecz.": "Eczacı",
    "Müh.": "Mühendis",
    "Mim.": "Mimar",
    "Öğr.": "Öğretim",
    "Gör.": "Görevlisi",
    "Asst.": "Asistan",
    "Gen.": "General",
    "Alb.": "Albay",
    "Yzb.": "Yüzbaşı",
    "Tğm.": "Teğmen",
    # Adres
    "Sk.": "Sokak",
    "Sok.": "Sokak",
    "Cad.": "Cadde",
    "Cd.": "Cadde",
    "Blv.": "Bulvar",
    "Bulv.": "Bulvar",
    "Mah.": "Mahalle",
    "Mh.": "Mahalle",
    "Apt.": "Apartman",
    "No.": "Numara",
    # Kurum / diğer
    "T.C.": "Türkiye Cumhuriyeti",
    "İst.": "İstanbul",
    "Alm.": "Almanca",
    "İng.": "İngilizce",
    "Fr.": "Fransızca",
    "Osm.": "Osmanlıca",
    "bkz.": "bakınız",
    "Bkz.": "Bakınız",
    "örn.": "örneğin",
    "Örn.": "Örneğin",
    "yy.": "yüzyıl",
    "Hz.": "Hazreti",
    "St.": "Sen",
    "Sn.": "Sayın",
    "Md.": "Müdür",
    "Şb.": "Şube",
    "Tel.": "Telefon",
    "tel.": "telefon",
    # Ay kısaltmaları (büyük harfle, tarih bağlamında yaygın)
    "Oca.": "Ocak", "Şub.": "Şubat", "Mar.": "Mart", "Nis.": "Nisan",
    "May.": "Mayıs", "Haz.": "Haziran", "Tem.": "Temmuz", "Ağu.": "Ağustos",
    "Eyl.": "Eylül", "Eki.": "Ekim", "Kas.": "Kasım", "Ara.": "Aralık",
}

# Kelime gibi okunan akronimler (harf harf DEĞİL): telaffuzu yerleşik olanlar.
# Buradakiler dışında 2-3 harfli tüm büyük-harf kısaltmalar harf harf okunur
# (ABD → "a be de", AB → "a be"); 4+ harflilerde sesli oranı sezgiseli devreye girer.
WORD_ACRONYMS: frozenset[str] = frozenset({
    "NATO", "TÜBİTAK", "ASELSAN", "TOKİ", "TEDAŞ", "BOTAŞ", "ÖSYM",
    "UNICEF", "OPEC", "AFAD", "MASAK", "FIFA", "UEFA", "NASA", "İETT",
    "TÜİK", "KOSGEB", "TÜRKSAT", "PETKİM", "PEGASUS", "TARKAN",
    "TESK", "TÜRSAB", "SETA", "ESA",
    # Sağlık: kelime gibi okunanlar (harf harf değil)
    "PET", "KOAH", "LASIK",
})

# Harf harf yerine özel sözlü biçimi olan akronimler (case-sensitive; "MR"
# lexicon'a konmaz çünkü IGNORECASE "Mr. Smith"i de yakalardı). spell_acronyms
# bu tabloya ÖNCE bakar.
ACRONYM_OVERRIDES: dict[str, str] = {
    "MR": "emar",   # manyetik rezonans — evrensel klinik kullanım
}

# Yabancı/marka kelimeler → Türkçe fonetik yazım (TTS doğru okusun diye).
# Anahtarlar küçük harfle aranır (IGNORECASE); değer olduğu gibi yerleştirilir.
FOREIGN_LEXICON: dict[str, str] = {
    "google": "Gugıl",
    "youtube": "Yutub",
    "whatsapp": "Vatsap",
    "instagram": "İnstagram",
    "twitter": "Tivitır",
    "facebook": "Feysbuk",
    "iphone": "Ayfon",
    "ipad": "Ayped",
    "android": "Endroid",
    "netflix": "Netfliks",
    "spotify": "Spotifay",
    "bluetooth": "Blutut",
    "wi-fi": "Vayfay",
    "wifi": "Vayfay",
    "e-mail": "imeyl",
    "email": "imeyl",
    "e-posta": "eposta",
    "online": "onlayn",
    "offline": "oflayn",
    "server": "sörvır",
    "website": "vebsayt",
    "browser": "bravzır",
    "laptop": "leptop",
    "windows": "Vindovs",
    "linux": "Linuks",
    "apple": "Epıl",
    "microsoft": "Maykrosoft",
    "chatgpt": "Çet CiPiTi",
    "podcast": "podkest",
    "smartphone": "smartfon",
    "update": "apdeyt",
    "check": "çek",
}

# Tıbbi terim sözlüğü genel yabancı sözlüğe katılır (aynı 'yabanci' kuralı
# işler). Küçük harf anahtarlar; MEDICAL_LEXICON aşağıda tanımlı.

# Tıp / biyoloji / sağlık terimleri → Türkçe fonetik yazım.
# Türkçe TTS bu terimleri Latin/İngilizce imlasıyla yanlış okur (c→"c" sesi,
# ph→"pe he" vb.); klinik/biyoloji bağlamında doğru duyulmaları için burada
# fonetikleştirilir. Anahtarlar küçük harf (IGNORECASE aranır); değerler ASLA
# tümü-büyük olmamalı (akronim kuralı sonra çalışıp harf harf okur). Türkçe
# imlası zaten doğru okunan terimler (enfeksiyon, antibiyotik, protein…) DAHİL
# EDİLMEZ — yalnızca yanlış okunacaklar.
MEDICAL_LEXICON: dict[str, str] = {
    # -- Mikroorganizmalar (Latince cins/tür adları) ----------------------
    "escherichia coli": "eşerihya koli",
    "escherichia": "eşerihya",
    "helicobacter pylori": "helikobakter pilori",
    "helicobacter": "helikobakter",
    "staphylococcus aureus": "stafilokokus aureus",
    "staphylococcus": "stafilokokus",
    "streptococcus": "streptokokus",
    "pneumococcus": "pnömokokus",
    "enterococcus": "enterokokus",
    "pseudomonas": "psödomonas",
    "klebsiella": "klebsiyella",
    "shigella": "şigella",
    "candida albicans": "kandida albikans",
    "candida": "kandida",
    "aspergillus": "asperjillus",
    "mycobacterium": "mikobakteriyum",
    "tuberculosis": "tüberküloz",
    "clostridium": "klostridyum",
    "chlamydia": "klamidya",
    "mycoplasma": "mikoplazma",
    "haemophilus": "hemofilus",
    "legionella": "lejyonella",
    "listeria": "listerya",
    "enterobacter": "enterobakter",
    "acinetobacter": "asinetobakter",
    "bacillus": "basilus",
    "toxoplasma": "toksoplazma",
    "plasmodium": "plazmodyum",
    # -- Virüsler ---------------------------------------------------------
    "covid-19": "kovid on dokuz",
    "covid": "kovid",
    "sars-cov-2": "sars kov iki",
    "rhinovirus": "rinovirüs",
    "rotavirus": "rotavirüs",
    "norovirus": "norovirüs",
    "papillomavirus": "papillomavirüs",
    "cytomegalovirus": "sitomegalovirüs",
    # -- İlaçlar / etken maddeler -----------------------------------------
    "paracetamol": "parasetamol",
    "acetaminophen": "asetaminofen",
    "acetylsalicylic acid": "asetilsalisilik asit",
    "amoxicillin": "amoksisilin",
    "penicillin": "penisilin",
    "ciprofloxacin": "siprofloksasin",
    "azithromycin": "azitromisin",
    "clarithromycin": "klaritromisin",
    "ceftriaxone": "seftriakson",
    "warfarin": "varfarin",
    "insulin": "insülin",
    "cortisone": "kortizon",
    "cortisol": "kortizol",
    "prednisolone": "prednizolon",
    "dexamethasone": "deksametazon",
    "diclofenac": "diklofenak",
    "omeprazole": "omeprazol",
    "morphine": "morfin",
    "levothyroxine": "levotiroksin",
    "clopidogrel": "klopidogrel",
    # -- Biyokimya / moleküller -------------------------------------------
    "glucose": "glikoz",
    "cholesterol": "kolesterol",
    "haemoglobin": "hemoglobin",
    "triglyceride": "trigliserit",
    "triglycerides": "trigliseritler",
    "creatinine": "kreatinin",
    "enzyme": "enzim",
    "chromosome": "kromozom",
    "mitochondria": "mitokondri",
    "cytoplasm": "sitoplazma",
    "nucleus": "nükleus",
    "ribosome": "ribozom",
    "chlorophyll": "klorofil",
    "photosynthesis": "fotosentez",
    "glycogen": "glikojen",
    "adrenaline": "adrenalin",
    "epinephrine": "epinefrin",
    "dopamine": "dopamin",
    "estrogen": "östrojen",
    "oestrogen": "östrojen",
    "testosterone": "testosteron",
    "thyroxine": "tiroksin",
    # -- Hastalıklar / durumlar (Latin/İngilizce imla) --------------------
    "pneumonia": "pnömoni",
    "diabetes": "diyabet",
    "hypertension": "hipertansiyon",
    "ischemia": "iskemi",
    "carcinoma": "karsinom",
    "melanoma": "melanom",
    "lymphoma": "lenfoma",
    "leukemia": "lösemi",
    "leukaemia": "lösemi",
    "anaemia": "anemi",
    "thrombosis": "tromboz",
    "embolism": "emboli",
    "arrhythmia": "aritmi",
    "tachycardia": "taşikardi",
    "bradycardia": "bradikardi",
    "hepatitis": "hepatit",
    "gastritis": "gastrit",
    "arthritis": "artrit",
    "osteoporosis": "osteoporoz",
    "pneumothorax": "pnömotoraks",
    "oedema": "ödem",
    "cyanosis": "siyanoz",
    "dyspnea": "dispne",
    "dyspnoea": "dispne",
    "syndrome": "sendrom",
    # -- İşlemler / görüntüleme -------------------------------------------
    "bypass": "baypas",
    "pacemaker": "peysmeyker",
    "check-up": "çekap",
    "checkup": "çekap",
    "screening": "sikrining",
    "endoscopy": "endoskopi",
    "biopsy": "biyopsi",
    "chemotherapy": "kemoterapi",
    "radiotherapy": "radyoterapi",
    "ultrasound": "ultrason",
    "angiography": "anjiyografi",
    # -- Vitaminler / besinler (rakamlı) ----------------------------------
    "b12": "be on iki",
    "b6": "be altı",
    "d3": "de üç",
    "k2": "ka iki",
    "omega-3": "omega üç",
    "omega-6": "omega altı",
    # -- İmmünoloji / bağışıklık hücreleri (İng./Latin imla → TR okunuş) ---
    "lymphocyte": "lenfosit", "lymphocytes": "lenfositler",
    "leukocyte": "lökosit", "leukocytes": "lökositler",
    "leucocyte": "lökosit", "leucocytes": "lökositler",
    "phagocyte": "fagosit", "phagocytes": "fagositler",
    "phagocytosis": "fagositoz",
    "macrophage": "makrofaj", "macrophages": "makrofajlar",
    "neutrophil": "nötrofil", "neutrophils": "nötrofiller",
    "eosinophil": "eozinofil", "eosinophils": "eozinofiller",
    "basophil": "bazofil", "basophils": "bazofiller",
    "monocyte": "monosit", "monocytes": "monositler",
    "cytokine": "sitokin", "cytokines": "sitokinler",
    "chemokine": "kemokin", "chemokines": "kemokinler",
    "antibody": "antikor", "antibodies": "antikorlar",
    "antigen": "antijen", "antigens": "antijenler",
    "pathogen": "patojen", "pathogens": "patojenler",
    "immunoglobulin": "immünoglobulin",
    "histamine": "histamin", "cytotoxic": "sitotoksik",
    "lysozyme": "lizozim", "apoptosis": "apoptoz",
    "phagosome": "fagozom", "opsonin": "opsonin",
    "complement system": "kompleman sistemi",
    "innate immunity": "doğal bağışıklık",
    "adaptive immunity": "kazanılmış bağışıklık",
    # -- İmmünoglobulin sınıfları (harf-harf; karışık büyük/küçük yakalanmaz)
    "igg": "i ge ge", "igm": "i ge me", "iga": "i ge a",
    "ige": "i ge e", "igd": "i ge de",
    # -- Hücre biyolojisi / genetik ----------------------------------------
    "receptor": "reseptör", "receptors": "reseptörler",
    "membrane": "membran", "neuron": "nöron", "neurons": "nöronlar",
    "synapse": "sinaps", "synapses": "sinapslar",
    "nucleotide": "nükleotit", "nucleotides": "nükleotitler",
    "nucleic": "nükleik", "chromatin": "kromatin",
    "mitochondrion": "mitokondri", "endoplasmic": "endoplazmik",
    "lysosome": "lizozom", "lysosomes": "lizozomlar",
    "cytosine": "sitozin", "thymine": "timin", "guanine": "guanin",
    "adenine": "adenin", "uracil": "urasil",
    "protease": "proteaz", "lipase": "lipaz", "amylase": "amilaz",
    "hormone": "hormon", "hormones": "hormonlar",
    "phenotype": "fenotip", "genotype": "genotip",
    "allele": "alel", "alleles": "aleller",
    "meiosis": "mayoz", "mitosis": "mitoz",
    # -- Hastalıklar / durumlar (ek) --------------------------------------
    "septicemia": "septisemi", "septicaemia": "septisemi",
    "meningitis": "menenjit", "bronchitis": "bronşit",
    "nephritis": "nefrit", "dermatitis": "dermatit",
    "cirrhosis": "siroz", "necrosis": "nekroz",
    "metastasis": "metastaz", "atherosclerosis": "ateroskleroz",
    "hemorrhage": "hemoraji", "haemorrhage": "hemoraji",
    "schizophrenia": "şizofreni", "epilepsy": "epilepsi",
    "asthma": "astım", "leukocytosis": "lökositoz",
    "sepsis": "sepsis",
    # -- Anatomi ----------------------------------------------------------
    "esophagus": "özofagus", "oesophagus": "özofagus",
    "trachea": "trakea", "larynx": "larinks", "pharynx": "farinks",
    "cerebrum": "serebrum", "cerebellum": "serebellum",
    # -- Kelime gibi okunan sağlık akronimleri ----------------------------
    "hiv": "eyç ay vi",
    "aids": "eyts",
}

# Bilim (kimya/fizik/matematik) terimleri → Türkçe fonetik yazım.
# Yalnız Türkçe imlasıyla YANLIŞ okunacak Latin/İngilizce biçimler; Türkçe
# karşılığı zaten doğru okunanlar (atom, proton, elektron, delta, sigma…) YOK.
# Ortak İngilizce homograflar (gold, lead, iron, tin…) bilerek DIŞARIDA — Türkçe
# metinde nadir + yanlış eşleşme riski.
SCIENCE_LEXICON: dict[str, str] = {
    # -- Element adları (Latin/İngilizce imla → Türkçe okunuş) -------------
    "hydrogen": "hidrojen", "helium": "helyum", "lithium": "lityum",
    "beryllium": "berilyum", "nitrogen": "azot", "oxygen": "oksijen",
    "fluorine": "flor", "sodium": "sodyum", "magnesium": "magnezyum",
    "aluminium": "alüminyum", "aluminum": "alüminyum", "silicon": "silisyum",
    "phosphorus": "fosfor", "sulfur": "kükürt", "sulphur": "kükürt",
    "chlorine": "klor", "potassium": "potasyum", "calcium": "kalsiyum",
    "titanium": "titanyum", "chromium": "krom", "manganese": "manganez",
    "cobalt": "kobalt", "nickel": "nikel", "arsenic": "arsenik",
    "bromine": "brom", "iodine": "iyot", "barium": "baryum",
    "platinum": "platin", "uranium": "uranyum", "tungsten": "volfram",
    "helium": "helyum", "neon": "neon", "argon": "argon", "krypton": "kripton",
    "xenon": "ksenon", "radium": "radyum", "plutonium": "plütonyum",
    # -- Yunan harf adları (yazılı; Türkçe imlası farklı olanlar) ----------
    "alpha": "alfa", "gamma": "gama", "theta": "teta", "phi": "fi",
    "chi": "ki", "psi": "psi", "omicron": "omikron", "upsilon": "üpsilon",
    # -- Element adları (ek: İng./Latin imla → Türkçe okunuş) --------------
    "carbon": "karbon", "boron": "bor", "selenium": "selenyum",
    "zinc": "çinko", "cesium": "sezyum", "caesium": "sezyum",
    "rubidium": "rubidyum", "strontium": "stronsiyum",
    "gallium": "galyum", "germanium": "germanyum",
    "palladium": "paladyum", "rhodium": "rodyum", "iridium": "iridyum",
    "osmium": "osmiyum", "antimony": "antimon", "bismuth": "bizmut",
    "tellurium": "tellür", "polonium": "polonyum", "thorium": "toryum",
    # -- Parçacık/atom fiziği ---------------------------------------------
    "electron": "elektron", "photon": "foton", "positron": "pozitron",
    "neutrino": "nötrino", "quark": "kuark", "boson": "bozon",
    "fermion": "fermiyon", "muon": "müon",
    "entropy": "entropi", "enthalpy": "entalpi",
    # -- Kimya (ek) -------------------------------------------------------
    "molecular": "moleküler", "hydroxide": "hidroksit",
    "sulfate": "sülfat", "sulphate": "sülfat", "nitrate": "nitrat",
    "carbonate": "karbonat", "chloride": "klorür", "oxide": "oksit",
    "phosphate": "fosfat", "acetate": "asetat", "ammonium": "amonyum",
    "hydroxyl": "hidroksil", "oxidation": "oksidasyon",
    "ion": "iyon", "cation": "katyon", "anion": "anyon",
    "electrolyte": "elektrolit",
    # -- Bilim/İngilizce terimler (Türkçede fonetik biçim) ----------------
    "quantum": "kuantum", "neutron": "nötron", "voltage": "voltaj",
    "molecule": "molekül", "equation": "ikueyşın",
    "theorem": "teorem", "hypothesis": "hipotez", "isotope": "izotop",
    "catalyst": "katalizör", "polymer": "polimer", "enzyme": "enzim",
    "spectrum": "spektrum", "frequency": "frekans", "amplitude": "amplitüt",
}

# Kimyasal formüller → sözlü okunuş (curated; genel ayrıştırma RİSKLİ, yok).
# Anahtarlar ASCII; kural unicode altsimgeleri (H₂O) önce ASCII'ye çevirir.
CHEM_FORMULAS: dict[str, str] = {
    "H2O": "su", "CO2": "karbondioksit", "CO": "karbonmonoksit",
    "O2": "oksijen", "O3": "ozon", "N2": "azot gazı", "H2": "hidrojen gazı",
    "NH3": "amonyak", "CH4": "metan", "NaCl": "sodyum klorür",
    "HCl": "hidroklorik asit", "H2SO4": "sülfürik asit", "HNO3": "nitrik asit",
    "NaOH": "sodyum hidroksit", "KOH": "potasyum hidroksit",
    "CaCO3": "kalsiyum karbonat", "NaHCO3": "sodyum bikarbonat",
    "C6H12O6": "glikoz", "C2H5OH": "etanol", "CH3COOH": "asetik asit",
    "H2O2": "hidrojen peroksit", "SO2": "kükürt dioksit", "CaO": "kalsiyum oksit",
    "Fe2O3": "demir üç oksit", "H3PO4": "fosforik asit", "CaCl2": "kalsiyum klorür",
    # -- Ek bileşikler ----------------------------------------------------
    "N2O": "diazot monoksit", "NO2": "azot dioksit", "SO3": "kükürt trioksit",
    "H2S": "hidrojen sülfür", "H2CO3": "karbonik asit",
    "CaSO4": "kalsiyum sülfat", "MgO": "magnezyum oksit",
    "MgSO4": "magnezyum sülfat", "KCl": "potasyum klorür",
    "KNO3": "potasyum nitrat", "AgNO3": "gümüş nitrat", "AgCl": "gümüş klorür",
    "CuSO4": "bakır sülfat", "ZnO": "çinko oksit", "Al2O3": "alüminyum oksit",
    "SiO2": "silisyum dioksit", "P2O5": "difosfor pentaoksit",
    "CH3OH": "metanol", "C3H8": "propan", "C4H10": "bütan",
    "Ca(OH)2": "kalsiyum hidroksit", "Mg(OH)2": "magnezyum hidroksit",
}

# Biyoloji terimleri → Türkçe fonetik yazım (Campbell Biology'den OCR ile
# çıkarılıp küratörlenen Latince tür adları ve taksonomik gruplar).
# İLKE korundu: yalnız Türkçe imlasıyla YANLIŞ okunacaklar. Latince/İngilizce
# 'c' Türkçede 'c'(j) sesi verir (paramecium→"paramejium" olurdu), 'ph' p+h,
# 'x' harf, 'ch'/'th' bozuk okunur → doğru fonetiğe çevrilir. Türkçe imlaya
# çevrilmiş biyoloji terimleri (fotosentez, ökaryot, ksilem…) kitapta zaten
# doğru yazılı olduğundan DAHİL EDİLMEZ. Özel isimler (Darwin, Watson) ve
# mevcut akronim katmanının okuduğu formüller (DNA, ATP, RNA) burada YOK.
BIOLOGY_LEXICON: dict[str, str] = {
    # -- Latince tür/cins adları (Genus species) --------------------------
    "saccharomyces cerevisiae": "sakaromises serevizye",
    "saccharomyces": "sakaromises",
    "caenorhabditis elegans": "senorabditis elegans",
    "caenorhabditis": "senorabditis",
    "drosophila melanogaster": "drozofila melanogaster",
    "drosophila": "drozofila",
    "homo sapiens": "homo sapiyens",
    "poecilia reticulata": "posilya retikulata",
    "paramecium caudatum": "paramesyum kaudatum",
    "paramecium": "paramesyum",
    "panthera pardus": "pantera pardus", "panthera tigris": "pantera tigris",
    "panthera": "pantera",
    "trichomonas vaginalis": "trikomonas vajinalis",
    "trichomonas": "trikomonas",
    "treponema pallidum": "treponema pallidum",
    "australopithecus": "avustralopitekus",
    "geospiza": "geospiza",
    "neisseria gonorrhoeae": "naysserya gonore", "neisseria": "naysserya",
    "entamoeba histolytica": "entamiba histolitika", "entamoeba": "entamiba",
    "phytophthora infestans": "fitoftora infestans", "phytophthora": "fitoftora",
    "pneumocystis": "nömosistis",
    "archaeopteryx": "arkeopteriks",
    "hyracotherium": "hirakoteryum",
    "equus": "ekus", "triticum": "tritikum",
    # -- Taksonomik gruplar (şube/sınıf; Latince, kitapta bu imlayla) ------
    "arthropoda": "artropoda", "arthropod": "artropot",
    "cephalochordata": "sefalokordata",
    "apicomplexa": "apikompleksa",
    "lophotrochozoa": "lofotrokozoa",
    "platyhelminthes": "platihelmintes",
    "ctenophora": "tenofora", "anthozoa": "antozoa", "scyphozoa": "sifozoa",
    "cephalopoda": "sefalopoda", "polyplacophora": "poliplakofora",
    "osteichthyes": "osteiktiyes", "chondrichthyes": "kondriktiyes",
    "gnathostomata": "gnatostomata", "myxini": "miksini",
    "amphibia": "amfibya", "squamata": "skuamata",
    "rhodophyta": "rodofita", "phaeophyta": "feofita",
    "chlorophyta": "klorofita", "chlorophyceae": "klorofise",
    "bryophyta": "briyofita", "bryophyte": "briyofit",
    "lycophyta": "likofita", "pterophyta": "pterofita",
    "hepatophyta": "hepatofita", "coniferophyta": "koniferofita",
    "ginkgophyta": "ginkgofita", "cycadophyta": "sikadofita",
    "gnetophyta": "gnetofita", "anthophyta": "antofita",
    "anthocerophyta": "antoserofita", "streptophyta": "streptofita",
    "charophyceae": "karofise", "bacillariophyta": "basilariyofita",
    "chrysophyta": "krizofita", "ciliophora": "siliyofora",
    "phoronida": "foronida", "holothuroidea": "holoturoidea",
    "ophiuroidea": "ofiuroidea", "cephalaspidomorphi": "sefalaspidomorfi",
    "eutheria": "öteria", "eutherian": "öteriyan",
    "sphagnum": "sfagnum", "equisetum": "ekuisetum",
    "welwitschia": "velviçya", "ephedra": "efedra",
}

# Bilim insanı adları → Türkçe fonetik. Ders anlatımında sürekli geçerler ve
# XTTS bunları Türkçe imla kurallarıyla okuyup tanınmaz hale getiriyordu
# ("Crick" → "cırik", "Stahl" → "stahıl"). Türkçede zaten doğru okunan adlar
# (Mendel, Morgan, Darwin okunuşu imlasına yakın) burada YOK.
SCIENTIST_LEXICON: dict[str, str] = {
    # -- Moleküler genetik --------------------------------------------------
    "watson": "vatsın", "crick": "krik", "rosalind franklin": "rozalind franklin",
    "chargaff": "şargaf", "meselson": "meselsın", "stahl": "ştal",
    "hershey": "herşi", "chase": "çeys", "griffith": "grifit",
    "avery": "eyveri", "mcclintock": "meklintok", "sanger": "senger",
    "okazaki": "okazaki", "kornberg": "kornberg", "nirenberg": "nirenberg",
    "khorana": "korana", "temin": "temin", "baltimore": "baltimor",
    "mullis": "mallis", "jacob": "jakob", "monod": "mono",
    "doudna": "daudna", "charpentier": "şarpantye",
    # -- Hücre ve kalıtım ---------------------------------------------------
    "sutton": "satın", "boveri": "boveri", "hooke": "huk",
    "leeuwenhoek": "levenhuk", "schleiden": "şlayden", "schwann": "şvan",
    "virchow": "virhov", "golgi": "golci", "ramón y cajal": "ramon i kahal",
    "purkinje": "purkinye", "langerhans": "langerhans",
    # -- Evrim ve sınıflandırma --------------------------------------------
    "lamarck": "lamark", "wallace": "vallas", "linnaeus": "linneus",
    "haeckel": "hekel", "malthus": "maltus", "lyell": "layıl",
    "beagle": "bigıl", "galapagos": "galapagos", "dobzhansky": "dobjanski",
    "mayr": "mayr", "gould": "guld", "dawkins": "dokins",
    # -- Mikrobiyoloji ve tıp ----------------------------------------------
    "pasteur": "pastör", "koch": "koh", "fleming": "fleming",
    "jenner": "cenır", "lister": "listır", "ehrlich": "erlih",
    "salk": "salk", "sabin": "seybin", "semmelweis": "zemelvays",
    # -- Biyokimya ve fizyoloji --------------------------------------------
    "krebs": "krebs", "calvin": "kelvin", "benson": "bensın",
    "mitchell": "miçıl", "lynen": "linen", "warburg": "varburg",
    "buchner": "buhner", "michaelis": "mihaelis", "menten": "menten",
    "pauling": "poling", "hodgkin": "hocgin", "huxley": "haksli",
    "harvey": "harvi", "bernard": "bernar", "cannon": "kenın",
    "loewi": "lövi", "sherrington": "şerington",
}

# Kısmen küçük harfli ya da rakam içeren kısaltmalar. Akronim kuralı yalnız
# tümü-büyük dizileri yakaladığı için "mRNA" ve "FADH2" ham imlalarıyla
# okunuyordu ("mırna", "fadhiki"); burada harf harf yazılırlar.
BIO_ACRONYM_LEXICON: dict[str, str] = {
    "mrna": "me ere ne a", "trna": "te ere ne a", "rrna": "re ere ne a",
    "mirna": "mi ere ne a", "sirna": "si ere ne a", "snrna": "es en ere ne a",
    "snorna": "es en o ere ne a", "lncrna": "el en se ere ne a",
    "ncrna": "en se ere ne a", "hnrna": "he en ere ne a",
    "cdna": "se de ne a", "mtdna": "em te de ne a", "rdna": "re de ne a",
    "ssdna": "es es de ne a", "dsdna": "de es de ne a",
    "rnai": "ere ne a i", "crispr": "krispır", "cas9": "kas dokuz",
    "fadh2": "fe a de he iki", "fad": "fe a de",
    "nadph": "ne a de pe he", "nadp": "ne a de pe", "nadph2": "ne a de pe he iki",
    "adp": "a de pe", "amp": "a me pe", "camp": "se a me pe",
    "cgmp": "se ge me pe", "gtp": "ge te pe", "gdp": "ge de pe",
    "utp": "u te pe", "ctp": "se te pe", "atpaz": "a te pe az",
    "atpase": "a te pe az", "coa": "ko a", "asetil-coa": "asetil ko a",
    "acetyl-coa": "asetil ko a", "pcr": "pe se re", "elisa": "eliza",
    "orf": "o ere fe", "utr": "u te re",
    "snp": "es en pe", "gwas": "ci vas", "qtl": "ku te el",
}

# Ders metninde geçen İngilizce terimler ve kimyasal formüller. Formüller
# harf harf değil, Türkçe adlarıyla okunur: "CO2" bir sohbette "se o iki"
# değil "karbondioksit"tir.
BIO_TERM_LEXICON: dict[str, str] = {
    "crossing over": "krosing ovır", "crossing-over": "krosing ovır",
    "crossover": "krosovır", "leading strand": "liding strend",
    "lagging strand": "leging strend", "primer": "praymır",
    "splicing": "splaysing", "frameshift": "freymşift",
    "knockout": "nokaut", "western blot": "vestırn blot",
    "southern blot": "sadırn blot", "northern blot": "nordırn blot",
    "housekeeping": "hauskiping", "feedback": "fidbek",
    "turnover": "törnovır", "hotspot": "hotspot", "wild type": "vayld tayp",
    "wild-type": "vayld tayp", "checkpoint": "çekpoint",
    "spindle": "spindıl", "cleavage": "kliviç", "fitness": "fitnıs",
    "founder effect": "faundır efekt", "bottleneck": "botılnek",
    "co2": "karbondioksit", "h2o": "su", "o2": "oksijen", "n2": "azot",
    "nh3": "amonyak", "nh4": "amonyum", "ch4": "metan",
    "h2o2": "hidrojen peroksit", "hco3": "bikarbonat",
    "na+": "sodyum", "k+": "potasyum", "ca2+": "kalsiyum",
    "mg2+": "magnezyum", "cl-": "klor", "h+": "hidrojen iyonu",
}

# Tıbbi + bilim + biyoloji sözlüklerini genel yabancı sözlüğe kat (normalize_tr
# içe aktarmadan önce, import sırasında çalışır; 'yabanci' kuralının deseni
# birleşik anahtarlardan kurulur). Çakışan anahtar yok.
FOREIGN_LEXICON.update(MEDICAL_LEXICON)
FOREIGN_LEXICON.update(SCIENCE_LEXICON)
FOREIGN_LEXICON.update(BIOLOGY_LEXICON)
FOREIGN_LEXICON.update(SCIENTIST_LEXICON)
FOREIGN_LEXICON.update(BIO_ACRONYM_LEXICON)
FOREIGN_LEXICON.update(BIO_TERM_LEXICON)

TAIL_ABBREVS: dict[str, str] = {
    "vb.": "ve benzeri",
    "vs.": "vesaire",
    "vd.": "ve diğerleri",
}

ABBREVIATIONS: dict[str, str] = {**TITLE_ABBREVS, **TAIL_ABBREVS}

# Cümle parçalayıcının ASLA cümle sonu saymayacağı nokta ile biten belirteçler.
# (TAIL_ABBREVS bilerek dahil değil: "elma vb. Şimdi..." gerçek bir sınır olabilir.)
NEVER_SENTENCE_END: frozenset[str] = frozenset(TITLE_ABBREVS.keys())

# Türkçe harf adları — sesli harf içermeyen büyük harf kısaltmalarını
# harf harf okumak için (TBMM → "te be me me").
LETTER_NAMES: dict[str, str] = {
    "A": "a", "B": "be", "C": "ce", "Ç": "çe", "D": "de", "E": "e",
    "F": "fe", "G": "ge", "Ğ": "yumuşak ge", "H": "he", "I": "ı", "İ": "i",
    "J": "je", "K": "ke", "L": "le", "M": "me", "N": "ne", "O": "o",
    "Ö": "ö", "P": "pe", "R": "re", "S": "se", "Ş": "şe", "T": "te",
    "U": "u", "Ü": "ü", "V": "ve", "Y": "ye", "Z": "ze",
    "Q": "kü", "W": "çift ve", "X": "iks",
}

TR_VOWELS = set("AEIİOÖUÜ")
