// YouTube alım işinin ilerlemesini yoklar. Sunucu tarafı uzun sürebilen
// indirme/döküm işini arka planda yürütüyor; sayfa yalnız durumu okur.
(function () {
  const kutu = document.getElementById("is-durumu");
  if (!kutu) return;
  const isId = kutu.dataset.isId;
  const mesaj = document.getElementById("is-mesaj");
  const alanlar = {
    biten: document.getElementById("is-biten"),
    toplam: document.getElementById("is-toplam"),
    aday: document.getElementById("is-aday"),
    hata: document.getElementById("is-hata"),
  };
  const durdurDugmesi = document.getElementById("is-durdur");
  const bitenDurumlar = ["bitti", "hata", "durduruldu"];

  async function yokla() {
    try {
      const yanit = await fetch(`/youtube/api/is/${isId}`);
      if (!yanit.ok) return;
      const veri = await yanit.json();
      mesaj.textContent = veri.hata || veri.mesaj || veri.durum;
      alanlar.biten.textContent = veri.biten_video;
      alanlar.toplam.textContent = veri.toplam_video;
      alanlar.aday.textContent = veri.aday_sayisi;
      alanlar.hata.textContent = veri.hata_sayisi;
      if (bitenDurumlar.includes(veri.durum)) {
        durdurDugmesi.disabled = true;
        return;
      }
    } catch (hata) {
      // Ağ kesintisi yoklamayı durdurmasın; sonraki turda yeniden denenir.
    }
    setTimeout(yokla, 1200);
  }

  durdurDugmesi.addEventListener("click", async () => {
    durdurDugmesi.disabled = true;
    await fetch(`/youtube/api/is/${isId}/durdur`, { method: "POST" });
  });

  yokla();
})();
