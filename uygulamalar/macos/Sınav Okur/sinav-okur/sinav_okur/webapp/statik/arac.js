// sinav-okur ortak arayüz araçları. Sayfalar davranışı data-öznitelikleriyle
// veya bilinen kimliklerle (onceki/sonraki-baglanti) açar; sayfaya özgü
// scriptler (sürükleme, modal, kümeli tezgâh gezintisi) şablonlarında kalır.
(() => {
  "use strict";

  const yaziyorMu = () => {
    const e = document.activeElement;
    return Boolean(
      e && (e.tagName === "TEXTAREA" || e.tagName === "INPUT" || e.tagName === "SELECT")
    );
  };
  // Tezgâh gibi kendi kısayolunu kuran sayfalar aynı semantiği kullanır.
  window.sinavOkur = Object.assign(window.sinavOkur || {}, { yaziyorMu });

  // --- Tablo arama + durum filtresi ------------------------------------
  // <input data-tablo-ara="#tablo"> serbest arama (satırlardaki data-ara),
  // <button data-filtre="deger" data-filtre-hedef="#tablo"> durum filtresi
  // (satırlardaki data-durum; "tumu" hepsini gösterir).
  const filtreDurumu = new Map();

  const tabloyuUygula = (tablo) => {
    const girdi = document.querySelector(`input[data-tablo-ara="#${tablo.id}"]`);
    const aranan = (girdi?.value || "").toLocaleLowerCase("tr-TR").trim();
    const etkin = filtreDurumu.get(tablo) || "tumu";
    tablo.querySelectorAll("tbody tr").forEach((satir) => {
      const aramaUyar =
        !aranan ||
        (satir.dataset.ara || "").toLocaleLowerCase("tr-TR").includes(aranan);
      const durumUyar = etkin === "tumu" || satir.dataset.durum === etkin;
      satir.hidden = !(aramaUyar && durumUyar);
    });
  };

  document.querySelectorAll("input[data-tablo-ara]").forEach((girdi) => {
    const tablo = document.querySelector(girdi.dataset.tabloAra);
    if (tablo) girdi.addEventListener("input", () => tabloyuUygula(tablo));
  });
  document.querySelectorAll("button[data-filtre][data-filtre-hedef]").forEach((dugme) => {
    dugme.addEventListener("click", () => {
      const tablo = document.querySelector(dugme.dataset.filtreHedef);
      if (!tablo) return;
      filtreDurumu.set(tablo, dugme.dataset.filtre);
      document
        .querySelectorAll(`button[data-filtre][data-filtre-hedef="${dugme.dataset.filtreHedef}"]`)
        .forEach((d) => d.setAttribute("aria-pressed", String(d === dugme)));
      tabloyuUygula(tablo);
    });
  });

  // --- Sütun sıralama ---------------------------------------------------
  // <th data-sirala> metin, <th data-sirala="sayi"> sayısal sıralar; hücrede
  // data-deger varsa o kullanılır (görünen metin yerine ham değer).
  const hucreDegeri = (satir, sutun, sayisal) => {
    const hucre = satir.children[sutun];
    if (!hucre) return sayisal ? Number.NEGATIVE_INFINITY : "";
    const ham = hucre.dataset.deger ?? hucre.textContent.trim();
    if (!sayisal) return ham.toLocaleLowerCase("tr-TR");
    const sayi = parseFloat(String(ham).replace("%", "").replace(",", "."));
    return Number.isNaN(sayi) ? Number.NEGATIVE_INFINITY : sayi;
  };

  document.querySelectorAll("th[data-sirala]").forEach((baslik) => {
    const tablo = baslik.closest("table");
    const govde = tablo?.querySelector("tbody");
    if (!govde) return;
    baslik.style.cursor = "pointer";
    baslik.setAttribute("aria-sort", "none");
    baslik.title = "Sıralamak için tıklayın";
    baslik.addEventListener("click", () => {
      const sutun = [...baslik.parentElement.children].indexOf(baslik);
      const sayisal = baslik.dataset.sirala === "sayi";
      const artan = baslik.getAttribute("aria-sort") !== "ascending";
      tablo.querySelectorAll("th[data-sirala]").forEach((b) => {
        if (b !== baslik) b.setAttribute("aria-sort", "none");
      });
      baslik.setAttribute("aria-sort", artan ? "ascending" : "descending");
      [...govde.querySelectorAll("tr")]
        .sort((a, b) => {
          const da = hucreDegeri(a, sutun, sayisal);
          const db = hucreDegeri(b, sutun, sayisal);
          const fark = sayisal ? da - db : da.localeCompare(db, "tr-TR");
          return artan ? fark : -fark;
        })
        .forEach((satir) => govde.appendChild(satir));
    });
  });

  // --- Klavye gezinme ---------------------------------------------------
  // Sayfada #onceki-baglanti / #sonraki-baglanti varsa ←/→ ve J/K gezinir;
  // #onayla-form varsa A onaylar; #metin-alani varsa D odaklanır.
  const sonraki = document.getElementById("sonraki-baglanti");
  const onceki = document.getElementById("onceki-baglanti");
  const onaylaForm = document.getElementById("onayla-form");
  const metinAlani = document.getElementById("metin-alani");
  if (sonraki || onceki || onaylaForm || metinAlani) {
    document.addEventListener("keydown", (olay) => {
      // Cmd+← (tarayıcı geri) gibi kombinasyonlar kısayol sayılmaz.
      if (olay.metaKey || olay.ctrlKey || olay.altKey) return;
      if (yaziyorMu()) {
        if (olay.key === "Escape") document.activeElement.blur();
        return;
      }
      const tus = olay.key.toLocaleLowerCase("tr-TR");
      if (tus === "a" && onaylaForm) { olay.preventDefault(); onaylaForm.requestSubmit(); }
      else if (tus === "d" && metinAlani) { olay.preventDefault(); metinAlani.focus(); }
      else if ((olay.key === "ArrowRight" || tus === "k") && sonraki) { olay.preventDefault(); sonraki.click(); }
      else if ((olay.key === "ArrowLeft" || tus === "j") && onceki) { olay.preventDefault(); onceki.click(); }
    });
  }

  // --- Uzun işlem formu kilidi -----------------------------------------
  // form[data-yukleniyor]: gönderimde butonlar (dıştaki form= düğmeleri
  // dahil) kilitlenir, çift gönderim engellenir. Kilit bir sonraki döngüye
  // ertelenir ki tarayıcı form verisini (buton name/value) önce toplasın.
  document.addEventListener("submit", (olay) => {
    const form = olay.target;
    if (!(form instanceof HTMLFormElement) || form.dataset.yukleniyor === undefined) return;
    // onsubmit confirm()'ü iptal ettiyse gönderim olmadı; form kilitlenmemeli.
    if (olay.defaultPrevented) return;
    if (form.dataset.gonderildi) { olay.preventDefault(); return; }
    form.dataset.gonderildi = "1";
    form.querySelector(".yukleniyor")?.classList.add("gorunur");
    const gonderen = olay.submitter;
    setTimeout(() => {
      const butonlar = [
        ...form.querySelectorAll('button[type="submit"], button:not([type])'),
        ...(form.id ? document.querySelectorAll(`button[form="${form.id}"]`) : []),
      ];
      butonlar.forEach((buton) => { buton.disabled = true; });
      if (!form.querySelector(".yukleniyor") && gonderen) {
        gonderen.dataset.ozgunMetin = gonderen.textContent;
        gonderen.textContent = "⏳ " + (form.dataset.yukleniyor || "İşleniyor…");
      }
    }, 0);
  });

  // Geri/bfcache dönüşünde kilit kalıcı olmasın: sayfa önbellekten gelirse
  // form yeniden kullanılabilir hâle getirilir (özellikle Safari).
  window.addEventListener("pageshow", (olay) => {
    if (!olay.persisted) return;
    document.querySelectorAll("form[data-yukleniyor][data-gonderildi]").forEach((form) => {
      delete form.dataset.gonderildi;
      form.querySelector(".yukleniyor")?.classList.remove("gorunur");
      const butonlar = [
        ...form.querySelectorAll('button[type="submit"], button:not([type])'),
        ...(form.id ? document.querySelectorAll(`button[form="${form.id}"]`) : []),
      ];
      butonlar.forEach((buton) => {
        buton.disabled = false;
        if (buton.dataset.ozgunMetin) {
          buton.textContent = buton.dataset.ozgunMetin;
          delete buton.dataset.ozgunMetin;
        }
      });
    });
  });
})();
