/* Kes ve Çöz istemcisi — bağımlılıksız, alan eksiklerine dayanıklı. */
(function () {
  "use strict";

  var kok = document.querySelector("[data-kvc-kok]");
  if (!kok) return;

  var form = kok.querySelector("[data-kvc-form]");
  var dosya = kok.querySelector("[data-kvc-dosya]");
  var birakma = kok.querySelector("[data-kvc-birakma]");
  var secim = kok.querySelector("[data-kvc-secim]");
  var dosyaAdi = kok.querySelector("[data-kvc-dosya-adi]");
  var dosyaBoyutu = kok.querySelector("[data-kvc-dosya-boyutu]");
  var dosyaTuru = kok.querySelector("[data-kvc-dosya-turu]");
  var temizle = kok.querySelector("[data-kvc-temizle]");
  var formHatasi = kok.querySelector("[data-kvc-form-hatasi]");
  var baslat = kok.querySelector("[data-kvc-baslat]");
  var baslatYazi = kok.querySelector("[data-kvc-baslat-yazi]");
  var islem = kok.querySelector("[data-kvc-islem]");
  var durumYazi = kok.querySelector("[data-kvc-durum-yazi]");
  var mesaj = kok.querySelector("[data-kvc-mesaj]");
  var durdur = kok.querySelector("[data-kvc-durdur]");
  var ilerleme = kok.querySelector("[data-kvc-ilerleme]");
  var ilerlemeAciklama = kok.querySelector("[data-kvc-ilerleme-aciklama]");
  var yuzde = kok.querySelector("[data-kvc-yuzde]");
  var isHatasi = kok.querySelector("[data-kvc-is-hatasi]");
  var sonuclar = kok.querySelector("[data-kvc-sonuclar]");
  var soruListesi = kok.querySelector("[data-kvc-soru-listesi]");
  var bosFiltre = kok.querySelector("[data-kvc-bos-filtre]");
  var bos = kok.querySelector("[data-kvc-bos]");
  var bildirim = kok.querySelector("#kvc-canli-bildirim");
  var filtreDugmeleri = kok.querySelectorAll("[data-kvc-filtre]");

  if (!form || !dosya || !islem || !soruListesi) return;

  var UZANTILAR = ["pdf", "docx", "png", "jpg", "jpeg", "tif", "tiff", "bmp", "webp", "gif"];
  var TERMINAL_TAMAM = ["tamam", "tamamlandi", "tamamlandı", "bitti", "completed", "done", "success"];
  var TERMINAL_KISMI = ["kismi", "kısmi", "partial", "partially_completed", "tamamlandi_kismi"];
  var TERMINAL_HATA = ["hata", "hatali", "hatalı", "failed", "error"];
  var TERMINAL_IPTAL = ["durduruldu", "iptal", "iptal_edildi", "cancelled", "canceled", "stopped"];
  var isKimligi = kok.getAttribute("data-is-id") || "";
  var zamanlayici = null;
  var istekDenetleyici = null;
  var etkin = false;
  var sonDurum = "";
  var sonSorularImzasi = "";
  var etkinFiltre = "tumu";
  var ardisikAgHatasi = 0;
  var sonReferansOzeti = { karsilastirilan: 0, anahtarli: 0, dogru: 0, yanlis: 0 };

  function ilk() {
    for (var i = 0; i < arguments.length; i += 1) {
      var deger = arguments[i];
      if (deger !== undefined && deger !== null && deger !== "") return deger;
    }
    return null;
  }

  function icVeri(veri) {
    if (!veri || typeof veri !== "object") return {};
    return veri.is && typeof veri.is === "object" ? Object.assign({}, veri, veri.is) : veri;
  }

  function sadeDurum(deger) {
    if (typeof deger !== "string") return "";
    return deger.trim().toLocaleLowerCase("tr-TR").replace(/[\s-]+/g, "_");
  }

  function terminalMi(durum) {
    return TERMINAL_TAMAM.indexOf(durum) >= 0 ||
      TERMINAL_KISMI.indexOf(durum) >= 0 ||
      TERMINAL_HATA.indexOf(durum) >= 0 ||
      TERMINAL_IPTAL.indexOf(durum) >= 0;
  }

  function sayi(deger, varsayilan) {
    var sonuc = Number(deger);
    return Number.isFinite(sonuc) && sonuc >= 0 ? Math.round(sonuc) : varsayilan;
  }

  function metin(deger, varsayilan) {
    if (deger === undefined || deger === null || deger === "") return varsayilan || "";
    return String(deger);
  }

  function bayrak(deger) {
    if (typeof deger === "string") return ["1", "true", "evet", "yes"].indexOf(sadeDurum(deger)) >= 0;
    return Boolean(deger);
  }

  function baytBicimle(bayt) {
    if (bayt < 1024) return bayt + " B";
    if (bayt < 1024 * 1024) return (bayt / 1024).toFixed(1).replace(".0", "") + " KB";
    return (bayt / (1024 * 1024)).toFixed(1).replace(".0", "") + " MB";
  }

  function uzanti(dosyaAdiMetni) {
    var parcalar = String(dosyaAdiMetni || "").toLocaleLowerCase("tr-TR").split(".");
    return parcalar.length > 1 ? parcalar.pop() : "";
  }

  function hataGoster(hedef, hataMetni) {
    if (!hedef) return;
    hedef.textContent = hataMetni;
    hedef.hidden = false;
  }

  function hataTemizle(hedef) {
    if (!hedef) return;
    hedef.textContent = "";
    hedef.hidden = true;
    hedef.classList.remove("kvc-kismi-uyari");
  }

  function duyur(yazi) {
    if (bildirim) bildirim.textContent = yazi;
  }

  function dosyayiDogrula(secilen) {
    if (!secilen) return "Bir PDF, DOCX veya sayfa görseli seç.";
    if (UZANTILAR.indexOf(uzanti(secilen.name)) < 0) {
      return "Bu dosya türü desteklenmiyor. PDF, DOCX veya desteklenen bir görsel seç.";
    }
    if (!secilen.size) return "Seçilen dosya boş görünüyor.";
    var azami = Number(dosya.getAttribute("data-azami-bayt")) || 419430400;
    if (secilen.size > azami) return "Dosya 400 MB sınırını aşıyor.";
    return "";
  }

  function secimiGoster(secilen) {
    if (!secilen) {
      secim.hidden = true;
      return;
    }
    dosyaAdi.textContent = secilen.name;
    dosyaBoyutu.textContent = baytBicimle(secilen.size) + " · işlem otomatik başlayacak";
    dosyaTuru.textContent = (uzanti(secilen.name) || "DOSYA").toLocaleUpperCase("tr-TR");
    secim.hidden = false;
  }

  function secimDegisti() {
    var secilen = dosya.files && dosya.files[0];
    var hata = dosyayiDogrula(secilen);
    secimiGoster(secilen);
    hataTemizle(formHatasi);
    if (hata) {
      hataGoster(formHatasi, hata);
      duyur(hata);
      return;
    }
    if (!etkin && window.fetch && window.FormData) {
      window.setTimeout(function () {
        if (!etkin && dosya.files && dosya.files[0] === secilen) form.requestSubmit();
      }, 180);
    }
  }

  function formuEtkinlestir(aktifMi) {
    etkin = aktifMi;
    dosya.disabled = aktifMi;
    baslat.disabled = aktifMi;
    if (baslatYazi) baslatYazi.textContent = aktifMi ? "İşlem sürüyor" : "Kes ve çözmeyi başlat";
    if (durdur) durdur.disabled = !aktifMi || !isKimligi;
    islem.setAttribute("aria-busy", aktifMi ? "true" : "false");
  }

  function asamaAdi(raw) {
    var deger = sadeDurum(raw);
    if (TERMINAL_TAMAM.indexOf(deger) >= 0) return "tamamlandi";
    if (deger.indexOf("coz") >= 0 || deger.indexOf("solve") >= 0) return "cozuluyor";
    if (deger.indexOf("kes") >= 0 || deger.indexOf("crop") >= 0 || deger.indexOf("detect") >= 0) return "kesiliyor";
    return "yukleniyor";
  }

  function asamalariGuncelle(asama, terminalDurum) {
    var siralama = ["yukleniyor", "kesiliyor", "cozuluyor", "tamamlandi"];
    var etkinSira = siralama.indexOf(asama);
    if (etkinSira < 0) etkinSira = 0;
    kok.querySelectorAll("[data-kvc-asama]").forEach(function (oge) {
      var sira = siralama.indexOf(oge.getAttribute("data-kvc-asama"));
      oge.classList.toggle("etkin", !terminalDurum && sira === etkinSira);
      oge.classList.toggle("tamam", TERMINAL_TAMAM.indexOf(terminalDurum) >= 0 || sira < etkinSira);
    });
  }

  function sorulariAl(veri) {
    var aday = ilk(veri.sorular, veri.questions, veri.sonuclar, veri.results);
    return Array.isArray(aday) ? aday : [];
  }

  function soruIncelenecekMi(soru) {
    var durum = sadeDurum(ilk(soru.durum, soru.status));
    return bayrak(ilk(soru.incele, soru.inceleme_gerekli, soru.review_required,
      soru.review, soru.belirsiz, soru.cozum && soru.cozum.incele)) ||
      durum.indexOf("incele") >= 0 || durum.indexOf("belirsiz") >= 0;
  }

  function soruCozulmusMu(soru) {
    var durum = sadeDurum(ilk(soru.durum, soru.status));
    return Boolean(ilk(soru.cevap, soru.yanit, soru.answer, soru.cozum && soru.cozum.cevap)) ||
      TERMINAL_TAMAM.indexOf(durum) >= 0;
  }

  function guvenYazisi(deger) {
    var g = Number(deger);
    if (!Number.isFinite(g)) return "";
    if (g >= 0 && g <= 1) g *= 100;
    return "%" + Math.max(0, Math.min(100, Math.round(g))) + " güven";
  }

  function oge(etiket, sinif, yazi) {
    var sonuc = document.createElement(etiket);
    if (sinif) sonuc.className = sinif;
    if (yazi !== undefined && yazi !== null) sonuc.textContent = String(yazi);
    return sonuc;
  }

  function guvenliGorselYolu(deger) {
    if (typeof deger !== "string" || deger.indexOf("/kes-ve-coz/") !== 0 ||
        deger.indexOf("//") === 0 || /[\\\r\n]/.test(deger)) return "";
    try {
      var adres = new URL(deger, window.location.origin);
      if (adres.origin !== window.location.origin || adres.pathname.indexOf("/kes-ve-coz/") !== 0) {
        return "";
      }
      return adres.pathname + adres.search;
    } catch (e) {
      return "";
    }
  }

  function uyarilariAl(soru) {
    var deger = ilk(soru.uyarilar, soru.warnings, soru.uyari,
      soru.cozum && soru.cozum.uyarilar);
    if (Array.isArray(deger)) return deger.filter(Boolean).map(String);
    return deger ? [String(deger)] : [];
  }

  function soruKarti(soru, sira) {
    soru = soru && typeof soru === "object" ? soru : { soru: metin(soru, "") };
    var incele = soruIncelenecekMi(soru);
    var kart = oge("article", "kvc-soru-karti" + (incele ? " inceleme" : ""));
    kart.dataset.kvcInceleme = incele ? "1" : "0";
    kart.dataset.kvcReferansUyusmuyor = soru.referansla_eslesiyor === false ? "1" : "0";

    var ust = oge("header", "kvc-soru-ust");
    var goruntulenenSira = metin(ilk(soru.no, soru.sira), sira + 1);
    ust.appendChild(oge("span", "kvc-soru-no", goruntulenenSira));
    var baslik = oge("div", "kvc-soru-baslik");
    var soruMetni = metin(ilk(soru.soru, soru.soru_metni, soru.metin, soru.baslik), "Soru metni hazırlanıyor…");
    baslik.appendChild(oge("h3", "", soruMetni));
    var sayfa = ilk(soru.sayfa, soru.sayfa_no, soru.page);
    var kaynak = sayfa !== null ? "Sayfa " + sayfa : metin(ilk(soru.kaynak, soru.source), "Belgeden çıkarıldı");
    baslik.appendChild(oge("small", "", kaynak));
    ust.appendChild(baslik);

    var rozetler = oge("div", "kvc-soru-rozetler");
    var guven = guvenYazisi(ilk(soru.guven, soru.confidence, soru.kesim_guveni,
      soru.cozum && soru.cozum.guven));
    if (guven) rozetler.appendChild(oge("span", "kvc-rozet", guven));
    if (incele) rozetler.appendChild(oge("span", "kvc-rozet inceleme", "İncele"));
    if (soru.cozum && soru.cozum.uretim_yontemi === "tam_referans") {
      rozetler.appendChild(oge("span", "kvc-rozet kaynakli", "Yerel arşivde birebir"));
    }
    if (soru.referansla_eslesiyor === true) {
      rozetler.appendChild(oge("span", "kvc-rozet dogru", "Anahtarla eşleşti"));
    } else if (soru.referansla_eslesiyor === false) {
      rozetler.appendChild(oge("span", "kvc-rozet hata", "Anahtarla uyuşmadı"));
    }
    var soruDurumu = sadeDurum(ilk(soru.durum, soru.status));
    if (TERMINAL_HATA.indexOf(soruDurumu) >= 0) rozetler.appendChild(oge("span", "kvc-rozet hata", "Çözülemedi"));
    ust.appendChild(rozetler);
    kart.appendChild(ust);

    var govde = oge("div", "kvc-soru-govde");
    var soruIcerik = oge("div", "kvc-soru-icerik");
    var gorselYolu = guvenliGorselYolu(soru.gorsel_url);
    if (gorselYolu) {
      soruIcerik.classList.add("gorselli");
      var sekil = oge("figure", "kvc-kesim-gorseli");
      var gorsel = oge("img", "");
      gorsel.src = gorselYolu;
      gorsel.alt = "Kesilen soru " + goruntulenenSira;
      gorsel.loading = "lazy";
      gorsel.decoding = "async";
      sekil.appendChild(gorsel);
      sekil.appendChild(oge("figcaption", "", "Kesilen soru " + goruntulenenSira));
      soruIcerik.appendChild(sekil);
    }
    soruIcerik.appendChild(oge("p", "kvc-soru-metni", soruMetni));
    govde.appendChild(soruIcerik);
    var cevapKutusu = oge("div", "kvc-cevap");
    var anahtarlaUyusmuyor = soru.referansla_eslesiyor === false;
    var kaynakAnahtari = metin(soru.kaynak_anahtar_cevabi, "");
    cevapKutusu.appendChild(oge(
      "span",
      "",
      anahtarlaUyusmuyor && kaynakAnahtari ?
        "Belgedeki cevap anahtarı" :
        (anahtarlaUyusmuyor ? "Model önerisi — doğrulanmadı" : "Cevap")
    ));
    var cevap = ilk(soru.cevap, soru.yanit, soru.answer, soru.cozum && soru.cozum.cevap);
    cevapKutusu.appendChild(oge("strong", "", metin(
      kaynakAnahtari || cevap,
      soruCozulmusMu(soru) ? "Cevap kaydedildi" : "Çözüm bekleniyor"
    )));
    if (anahtarlaUyusmuyor && kaynakAnahtari && cevap) {
      cevapKutusu.appendChild(oge(
        "small",
        "kvc-model-onerisi",
        "Model önerisi: " + metin(cevap, "—") + " — doğrulanmadı"
      ));
    }
    govde.appendChild(cevapKutusu);

    var cozum = ilk(soru.cozum_ozeti, soru.ozet, soru.explanation, soru.aciklama);
    if (!cozum && typeof soru.cozum === "string") cozum = soru.cozum;
    if (!cozum && Array.isArray(soru.adimlar)) cozum = soru.adimlar.join("\n");
    if (!cozum && soru.cozum && Array.isArray(soru.cozum.adimlar)) {
      cozum = soru.cozum.adimlar.join("\n");
    }
    if (cozum) {
      var cozumMetni = anahtarlaUyusmuyor ?
        "Model açıklaması cevap anahtarıyla çelişiyor; doğru çözüm olarak kullanma.\n" + cozum :
        cozum;
      govde.appendChild(oge("p", "kvc-cozum-ozeti", cozumMetni));
    }

    var uyarilar = uyarilariAl(soru);
    if (uyarilar.length) {
      var liste = oge("ul", "kvc-uyarilar");
      uyarilar.forEach(function (uyari) { liste.appendChild(oge("li", "", uyari)); });
      govde.appendChild(liste);
    }
    kart.appendChild(govde);
    return kart;
  }

  function filtreyiUygula() {
    var gorunen = 0;
    soruListesi.querySelectorAll(".kvc-soru-karti").forEach(function (kart) {
      var goster = etkinFiltre === "tumu" ||
        (etkinFiltre === "inceleme" && kart.dataset.kvcInceleme === "1") ||
        (etkinFiltre === "uyusmayan" && kart.dataset.kvcReferansUyusmuyor === "1");
      kart.hidden = !goster;
      if (goster) gorunen += 1;
    });
    bosFiltre.hidden = gorunen > 0;
  }

  function sorulariCiz(sorular) {
    var imza;
    try { imza = JSON.stringify(sorular); } catch (e) { imza = String(sorular.length); }
    if (imza === sonSorularImzasi) return;
    sonSorularImzasi = imza;
    soruListesi.textContent = "";
    sorular.forEach(function (soru, sira) { soruListesi.appendChild(soruKarti(soru, sira)); });
    sonuclar.hidden = sorular.length === 0;
    filtreyiUygula();
  }

  function ilerlemeDegeri(veri, asama, toplam, cozulen) {
    var ham = ilk(
      veri.ilerleme && typeof veri.ilerleme === "object" ? ilk(veri.ilerleme.yuzde, veri.ilerleme.progress) : veri.ilerleme,
      veri.progress,
      veri.yuzde
    );
    var deger = Number(ham);
    if (Number.isFinite(deger)) {
      if (deger > 0 && deger <= 1) deger *= 100;
      return Math.max(0, Math.min(100, Math.round(deger)));
    }
    if (toplam > 0 && cozulen > 0) return Math.min(99, Math.round((cozulen / toplam) * 100));
    return { yukleniyor: 8, kesiliyor: 32, cozuluyor: 62, tamamlandi: 100 }[asama] || 0;
  }

  function sayaciYaz(secici, deger) {
    var hedef = kok.querySelector(secici);
    if (hedef) hedef.textContent = String(deger);
  }

  function referansDuyurusu() {
    if (!sonReferansOzeti.anahtarli) return "";
    return " Anahtar kontrolü: " + sonReferansOzeti.karsilastirilan + " / " +
      sonReferansOzeti.anahtarli + "; " + sonReferansOzeti.dogru +
      " eşleşti, " + sonReferansOzeti.yanlis + " uyuşmadı.";
  }

  function yanitiUygula(hamVeri) {
    var veri = icVeri(hamVeri);
    var sorular = sorulariAl(veri);
    var hamDurum = sadeDurum(ilk(veri.durum, veri.status, veri.state));
    var asama = asamaAdi(ilk(veri.asama, veri.stage, hamDurum));
    var terminal = terminalMi(hamDurum) ? hamDurum : "";
    if (bayrak(veri.tamamlandi) && !terminal) terminal = "tamamlandi";

    var toplam = sayi(ilk(veri.toplam, veri.toplam_soru, veri.total), sorular.length);
    var kesilen = sayi(ilk(veri.kesilen, veri.kesilen_soru, veri.cropped), sorular.length);
    var cozulmus = sorular.filter(soruCozulmusMu).length;
    var cozulen = sayi(ilk(veri.cozulen, veri.cozulen_soru, veri.solved), cozulmus);
    var incelemeSayisi = sorular.filter(soruIncelenecekMi).length;
    var incele = sayi(ilk(veri.inceleme, veri.incelenecek, veri.review_count), incelemeSayisi);
    var dogru = sorular.filter(function (soru) { return soru.referansla_eslesiyor === true; }).length;
    var yanlis = sorular.filter(function (soru) { return soru.referansla_eslesiyor === false; }).length;
    var referansli = dogru + yanlis;
    var anahtarli = sorular.filter(function (soru) {
      return soru.referans_var === true || soru.referansla_eslesiyor === true || soru.referansla_eslesiyor === false;
    }).length;
    sonReferansOzeti = { karsilastirilan: referansli, anahtarli: anahtarli, dogru: dogru, yanlis: yanlis };
    var oran = ilerlemeDegeri(veri, asama, toplam, cozulen);

    islem.hidden = false;
    if (bos) bos.hidden = true;
    ilerleme.value = oran;
    ilerleme.textContent = "%" + oran;
    yuzde.textContent = "%" + oran;
    ilerlemeAciklama.textContent = metin(ilk(veri.ilerleme_aciklama, veri.progress_text), asama === "cozuluyor" && toplam ? cozulen + " / " + toplam + " soru çözüldü" : "İşleniyor");
    sayaciYaz("[data-kvc-toplam]", toplam);
    sayaciYaz("[data-kvc-kesilen]", kesilen);
    sayaciYaz("[data-kvc-cozulen]", cozulen);
    sayaciYaz("[data-kvc-inceleme]", incele);
    sayaciYaz("[data-kvc-karsilastirilan]", referansli);
    sayaciYaz("[data-kvc-anahtarli]", anahtarli);
    sayaciYaz("[data-kvc-dogru]", dogru);
    sayaciYaz("[data-kvc-yanlis]", yanlis);
    kok.querySelectorAll("[data-kvc-referans-sayaci]").forEach(function (oge) {
      oge.hidden = anahtarli === 0;
    });
    sorulariCiz(sorular);
    asamalariGuncelle(asama, terminal);

    var varsayilanBaslik = {
      yukleniyor: "Dosya hazırlanıyor",
      kesiliyor: "Sorular bulunup kesiliyor",
      cozuluyor: "Sorular sırayla çözülüyor",
      tamamlandi: "Kesme ve çözme tamamlandı"
    }[asama];
    var yeniBaslik = metin(ilk(veri.baslik, veri.title), varsayilanBaslik);
    var yeniMesaj = metin(ilk(veri.mesaj, veri.message, veri.aciklama), "İşlem cihazında sürüyor.");
    durumYazi.textContent = yeniBaslik;
    mesaj.textContent = yeniMesaj;
    if (hamDurum !== sonDurum) {
      duyur(yeniBaslik + ". " + yeniMesaj);
      sonDurum = hamDurum;
    }
    return { durum: hamDurum, terminal: terminal, veri: veri };
  }

  function hataMesaji(veri, varsayilan) {
    if (!veri || typeof veri !== "object") return varsayilan;
    var ayrinti = ilk(veri.mesaj, veri.message, veri.hata, veri.error, veri.detail);
    if (Array.isArray(ayrinti)) return ayrinti.map(function (x) { return x.msg || String(x); }).join(" ");
    return metin(ayrinti, varsayilan);
  }

  function jsonOku(yanit) {
    return yanit.text().then(function (govde) {
      var veri = {};
      try { veri = govde ? JSON.parse(govde) : {}; } catch (e) {}
      if (!yanit.ok) throw new Error(hataMesaji(veri, "Sunucu yanıt vermedi (" + yanit.status + ")."));
      return veri;
    });
  }

  function bitir(tur, veri) {
    if (zamanlayici) window.clearTimeout(zamanlayici);
    zamanlayici = null;
    formuEtkinlestir(false);
    kok.dataset.durum = tur;
    var tamamlayici = tur === "tamam" || tur === "kismi";
    asamalariGuncelle(tamamlayici ? "tamamlandi" : asamaAdi(tur), tamamlayici ? "tamamlandi" : tur);
    if (tur === "tamam") {
      ilerleme.value = 100;
      ilerleme.textContent = "%100";
      yuzde.textContent = "%100";
      durumYazi.textContent = sonReferansOzeti.yanlis > 0 ?
        "İşlem tamamlandı; doğrulanması gereken cevaplar var" :
        "Kesme ve çözme tamamlandı";
      mesaj.textContent = sonReferansOzeti.yanlis > 0 ?
        sonReferansOzeti.yanlis + " model önerisi cevap anahtarıyla uyuşmadı ve incelemeye ayrıldı." :
        "Sonuçlar hazır.";
      duyur(durumYazi.textContent + ". " + mesaj.textContent + referansDuyurusu());
      if (sonuclar && !sonuclar.hidden) sonuclar.scrollIntoView({ behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth", block: "start" });
    } else if (tur === "kismi") {
      ilerleme.value = 100;
      ilerleme.textContent = "%100";
      yuzde.textContent = "%100";
      durumYazi.textContent = "İşlem tamamlandı; bazı sorularda hata var";
      mesaj.textContent = "Hazır olan çözümler korundu. Çözülemeyen veya belirsiz soruları sonuçlarda görebilirsin.";
      if (isHatasi) isHatasi.classList.add("kvc-kismi-uyari");
      hataGoster(isHatasi, "Bazı sorular tamamlanamadı; diğer sonuçlar kullanıma hazır.");
      duyur("Kes ve çöz işlemi kısmen tamamlandı. Bazı sorularda hata var." + referansDuyurusu());
      if (sonuclar && !sonuclar.hidden) sonuclar.scrollIntoView({ behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth", block: "start" });
    } else if (tur === "durduruldu") {
      durumYazi.textContent = "İşlem durduruldu";
      mesaj.textContent = "Hazır olan sonuçlar ekranda bırakıldı.";
      duyur("Kes ve çöz işlemi durduruldu." + referansDuyurusu());
    } else {
      var hata = hataMesaji(veri, "İşlem tamamlanamadı. Dosyayı denetleyip yeniden deneyebilirsin.");
      durumYazi.textContent = "İşlem tamamlanamadı";
      hataGoster(isHatasi, hata);
      duyur("İşlem tamamlanamadı. " + hata);
    }
  }

  function sonrakiSorguyuKur(gecikme) {
    if (!etkin || !isKimligi) return;
    zamanlayici = window.setTimeout(durumuSorgula, gecikme || 1200);
  }

  function durumuSorgula() {
    if (!etkin || !isKimligi) return;
    fetch("/kes-ve-coz/api/is/" + encodeURIComponent(isKimligi), {
      headers: { "Accept": "application/json" },
      cache: "no-store"
    }).then(jsonOku).then(function (veri) {
      ardisikAgHatasi = 0;
      hataTemizle(isHatasi);
      var sonuc = yanitiUygula(veri);
      if (TERMINAL_TAMAM.indexOf(sonuc.terminal) >= 0) bitir("tamam", sonuc.veri);
      else if (TERMINAL_KISMI.indexOf(sonuc.terminal) >= 0) bitir("kismi", sonuc.veri);
      else if (TERMINAL_IPTAL.indexOf(sonuc.terminal) >= 0) bitir("durduruldu", sonuc.veri);
      else if (TERMINAL_HATA.indexOf(sonuc.terminal) >= 0) bitir("hata", sonuc.veri);
      else sonrakiSorguyuKur(1200);
    }).catch(function (hata) {
      ardisikAgHatasi += 1;
      if (ardisikAgHatasi < 4 && etkin) {
        mesaj.textContent = "Bağlantı yenileniyor; işlem arka planda sürüyor.";
        sonrakiSorguyuKur(1200 * ardisikAgHatasi);
      } else {
        bitir("hata", { mesaj: hata.message });
      }
    });
  }

  function kimligiAl(veri) {
    var ic = icVeri(veri);
    return metin(ilk(ic.id, ic.is_id, ic.job_id, ic.kimlik), "");
  }

  function isiBaslat() {
    var secilen = dosya.files && dosya.files[0];
    var hata = dosyayiDogrula(secilen);
    hataTemizle(formHatasi);
    hataTemizle(isHatasi);
    if (hata) {
      hataGoster(formHatasi, hata);
      duyur(hata);
      dosya.focus();
      return;
    }

    // Form alanlari devre disi birakildiginda FormData'ya dahil edilmez.
    // Dosyayi arayuz kilitlenmeden once yakala; aksi halde sunucu 422 doner.
    var formVerisi = new FormData(form);

    if (istekDenetleyici) istekDenetleyici.abort();
    istekDenetleyici = new AbortController();
    isKimligi = "";
    sonDurum = "";
    sonSorularImzasi = "";
    soruListesi.textContent = "";
    sonuclar.hidden = true;
    islem.hidden = false;
    bos.hidden = true;
    kok.dataset.durum = "calisiyor";
    formuEtkinlestir(true);
    yanitiUygula({ durum: "yukleniyor", asama: "yukleniyor", mesaj: "Dosya güvenli çalışma alanına alınıyor." });
    islem.scrollIntoView({ behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth", block: "start" });

    fetch(form.action, {
      method: "POST",
      body: formVerisi,
      headers: { "Accept": "application/json" },
      signal: istekDenetleyici.signal
    }).then(jsonOku).then(function (veri) {
      var sonuc = yanitiUygula(veri);
      isKimligi = kimligiAl(veri);
      if (durdur && isKimligi) durdur.disabled = false;
      if (TERMINAL_TAMAM.indexOf(sonuc.terminal) >= 0) bitir("tamam", sonuc.veri);
      else if (TERMINAL_KISMI.indexOf(sonuc.terminal) >= 0) bitir("kismi", sonuc.veri);
      else if (TERMINAL_HATA.indexOf(sonuc.terminal) >= 0) bitir("hata", sonuc.veri);
      else if (!isKimligi) bitir("hata", { mesaj: "İşlem kimliği alınamadı." });
      else sonrakiSorguyuKur(450);
    }).catch(function (hataNesnesi) {
      if (hataNesnesi.name === "AbortError") return;
      bitir("hata", { mesaj: hataNesnesi.message });
    });
  }

  form.addEventListener("submit", function (olay) {
    if (!window.fetch || !window.FormData || !window.AbortController) return;
    olay.preventDefault();
    if (!etkin) isiBaslat();
  });

  dosya.addEventListener("change", secimDegisti);
  if (temizle) temizle.addEventListener("click", function () {
    if (etkin) return;
    dosya.value = "";
    secimiGoster(null);
    hataTemizle(formHatasi);
    dosya.click();
  });

  ["dragenter", "dragover"].forEach(function (olayAdi) {
    birakma.addEventListener(olayAdi, function () { birakma.classList.add("surukleniyor"); });
  });
  ["dragleave", "drop"].forEach(function (olayAdi) {
    birakma.addEventListener(olayAdi, function () { birakma.classList.remove("surukleniyor"); });
  });

  if (durdur) durdur.addEventListener("click", function () {
    if (!etkin || !isKimligi) return;
    if (zamanlayici) window.clearTimeout(zamanlayici);
    zamanlayici = null;
    durdur.disabled = true;
    mesaj.textContent = "İşlem güvenli biçimde durduruluyor…";
    fetch("/kes-ve-coz/api/is/" + encodeURIComponent(isKimligi) + "/durdur", {
      method: "POST",
      headers: { "Accept": "application/json" }
    }).then(jsonOku).then(function (veri) {
      var sonuc = yanitiUygula(veri);
      if (TERMINAL_IPTAL.indexOf(sonuc.terminal) >= 0) bitir("durduruldu", sonuc.veri);
      else if (TERMINAL_TAMAM.indexOf(sonuc.terminal) >= 0) bitir("tamam", sonuc.veri);
      else if (TERMINAL_KISMI.indexOf(sonuc.terminal) >= 0) bitir("kismi", sonuc.veri);
      else if (TERMINAL_HATA.indexOf(sonuc.terminal) >= 0) bitir("hata", sonuc.veri);
      else {
        mesaj.textContent = "Durdurma isteği alındı; çalışan soru güvenli noktada bırakılıyor…";
        duyur("Durdurma isteği alındı. İşlemin durması bekleniyor.");
        sonrakiSorguyuKur(400);
      }
    }).catch(function (hata) {
      durdur.disabled = false;
      hataGoster(isHatasi, "İşlem durdurulamadı: " + hata.message);
      sonrakiSorguyuKur(1200);
    });
  });

  filtreDugmeleri.forEach(function (dugme) {
    dugme.addEventListener("click", function () {
      etkinFiltre = dugme.getAttribute("data-kvc-filtre") || "tumu";
      filtreDugmeleri.forEach(function (d) {
        var secili = d === dugme;
        d.classList.toggle("etkin", secili);
        d.setAttribute("aria-pressed", secili ? "true" : "false");
      });
      filtreyiUygula();
    });
  });

  document.addEventListener("keydown", function (olay) {
    if (olay.key === "Escape" && etkin && durdur && !durdur.disabled) {
      olay.preventDefault();
      durdur.click();
    }
  });

  if (isKimligi && window.fetch) {
    islem.hidden = false;
    bos.hidden = true;
    formuEtkinlestir(true);
    durumuSorgula();
  }
})();
