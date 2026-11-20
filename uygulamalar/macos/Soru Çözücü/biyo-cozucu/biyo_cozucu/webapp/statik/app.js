/* biyo-cozucu arayüz betiği — bağımlılıksız, derleme adımı yok.
 *
 * Her parça ilerlemeli (progressive) çalışır: JavaScript yüklenmezse formlar
 * klasik POST ile gönderilir ve sayfa yine tam işlevlidir. Akış yalnız bir
 * hızlandırma katmanıdır, tek yol değil. */

(function () {
  "use strict";

  // --- tema anahtarı ---------------------------------------------------

  var TEMA_SIRASI = ["sistem", "acik", "koyu"];
  var TEMA_ADI = { sistem: "tema: sistem", acik: "tema: açık", koyu: "tema: koyu" };
  var TEMA_KISA = { sistem: "Sistem", acik: "Açık", koyu: "Koyu" };

  function temayiOku() {
    try { return localStorage.getItem("biyo-tema") || "sistem"; } catch (e) { return "sistem"; }
  }

  function temayiUygula(tema) {
    if (tema === "sistem") delete document.documentElement.dataset.tema;
    else document.documentElement.dataset.tema = tema;
    try { localStorage.setItem("biyo-tema", tema); } catch (e) {}
    document.querySelectorAll("[data-tema-anahtari]").forEach(function (d) {
      var yazi = d.querySelector("[data-tema-yazi]");
      if (yazi) yazi.textContent = TEMA_KISA[tema];
      else d.textContent = TEMA_ADI[tema];
      d.setAttribute("aria-label", TEMA_ADI[tema] + " — değiştirmek için tıklayın");
      d.setAttribute("title", TEMA_ADI[tema] + " — değiştirmek için tıklayın");
    });
  }

  function temayiKur() {
    var dugmeler = document.querySelectorAll("[data-tema-anahtari]");
    if (!dugmeler.length) return;
    temayiUygula(temayiOku());
    dugmeler.forEach(function (d) {
      d.addEventListener("click", function () {
        var sonraki = TEMA_SIRASI[(TEMA_SIRASI.indexOf(temayiOku()) + 1) % TEMA_SIRASI.length];
        temayiUygula(sonraki);
      });
    });
  }

  // --- yıkıcı işlemlerde onay ------------------------------------------

  function onaylariKur() {
    document.addEventListener("submit", function (olay) {
      var form = olay.target;
      var soru = form.getAttribute("data-onay");
      if (soru && !window.confirm(soru)) olay.preventDefault();
    });
    document.addEventListener("click", function (olay) {
      var oge = olay.target.closest("[data-onay]");
      if (!oge || oge.tagName === "FORM" || oge.closest("form[data-onay]")) return;
      if (!window.confirm(oge.getAttribute("data-onay"))) olay.preventDefault();
    });
  }

  // --- klavye kısayolları -----------------------------------------------

  function yazmaAlanindaMi(oge) {
    if (!oge) return false;
    var ad = oge.tagName;
    return ad === "INPUT" || ad === "TEXTAREA" || ad === "SELECT" || oge.isContentEditable;
  }

  function kisayollariKur() {
    var yardim = document.getElementById("kisayol-yardim");
    if (yardim) {
      yardim.querySelectorAll("[data-kapat]").forEach(function (d) {
        d.addEventListener("click", function () { yardim.close(); });
      });
      // Görünür düğme: "?" tuşu yazma alanındayken bilinçli olarak
      // yok sayıldığından (soru metnine "?" yazmak gerekir) yardımın
      // klavyeden bağımsız bir yolu olmalı.
      document.querySelectorAll("[data-yardim-ac]").forEach(function (d) {
        d.addEventListener("click", function () {
          if (yardim.open) yardim.close(); else yardim.showModal();
        });
      });
    }
    document.addEventListener("keydown", function (olay) {
      // ⌘/Ctrl+Enter yazma alanının içinden de çalışmalı: asıl kullanım orası.
      if ((olay.metaKey || olay.ctrlKey) && olay.key === "Enter") {
        var form = document.querySelector("[data-akis-formu]") ||
                   (document.activeElement && document.activeElement.form);
        if (form) { olay.preventDefault(); form.requestSubmit(); }
        return;
      }
      if (yazmaAlanindaMi(document.activeElement)) return;
      if (olay.key === "/") {
        var arama = document.querySelector("input[type=search], input[name=ara]");
        if (arama) { olay.preventDefault(); arama.focus(); arama.select(); }
      } else if (olay.key === "?" && yardim) {
        olay.preventDefault();
        if (yardim.open) yardim.close(); else yardim.showModal();
      }
    });
  }

  // --- mobil gezinme ve hazır soru örnekleri ---------------------------

  function mobilGezinmeyiKur() {
    var menu = document.querySelector(".mobil-gezinme");
    if (!menu) return;
    menu.querySelectorAll("a").forEach(function (baglanti) {
      baglanti.addEventListener("click", function () { menu.open = false; });
    });
    document.addEventListener("click", function (olay) {
      if (menu.open && !menu.contains(olay.target)) menu.open = false;
    });
    document.addEventListener("keydown", function (olay) {
      if (olay.key === "Escape" && menu.open) menu.open = false;
    });
  }

  function ornekleriKur() {
    var soru = document.getElementById("soru");
    var secenekler = document.getElementById("secenekler");
    if (!soru) return;
    document.querySelectorAll("[data-ornek-soru]").forEach(function (dugme) {
      dugme.addEventListener("click", function () {
        soru.value = dugme.getAttribute("data-ornek-soru") || "";
        if (secenekler) {
          secenekler.value = dugme.getAttribute("data-ornek-secenekler") || "";
          if (secenekler.value) {
            var ayrintilar = secenekler.closest("details");
            if (ayrintilar) ayrintilar.open = true;
          }
        }
        var hata = document.getElementById("coz-form-hatasi");
        if (hata) hata.hidden = true;
        var durum = document.getElementById("coz-durum-bildirimi");
        if (durum && durum.textContent === "Soru veya dosya gerekli.") durum.textContent = "";
        soru.focus();
        soru.setSelectionRange(soru.value.length, soru.value.length);
      });
    });
  }

  // --- canlı akış --------------------------------------------------------

  /* Sunucudan gelen SSE çerçevelerini ayrıştırır. EventSource yerine fetch
   * kullanıyoruz: soru metni uzun olabiliyor ve EventSource yalnız GET
   * desteklediğinden URL sınırına takılırdı. */
  function sseAyristir(tampon, isle) {
    var parcalar = tampon.split("\n\n");
    var kalan = parcalar.pop();
    parcalar.forEach(function (cerceve) {
      var ad = "mesaj", veri = [];
      cerceve.split("\n").forEach(function (satir) {
        if (satir.indexOf("event:") === 0) ad = satir.slice(6).trim();
        else if (satir.indexOf("data:") === 0) veri.push(satir.slice(5).replace(/^ /, ""));
      });
      if (veri.length) {
        try { isle(ad, JSON.parse(veri.join("\n"))); } catch (e) {}
      }
    });
    return kalan;
  }

  function sureBicimle(ms) {
    var sn = Math.floor(ms / 1000);
    return sn < 60 ? sn + " sn" : Math.floor(sn / 60) + " dk " + (sn % 60) + " sn";
  }

  function akisiKur() {
    var form = document.querySelector("[data-akis-formu]");
    if (!form || !window.fetch || !window.ReadableStream) return;  // klasik POST'a bırak

    var kutu = document.getElementById("akis-alani");
    var metin = document.getElementById("akis-metni");
    var durumYazi = document.getElementById("akis-durum-yazi");
    var sureYazi = document.getElementById("akis-sure");
    var sonuc = document.getElementById("cozum-alani");
    var dosyaSonuclari = document.getElementById("dosya-cozumleri");
    var dosyaGirdisi = document.getElementById("soru-dosyalari");
    var iptalDugmesi = document.getElementById("akis-iptal");
    var formHatasi = document.getElementById("coz-form-hatasi");
    var durumBildirimi = document.getElementById("coz-durum-bildirimi");
    var kuyrukOzeti = document.getElementById("kuyruk-ozeti");
    var dugme = form.querySelector("button[type=submit]");
    if (!kutu || !metin || !sonuc) return;

    var iptal = null;
    var etkinIstek = 0;
    var sureSayaci = null;

    function etkinMi(istek) { return istek === etkinIstek; }

    function dugmeYazisi(yazi) {
      if (!dugme) return;
      var hedef = dugme.querySelector("[data-dugme-yazi]");
      if (hedef) hedef.textContent = yazi;
      else dugme.textContent = yazi;
    }

    function durumBildir(mesaj) {
      if (durumBildirimi) durumBildirimi.textContent = mesaj;
    }

    function gerekliUyarisiniTemizle() {
      if (formHatasi && !formHatasi.hidden) formHatasi.hidden = true;
      if (durumBildirimi && durumBildirimi.textContent === "Soru veya dosya gerekli.") {
        durumBildirimi.textContent = "";
      }
    }

    function kuyrukOzetiniGuncelle() {
      if (!kuyrukOzeti || !dosyaSonuclari) return;
      var toplam = dosyaSonuclari.querySelectorAll(".kuyruk-karti").length;
      if (!toplam) { kuyrukOzeti.hidden = true; return; }
      var tamam = dosyaSonuclari.querySelectorAll(".kuyruk-karti.tamam").length;
      var hata = dosyaSonuclari.querySelectorAll(".kuyruk-karti.hatali").length;
      var atlanan = dosyaSonuclari.querySelectorAll(".kuyruk-karti.atlanmis").length;
      var suruyor = Math.max(0, toplam - tamam - hata - atlanan);
      var parcalar = [tamam + " tamamlandı"];
      if (hata) parcalar.push(hata + " hata");
      if (atlanan) parcalar.push(atlanan + " durduruldu/atlanmış");
      if (suruyor) parcalar.push(suruyor + " sırada");
      kuyrukOzeti.textContent = toplam + " soru · " + parcalar.join(" · ");
      kuyrukOzeti.hidden = false;
    }

    function sonucaGit() {
      try { sonuc.focus({ preventScroll: true }); } catch (e) { sonuc.focus(); }
      if (window.matchMedia && window.matchMedia("(max-width: 70rem)").matches) {
        var azalt = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
        sonuc.scrollIntoView({ behavior: azalt ? "auto" : "smooth", block: "start" });
      }
    }

    function bitir(istek) {
      if (!etkinMi(istek)) return;
      if (sureSayaci) clearInterval(sureSayaci);
      sureSayaci = null;
      if (dugme) dugme.disabled = false;
      dugmeYazisi("Çözümü başlat");
      sonuc.setAttribute("aria-busy", "false");
      kutu.setAttribute("aria-busy", "false");
      iptal = null;
    }

    function hataGoster(hedef, mesaj) {
      hedef.innerHTML = '<div class="hata-kutu" role="alert"></div>';
      hedef.firstChild.textContent = mesaj;
    }

    function akisGonder(formVerisi, denetleyici, istek, olayIsle) {
      return fetch("/coz/akis", {
        method: "POST",
        body: formVerisi,
        signal: denetleyici.signal,
        headers: { "Accept": "text/event-stream" }
      }).then(function (yanit) {
        if (!yanit.ok || !yanit.body) {
          throw new Error("Sunucu yanıtı alınamadı (" + yanit.status + ")");
        }
        var okuyucu = yanit.body.getReader();
        var kodlayici = new TextDecoder();
        var tampon = "";
        var sonOlay = null;

        function oku() {
          return okuyucu.read().then(function (parca) {
            if (!etkinMi(istek)) { okuyucu.cancel(); return sonOlay; }
            if (parca.done) {
              if (!sonOlay) throw new Error("Çözüm akışı tamamlanmadan kesildi.");
              return sonOlay;
            }
            tampon += kodlayici.decode(parca.value, { stream: true });
            tampon = sseAyristir(tampon, function (ad, veri) {
              if (!etkinMi(istek)) return;
              olayIsle(ad, veri);
              if (ad === "bitti" || ad === "hata") sonOlay = { ad: ad, veri: veri };
            });
            if (sonOlay) { okuyucu.cancel(); return sonOlay; }
            return oku();
          });
        }
        return oku();
      });
    }

    function kuyruguCiz(sorular) {
      dosyaSonuclari.innerHTML = "";
      sorular.forEach(function (soru, sira) {
        var kart = document.createElement("section");
        kart.className = "kuyruk-karti";
        kart.dataset.sira = String(sira);
        var baslik = document.createElement("div");
        baslik.className = "kuyruk-baslik";
        var onizleme;
        if (soru.gorsel) {
          onizleme = document.createElement("img");
          onizleme.src = "/coz/gorsel/" + soru.gorsel + ".png";
          onizleme.alt = "Soru önizlemesi";
        } else {
          onizleme = document.createElement("span");
          onizleme.className = "dosya-onizleme";
          onizleme.textContent = "TXT";
        }
        var bilgi = document.createElement("div");
        var ad = document.createElement("h2");
        ad.textContent = soru.baslik;
        var ozet = document.createElement("p");
        ozet.textContent = soru.soru;
        bilgi.appendChild(ad); bilgi.appendChild(ozet);
        var durum = document.createElement("span");
        durum.className = "kuyruk-durum";
        durum.textContent = "bekliyor";
        baslik.appendChild(onizleme); baslik.appendChild(bilgi); baslik.appendChild(durum);
        var kartSonucu = document.createElement("div");
        kartSonucu.className = "kuyruk-sonuc";
        kart.appendChild(baslik); kart.appendChild(kartSonucu);
        dosyaSonuclari.appendChild(kart);
      });
      kuyrukOzetiniGuncelle();
    }

    function tekSoruyuCoz(formVerisi, denetleyici, istek) {
      return akisGonder(formVerisi, denetleyici, istek, function (ad, veri) {
        if (ad === "parca") {
          metin.textContent += veri.metin;
          metin.scrollTop = metin.scrollHeight;
        } else if (ad === "durum") {
          if (durumYazi) durumYazi.textContent = veri.mesaj;
        } else if (ad === "bitti") {
          sonuc.innerHTML = veri.html;
          durumBildir("Çözüm hazır.");
        } else if (ad === "hata") {
          hataGoster(sonuc, veri.mesaj);
          durumBildir("Çözüm tamamlanamadı: " + veri.mesaj);
        }
      }).then(function (sonOlay) {
        if (sonOlay && sonOlay.ad === "bitti") sonucaGit();
        return sonOlay;
      });
    }

    function topluCoz(sorular, denetleyici, istek) {
      kuyruguCiz(sorular);
      var sira = 0;
      var kullaniciSecenekleri = (form.querySelector("[name=secenekler]") || {}).value || "";

      function siradaki() {
        if (!etkinMi(istek) || denetleyici.signal.aborted || sira >= sorular.length) {
          return Promise.resolve();
        }
        var soru = sorular[sira];
        var kart = dosyaSonuclari.querySelector('[data-sira="' + sira + '"]');
        var durum = kart.querySelector(".kuyruk-durum");
        var kartSonucu = kart.querySelector(".kuyruk-sonuc");
        kart.classList.add("calisiyor");
        durum.textContent = "çözülüyor";
        metin.textContent = "";
        if (durumYazi) durumYazi.textContent = (sira + 1) + " / " + sorular.length + " çözülüyor";

        var veri = new FormData(form);
        veri.delete("dosyalar");
        veri.delete("gorsel");
        veri.set("soru", soru.soru);
        // PDF'den çıkarılan her soru kendi şıklarını taşır. Formdaki elle
        // yazılmış şıklar çoklu kuyrukta bütün soruları ezmemeli; yalnız tek
        // ve şıksız bir görsel/metin dosyası için yardımcı giriş sayılır.
        var secenekMetni = soru.secenekler || "";
        if (!secenekMetni && sorular.length === 1) secenekMetni = kullaniciSecenekleri;
        veri.set("secenekler", secenekMetni);
        veri.set("gorsel_imza", soru.gorsel || "");

        return akisGonder(veri, denetleyici, istek, function (ad, olayVerisi) {
          if (ad === "parca") {
            metin.textContent += olayVerisi.metin;
            metin.scrollTop = metin.scrollHeight;
          } else if (ad === "durum") {
            if (durumYazi) durumYazi.textContent = (sira + 1) + " / " + sorular.length + " · " + olayVerisi.mesaj;
          } else if (ad === "bitti") {
            kartSonucu.innerHTML = olayVerisi.html;
            kart.classList.remove("calisiyor");
            kart.classList.add("tamam");
            durum.textContent = "tamamlandı";
            kuyrukOzetiniGuncelle();
          } else if (ad === "hata") {
            hataGoster(kartSonucu, olayVerisi.mesaj);
            kart.classList.remove("calisiyor");
            kart.classList.add("hatali");
            durum.textContent = "hata";
            kuyrukOzetiniGuncelle();
          }
        }).catch(function (hata) {
          if (hata && hata.name === "AbortError") throw hata;
          hataGoster(kartSonucu, hata.message || "Çözüm üretilemedi.");
          kart.classList.remove("calisiyor");
          kart.classList.add("hatali");
          durum.textContent = "hata";
          kuyrukOzetiniGuncelle();
        }).then(function () {
          sira += 1;
          return siradaki();
        });
      }
      return siradaki().then(function () {
        kuyrukOzetiniGuncelle();
        durumBildir("Dosya kuyruğu tamamlandı.");
        sonucaGit();
      });
    }

    form.addEventListener("submit", function (olay) {
      olay.preventDefault();
      var dosyalar = dosyaGirdisi && dosyaGirdisi.files ? Array.from(dosyaGirdisi.files) : [];
      var soruAlani = form.querySelector("[name=soru]");
      var soruMetni = soruAlani ? soruAlani.value.trim() : "";
      if (!soruMetni && !dosyalar.length) {
        if (formHatasi) {
          formHatasi.textContent = "Çözmek için bir soru yaz veya en az bir dosya seç.";
          formHatasi.hidden = false;
        }
        durumBildir("Soru veya dosya gerekli.");
        if (soruAlani) soruAlani.focus();
        return;
      }
      if (formHatasi) formHatasi.hidden = true;
      if (iptal) iptal.abort();
      etkinIstek += 1;
      var istek = etkinIstek;
      var denetleyici = new AbortController();
      iptal = denetleyici;

      var baslangic = Date.now();
      metin.textContent = "";
      sonuc.innerHTML = "";
      if (dosyaSonuclari) dosyaSonuclari.innerHTML = "";
      if (kuyrukOzeti) kuyrukOzeti.hidden = true;
      kutu.hidden = false;
      kutu.setAttribute("aria-busy", "true");
      sonuc.setAttribute("aria-busy", "true");
      if (dugme) dugme.disabled = true;
      dugmeYazisi("Çözülüyor…");
      if (durumYazi) durumYazi.textContent = "Hazırlanıyor";
      durumBildir("Çözüm hazırlanıyor.");

      if (sureSayaci) clearInterval(sureSayaci);
      sureSayaci = setInterval(function () {
        if (etkinMi(istek) && sureYazi) sureYazi.textContent = sureBicimle(Date.now() - baslangic);
      }, 500);

      var islem;
      if (dosyalar.length) {
        var hazirlama = new FormData();
        dosyalar.forEach(function (dosya) { hazirlama.append("dosyalar", dosya, dosya.name); });
        hazirlama.set("soru_notu", (form.querySelector("[name=soru]") || {}).value || "");
        islem = fetch("/coz/dosya/hazirla", {
          method: "POST", body: hazirlama, signal: denetleyici.signal,
          headers: { "Accept": "application/json" }
        }).then(function (yanit) {
          return yanit.json().then(function (veri) {
            if (!yanit.ok) throw new Error(veri.hata || "Dosyalar hazırlanamadı.");
            return veri;
          });
        }).then(function (veri) {
          if (!etkinMi(istek)) return;
          if (!veri.sorular || !veri.sorular.length) throw new Error("Dosyalardan soru çıkarılamadı.");
          return topluCoz(veri.sorular, denetleyici, istek);
        });
      } else {
        var tekVeri = new FormData(form);
        tekVeri.delete("dosyalar");
        islem = tekSoruyuCoz(tekVeri, denetleyici, istek);
      }

      islem.then(function () {
        if (!etkinMi(istek)) return;
        kutu.hidden = true;
        kuyrukOzetiniGuncelle();
        bitir(istek);
      }).catch(function (hata) {
        if (!etkinMi(istek)) return;
        kutu.hidden = true;
        if (hata && hata.name === "AbortError") {
          if (durumYazi) durumYazi.textContent = "Durduruldu";
          durumBildir("Çözüm durduruldu.");
          if (dosyaSonuclari) {
            dosyaSonuclari.querySelectorAll(".kuyruk-karti").forEach(function (kart) {
              if (kart.classList.contains("tamam") || kart.classList.contains("hatali")) return;
              var calisiyordu = kart.classList.contains("calisiyor");
              kart.classList.remove("calisiyor");
              kart.classList.add("atlanmis");
              kart.querySelector(".kuyruk-durum").textContent = calisiyordu ? "durduruldu" : "atlanmış";
            });
            kuyrukOzetiniGuncelle();
          }
        } else {
          hataGoster(sonuc, hata.message || "Çözüm üretilemedi.");
          durumBildir("Çözüm tamamlanamadı: " + (hata.message || "Bilinmeyen hata"));
          sonucaGit();
        }
        bitir(istek);
      });
    });

    form.addEventListener("input", gerekliUyarisiniTemizle);
    form.addEventListener("change", gerekliUyarisiniTemizle);

    document.addEventListener("keydown", function (olay) {
      if (olay.key === "Escape" && iptal) iptal.abort();
    });
    if (iptalDugmesi) iptalDugmesi.addEventListener("click", function () {
      if (iptal) iptal.abort();
    });
  }

  // --- başlat ------------------------------------------------------------

  // --- çoklu soru dosyası, sürükleme ve panodan yapıştırma --------------

  function dosyalariKur() {
    var girdi = document.getElementById("soru-dosyalari");
    var birakma = document.getElementById("dosya-birakma");
    var liste = document.getElementById("dosya-listesi");
    var ozet = document.getElementById("dosya-ozeti");
    var sayi = document.getElementById("dosya-sayisi");
    var tumunuKaldir = document.getElementById("tum-dosyalari-kaldir");
    var hataKutusu = document.getElementById("dosya-hatasi");
    if (!girdi || !birakma || !liste) return;
    var dosyalar = Array.from(girdi.files || []);
    var onizlemeAdresleri = [];
    var azamiDosya = Number(girdi.getAttribute("data-azami-dosya")) || 12;
    var azamiDosyaBayt = (Number(girdi.getAttribute("data-azami-dosya-mb")) || 25) * 1024 * 1024;
    var azamiToplamBayt = (Number(girdi.getAttribute("data-azami-toplam-mb")) || 80) * 1024 * 1024;
    var desteklenen = {
      ".png": true, ".jpg": true, ".jpeg": true, ".webp": true,
      ".gif": true, ".bmp": true, ".tif": true, ".tiff": true,
      ".pdf": true, ".txt": true, ".text": true, ".md": true
    };

    function boyutBicimle(bayt) {
      return bayt < 1024 * 1024 ? Math.max(1, Math.round(bayt / 1024)) + " KB" : (bayt / 1024 / 1024).toFixed(1) + " MB";
    }
    function anahtar(dosya) { return [dosya.name, dosya.size, dosya.lastModified].join(":"); }
    function uzanti(dosya) {
      var ad = (dosya.name || "").toLowerCase();
      var nokta = ad.lastIndexOf(".");
      return nokta < 0 ? "" : ad.slice(nokta);
    }
    function hataGoster(mesaj) {
      if (!hataKutusu) return;
      hataKutusu.textContent = mesaj || "";
      hataKutusu.hidden = !mesaj;
    }
    function dosyalariDenetle(adaylar) {
      if (adaylar.length > azamiDosya) return "Tek seferde en fazla " + azamiDosya + " dosya seçebilirsin.";
      var toplam = 0;
      for (var i = 0; i < adaylar.length; i++) {
        var dosya = adaylar[i];
        if (!desteklenen[uzanti(dosya)]) return dosya.name + ": bu dosya türü desteklenmiyor.";
        if (dosya.size > azamiDosyaBayt) return dosya.name + ": dosya 25 MB sınırını aşıyor.";
        toplam += dosya.size;
      }
      if (toplam > azamiToplamBayt) return "Seçilen dosyaların toplamı 80 MB sınırını aşıyor.";
      return "";
    }
    function girdiyiYenile() {
      if (!window.DataTransfer) {
        if (!dosyalar.length) girdi.value = "";
        return false;
      }
      var aktarim = new DataTransfer();
      dosyalar.forEach(function (dosya) { aktarim.items.add(dosya); });
      girdi.files = aktarim.files;
      return true;
    }
    function ciz() {
      onizlemeAdresleri.forEach(function (adres) { URL.revokeObjectURL(adres); });
      onizlemeAdresleri = [];
      liste.innerHTML = "";
      liste.hidden = dosyalar.length === 0;
      if (ozet) ozet.hidden = dosyalar.length === 0;
      if (sayi) sayi.textContent = dosyalar.length + " dosya seçildi";
      dosyalar.forEach(function (dosya, sira) {
        var satir = document.createElement("div"); satir.className = "dosya-satiri";
        var onizleme;
        if (dosya.type.indexOf("image/") === 0) {
          onizleme = document.createElement("img");
          var adres = URL.createObjectURL(dosya); onizlemeAdresleri.push(adres);
          onizleme.src = adres; onizleme.alt = ""; onizleme.className = "dosya-onizleme";
        } else {
          onizleme = document.createElement("span"); onizleme.className = "dosya-onizleme";
          onizleme.textContent = dosya.name.split(".").pop().toUpperCase().slice(0, 4);
        }
        var bilgi = document.createElement("div"); bilgi.className = "dosya-bilgi";
        var ad = document.createElement("strong"); ad.textContent = dosya.name;
        var tur = document.createElement("span"); tur.textContent = boyutBicimle(dosya.size);
        bilgi.appendChild(ad); bilgi.appendChild(tur);
        var kaldir = document.createElement("button");
        kaldir.type = "button"; kaldir.className = "ikincil kucuk"; kaldir.textContent = "Kaldır";
        kaldir.setAttribute("aria-label", dosya.name + " dosyasını kaldır");
        kaldir.addEventListener("click", function () {
          if (!window.DataTransfer) {
            dosyalar = [];
            girdi.value = "";
            hataGoster("Bu tarayıcıda tek dosya kaldırılamadı; seçim temizlendi.");
          } else {
            dosyalar.splice(sira, 1);
            girdiyiYenile();
            hataGoster("");
          }
          ciz();
        });
        satir.appendChild(onizleme); satir.appendChild(bilgi); satir.appendChild(kaldir);
        liste.appendChild(satir);
      });
    }
    function ekle(yeniDosyalar, mevcutSecimiDegistir) {
      var adaylar = mevcutSecimiDegistir ? [] : dosyalar.slice();
      var mevcut = {};
      adaylar.forEach(function (dosya) { mevcut[anahtar(dosya)] = true; });
      Array.from(yeniDosyalar || []).forEach(function (dosya) {
        if (!mevcut[anahtar(dosya)]) { adaylar.push(dosya); mevcut[anahtar(dosya)] = true; }
      });
      var hata = dosyalariDenetle(adaylar);
      if (hata) {
        hataGoster(hata);
        if (mevcutSecimiDegistir) {
          dosyalar = [];
          girdi.value = "";
          ciz();
        } else if (window.DataTransfer) girdiyiYenile();
        return;
      }
      dosyalar = adaylar;
      if (window.DataTransfer) girdiyiYenile();
      hataGoster("");
      ciz();
    }

    girdi.addEventListener("change", function () {
      // DataTransfer varsa önceki seçimleri koruyup yenileri ekleyebiliriz;
      // yoksa yerel file input yine tam işlevli, yalnız seçim yenilenir.
      ekle(girdi.files, !window.DataTransfer);
    });
    ["dragenter", "dragover"].forEach(function (ad) {
      birakma.addEventListener(ad, function (olay) {
        olay.preventDefault(); birakma.classList.add("surukleniyor");
      });
    });
    ["dragleave", "drop"].forEach(function (ad) {
      birakma.addEventListener(ad, function (olay) {
        olay.preventDefault(); birakma.classList.remove("surukleniyor");
      });
    });
    birakma.addEventListener("drop", function (olay) {
      if (olay.dataTransfer) ekle(olay.dataTransfer.files, false);
    });

    if (tumunuKaldir) {
      tumunuKaldir.addEventListener("click", function () {
        dosyalar = [];
        girdiyiYenile();
        girdi.value = "";
        hataGoster("");
        ciz();
      });
    }

    document.addEventListener("paste", function (olay) {
      var eklenenler = [];
      var ogeler = (olay.clipboardData || {}).items || [];
      for (var i = 0; i < ogeler.length; i++) {
        if (ogeler[i].type && ogeler[i].type.indexOf("image/") === 0) {
          var dosya = ogeler[i].getAsFile();
          if (dosya) eklenenler.push(dosya);
        }
      }
      if (eklenenler.length) { ekle(eklenenler); olay.preventDefault(); }
    });
    ciz();
  }

  // --- kör değerlendirme koşusu ----------------------------------------

  function kosuyuKur() {
    var form = document.querySelector("[data-kosu-formu]");
    if (!form || !window.fetch || !window.ReadableStream) return;

    var kutu = document.getElementById("kosu-alani");
    var ilerleme = document.getElementById("kosu-ilerleme");
    var durumYazi = document.getElementById("kosu-durum-yazi");
    var sonuc = document.getElementById("kosu-sonucu");
    var dugme = form.querySelector("button[type=submit]");
    if (!kutu || !ilerleme || !sonuc) return;

    form.addEventListener("submit", function (olay) {
      olay.preventDefault();
      var dugmeYazisi = dugme ? dugme.textContent : "";
      ilerleme.textContent = "";
      sonuc.innerHTML = "";
      kutu.hidden = false;
      if (dugme) { dugme.disabled = true; dugme.textContent = "Koşuyor…"; }

      function bitir() {
        if (dugme) { dugme.disabled = false; dugme.textContent = dugmeYazisi; }
      }

      fetch("/degerlendirme/akis", {
        method: "POST",
        body: new FormData(form),
        headers: { "Accept": "text/event-stream" }
      }).then(function (yanit) {
        if (!yanit.ok || !yanit.body) throw new Error("Sunucu yanıtı alınamadı");
        var okuyucu = yanit.body.getReader();
        var kodlayici = new TextDecoder();
        var tampon = "";

        function oku() {
          return okuyucu.read().then(function (parca) {
            if (parca.done) { bitir(); return; }
            tampon += kodlayici.decode(parca.value, { stream: true });
            tampon = sseAyristir(tampon, function (ad, veri) {
              if (ad === "ilerleme") {
                if (durumYazi) {
                  durumYazi.textContent = veri.sira + " / " + veri.toplam;
                }
                var satir = document.createElement("div");
                satir.textContent = (veri.dogru ? "✓ " : "✗ ") + veri.soru;
                ilerleme.appendChild(satir);
                ilerleme.scrollTop = ilerleme.scrollHeight;
              } else if (ad === "bitti") {
                sonuc.innerHTML = veri.html;
                kutu.hidden = true;
                bitir();
              } else if (ad === "hata") {
                sonuc.innerHTML = '<div class="hata-kutu"></div>';
                sonuc.firstChild.textContent = veri.mesaj;
                kutu.hidden = true;
                bitir();
              }
            });
            return oku();
          });
        }
        return oku();
      }).catch(function () {
        // Akış kurulamadıysa klasik gönderime düş: koşu yine çalışsın.
        bitir();
        kutu.hidden = true;
        form.removeAttribute("data-kosu-formu");
        form.submit();
      });
    });
  }

  function baslat() {
    temayiKur();
    onaylariKur();
    kisayollariKur();
    mobilGezinmeyiKur();
    ornekleriKur();
    akisiKur();
    dosyalariKur();
    kosuyuKur();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", baslat);
  } else {
    baslat();
  }
})();
