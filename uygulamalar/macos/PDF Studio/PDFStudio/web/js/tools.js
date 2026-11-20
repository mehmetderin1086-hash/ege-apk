// Araç kayıt defteri — tüm PDF araçlarının tanımı.
// kind: 'simple' | 'input' | 'organizer' | 'editor' | 'metadata' | 'forms' | 'forms-extract'

export const CATEGORIES = [
  { id: 'organize', title: 'Düzenle & Organize', icon: 'pages' },
  { id: 'optimize', title: 'Optimize Et', icon: 'zap' },
  { id: 'topdf', title: "PDF'e Dönüştür", icon: 'topdf' },
  { id: 'frompdf', title: "PDF'ten Dönüştür", icon: 'frompdf' },
  { id: 'mark', title: 'Editör & İşaretle', icon: 'edit' },
  { id: 'security', title: 'Güvenlik', icon: 'shield' },
  { id: 'forms', title: 'Formlar', icon: 'form' },
];

const PAGES_FIELD = {
  key: 'pages', label: 'Sayfa aralığı', type: 'pages',
  placeholder: 'örn: 1-3, 5, 8-10', default: '',
  hint: 'Boş bırakılırsa tüm sayfalara uygulanır.',
};
const PW_FIELD = { key: 'password', label: 'PDF parolası (varsa)', type: 'password', default: '', optional: true };

export const TOOLS = [
  // ---------------- ORGANIZE ----------------
  {
    id: 'merge', cat: 'organize', title: 'PDF Birleştir', color: 'c-violet', icon: 'merge',
    desc: 'Birden çok PDF dosyasını tek belgede istediğiniz sırayla birleştirin.',
    kind: 'simple', accept: ['pdf'], multiple: true, reorder: true, minFiles: 2,
    endpoint: '/api/organize/merge',
    build: (files) => ({ file_ids: files.map(f => f.file_id) }),
  },
  {
    id: 'split', cat: 'organize', title: 'PDF Böl', color: 'c-blue', icon: 'split',
    desc: 'Bir PDF’i sayfa aralıklarına veya eşit parçalara bölün.',
    kind: 'simple', accept: ['pdf'], multiple: false,
    endpoint: '/api/organize/split',
    fields: [
      { key: 'mode', label: 'Bölme yöntemi', type: 'segment', default: 'ranges',
        options: [{ value: 'ranges', label: 'Aralıklara göre' }, { value: 'every', label: 'Her N sayfada' }] },
      { key: 'ranges_text', label: 'Aralıklar (her satır bir dosya)', type: 'textarea',
        default: '1-3\n4-6', placeholder: '1-3\n4-6\n7', showIf: (o) => o.mode === 'ranges',
        hint: 'Her satır ayrı bir PDF olur.' },
      { key: 'every', label: 'Kaç sayfada bir bölünsün?', type: 'number', default: 1, min: 1, max: 999,
        showIf: (o) => o.mode === 'every' },
      PW_FIELD,
    ],
    build: (files, o) => {
      const b = { file_id: files[0].file_id, mode: o.mode, password: o.password || null };
      if (o.mode === 'every') b.every = Number(o.every) || 1;
      else b.ranges = (o.ranges_text || '').split('\n').map(s => s.trim()).filter(Boolean);
      return b;
    },
  },
  {
    id: 'organize-pages', cat: 'organize', title: 'Sayfaları Düzenle', color: 'c-indigo', icon: 'pages',
    desc: 'Sayfaları sürükle-bırak ile yeniden sıralayın, döndürün veya silin.',
    kind: 'organizer', accept: ['pdf'], multiple: false, badge: 'Görsel',
  },
  {
    id: 'rotate', cat: 'organize', title: 'PDF Döndür', color: 'c-teal', icon: 'rotate',
    desc: 'Sayfaları 90°, 180° veya 270° döndürün.',
    kind: 'simple', accept: ['pdf'], multiple: false,
    endpoint: '/api/organize/rotate',
    fields: [
      { key: 'degrees', label: 'Döndürme açısı', type: 'segment', default: 90,
        options: [{ value: 90, label: '90° ↻' }, { value: 180, label: '180°' }, { value: 270, label: '270° ↺' }] },
      PAGES_FIELD, PW_FIELD,
    ],
    build: (files, o) => ({ file_id: files[0].file_id, degrees: Number(o.degrees), pages: o.pages || null, password: o.password || null }),
  },
  {
    id: 'delete-pages', cat: 'organize', title: 'Sayfa Sil', color: 'c-red', icon: 'trash',
    desc: 'Belirttiğiniz sayfaları PDF’ten kaldırın.',
    kind: 'simple', accept: ['pdf'], multiple: false,
    endpoint: '/api/organize/delete',
    fields: [{ ...PAGES_FIELD, label: 'Silinecek sayfalar', default: '', hint: 'örn: 2, 5-7' }, PW_FIELD],
    build: (files, o) => ({ file_id: files[0].file_id, pages: o.pages, password: o.password || null }),
    requireField: 'pages',
  },
  {
    id: 'extract-pages', cat: 'organize', title: 'Sayfa Çıkar', color: 'c-amber', icon: 'extract',
    desc: 'Seçtiğiniz sayfaları yeni bir PDF olarak çıkarın.',
    kind: 'simple', accept: ['pdf'], multiple: false,
    endpoint: '/api/organize/extract',
    fields: [{ ...PAGES_FIELD, label: 'Çıkarılacak sayfalar', hint: 'örn: 1, 3-5' }, PW_FIELD],
    build: (files, o) => ({ file_id: files[0].file_id, pages: o.pages, password: o.password || null }),
    requireField: 'pages',
  },
  {
    id: 'crop', cat: 'organize', title: 'PDF Kırp', color: 'c-pink', icon: 'crop',
    desc: 'Sayfa kenarlarından belirlediğiniz miktarda kırpın (punto).',
    kind: 'simple', accept: ['pdf'], multiple: false,
    endpoint: '/api/organize/crop',
    fields: [
      { key: 'left', label: 'Sol (pt)', type: 'number', default: 0, min: 0, half: true },
      { key: 'top', label: 'Üst (pt)', type: 'number', default: 0, min: 0, half: true },
      { key: 'right', label: 'Sağ (pt)', type: 'number', default: 0, min: 0, half: true },
      { key: 'bottom', label: 'Alt (pt)', type: 'number', default: 0, min: 0, half: true },
      PAGES_FIELD, PW_FIELD,
    ],
    build: (files, o) => ({ file_id: files[0].file_id, margins: { left: +o.left, top: +o.top, right: +o.right, bottom: +o.bottom }, pages: o.pages || null, password: o.password || null }),
  },

  {
    id: 'batch', cat: 'organize', title: 'Toplu İşlem', color: 'c-orange', icon: 'layers', badge: 'Yeni',
    desc: 'Aynı işlemi birden çok PDF’e tek seferde uygulayın; sonuçlar zip’lenir.',
    kind: 'simple', accept: ['pdf'], multiple: true, minFiles: 2,
    endpoint: '/api/batch/apply',
    fields: [
      { key: 'operation', label: 'Uygulanacak işlem', type: 'select', default: 'compress', affectsVisibility: true,
        options: [
          { value: 'compress', label: 'Sıkıştır' },
          { value: 'watermark-text', label: 'Metin filigranı ekle' },
          { value: 'page-numbers', label: 'Sayfa numarası ekle' },
          { value: 'rotate', label: 'Döndür' },
          { value: 'protect', label: 'Şifrele (AES-256)' },
        ] },
      { key: 'level', label: 'Sıkıştırma seviyesi', type: 'segment', default: 'orta',
        options: [{ value: 'dusuk', label: 'Az (kalite↑)' }, { value: 'orta', label: 'Dengeli' }, { value: 'yuksek', label: 'Yüksek (boyut↓)' }],
        showIf: (o) => o.operation === 'compress' },
      { key: 'text', label: 'Filigran metni', type: 'text', default: 'GİZLİ', showIf: (o) => o.operation === 'watermark-text' },
      { key: 'position', label: 'Numara konumu', type: 'select', default: 'alt-orta',
        options: [
          { value: 'ust-sol', label: 'Üst sol' }, { value: 'ust-orta', label: 'Üst orta' }, { value: 'ust-sag', label: 'Üst sağ' },
          { value: 'alt-sol', label: 'Alt sol' }, { value: 'alt-orta', label: 'Alt orta' }, { value: 'alt-sag', label: 'Alt sağ' },
        ], showIf: (o) => o.operation === 'page-numbers' },
      { key: 'degrees', label: 'Döndürme açısı', type: 'segment', default: 90,
        options: [{ value: 90, label: '90° ↻' }, { value: 180, label: '180°' }, { value: 270, label: '270° ↺' }],
        showIf: (o) => o.operation === 'rotate' },
      { key: 'new_password', label: 'Açılış parolası', type: 'password', default: '', showIf: (o) => o.operation === 'protect' },
      { ...PW_FIELD, label: 'Mevcut PDF parolası (varsa)' },
    ],
    build: (files, o) => {
      const params = { password: o.password || null };
      if (o.operation === 'compress') params.level = o.level;
      if (o.operation === 'watermark-text') params.text = o.text;
      if (o.operation === 'page-numbers') params.position = o.position;
      if (o.operation === 'rotate') params.degrees = Number(o.degrees);
      if (o.operation === 'protect') params.new_password = o.new_password;
      return { file_ids: files.map(f => f.file_id), operation: o.operation, params };
    },
  },
  {
    id: 'compare', cat: 'organize', title: 'PDF Karşılaştır', color: 'c-indigo', icon: 'search', badge: 'Yeni',
    desc: 'İki PDF’in metin farklarını sayfa sayfa görün; görsel farkları PNG alın.',
    kind: 'compare', accept: ['pdf'], multiple: false,
  },

  // ---------------- OPTIMIZE ----------------
  {
    id: 'compress', cat: 'optimize', title: 'PDF Sıkıştır', color: 'c-green', icon: 'compress',
    desc: 'Görselleri optimize ederek dosya boyutunu küçültün.',
    kind: 'simple', accept: ['pdf'], multiple: false,
    endpoint: '/api/optimize/compress',
    fields: [
      { key: 'level', label: 'Sıkıştırma seviyesi', type: 'segment', default: 'orta',
        options: [{ value: 'dusuk', label: 'Az (kalite↑)' }, { value: 'orta', label: 'Dengeli' }, { value: 'yuksek', label: 'Yüksek (boyut↓)' }] },
      PW_FIELD,
    ],
    build: (files, o) => ({ file_id: files[0].file_id, level: o.level, password: o.password || null }),
  },
  {
    id: 'repair', cat: 'optimize', title: 'PDF Onar', color: 'c-slate', icon: 'repair',
    desc: 'Bozuk veya açılmayan PDF’leri yeniden yazarak onarın.',
    kind: 'simple', accept: ['pdf'], multiple: false,
    endpoint: '/api/optimize/repair',
    fields: [PW_FIELD],
    build: (files, o) => ({ file_id: files[0].file_id, password: o.password || null }),
  },
  {
    id: 'ocr', cat: 'optimize', title: 'OCR — Metin Tanıma', color: 'c-orange', icon: 'ocr', badge: 'AI',
    desc: 'Taranmış PDF’leri aranabilir metne dönüştürün (Türkçe + İngilizce).',
    kind: 'simple', accept: ['pdf'], multiple: false, slow: true,
    endpoint: '/api/optimize/ocr',
    fields: [PW_FIELD],
    build: (files, o) => ({ file_id: files[0].file_id, languages: 'tr,en', password: o.password || null }),
  },

  // ---------------- PDF'E DÖNÜŞTÜR ----------------
  {
    id: 'images-to-pdf', cat: 'topdf', title: 'Görsel → PDF', color: 'c-blue', icon: 'image',
    desc: 'JPG, PNG ve diğer görselleri tek bir PDF’de birleştirin.',
    kind: 'simple', accept: ['image'], multiple: true, reorder: true, minFiles: 1,
    endpoint: '/api/convert/images-to-pdf',
    fields: [
      { key: 'page_size', label: 'Sayfa boyutu', type: 'select', default: 'auto',
        options: [{ value: 'auto', label: 'Görsele göre (otomatik)' }, { value: 'a4', label: 'A4' }, { value: 'letter', label: 'Letter' }] },
      { key: 'margin', label: 'Kenar boşluğu (pt)', type: 'number', default: 0, min: 0, max: 100 },
    ],
    build: (files, o) => ({ file_ids: files.map(f => f.file_id), page_size: o.page_size, margin: +o.margin }),
  },
  {
    id: 'word-to-pdf', cat: 'topdf', title: 'Word → PDF', color: 'c-indigo', icon: 'word',
    desc: 'Word (.docx) belgelerini PDF’e dönüştürün.',
    kind: 'simple', accept: ['office'], multiple: false,
    endpoint: '/api/convert/word-to-pdf',
    build: (files) => ({ file_id: files[0].file_id }),
  },
  {
    id: 'html-to-pdf', cat: 'topdf', title: 'HTML → PDF', color: 'c-orange', icon: 'html',
    desc: 'HTML kodunu biçimli bir PDF’e dönüştürün.',
    kind: 'input',
    endpoint: '/api/convert/html-to-pdf',
    fields: [
      { key: 'html', label: 'HTML içeriği', type: 'textarea', big: true,
        default: '<h1>Başlık</h1>\n<p>Bu bir <b>HTML</b> örneğidir.</p>\n<ul><li>Madde 1</li><li>Madde 2</li></ul>' },
    ],
    build: (_f, o) => ({ html: o.html }),
    requireField: 'html',
  },
  {
    id: 'text-to-pdf', cat: 'topdf', title: 'Metin → PDF', color: 'c-teal', icon: 'filetext',
    desc: 'Düz metni temiz bir PDF belgesine dönüştürün.',
    kind: 'input',
    endpoint: '/api/convert/text-to-pdf',
    fields: [{ key: 'text', label: 'Metin', type: 'textarea', big: true, default: '', placeholder: 'Metninizi buraya yazın…' }],
    build: (_f, o) => ({ text: o.text }),
    requireField: 'text',
  },

  // ---------------- PDF'TEN DÖNÜŞTÜR ----------------
  {
    id: 'pdf-to-images', cat: 'frompdf', title: 'PDF → Görsel', color: 'c-pink', icon: 'image',
    desc: 'Her sayfayı yüksek çözünürlüklü JPG veya PNG olarak dışa aktarın.',
    kind: 'simple', accept: ['pdf'], multiple: false,
    endpoint: '/api/convert/pdf-to-images',
    fields: [
      { key: 'fmt', label: 'Biçim', type: 'segment', default: 'png',
        options: [{ value: 'png', label: 'PNG' }, { value: 'jpg', label: 'JPG' }] },
      { key: 'dpi', label: 'Çözünürlük (DPI)', type: 'select', default: 150,
        options: [{ value: 72, label: '72 (ekran)' }, { value: 150, label: '150 (standart)' }, { value: 300, label: '300 (baskı)' }] },
      PW_FIELD,
    ],
    build: (files, o) => ({ file_id: files[0].file_id, fmt: o.fmt, dpi: +o.dpi, password: o.password || null }),
  },
  {
    id: 'pdf-to-word', cat: 'frompdf', title: 'PDF → Word', color: 'c-blue', icon: 'word', slow: true,
    desc: 'PDF’i düzenlenebilir Word (.docx) belgesine dönüştürün.',
    kind: 'simple', accept: ['pdf'], multiple: false,
    endpoint: '/api/convert/pdf-to-word',
    fields: [PW_FIELD],
    build: (files, o) => ({ file_id: files[0].file_id, password: o.password || null }),
  },
  {
    id: 'pdf-to-excel', cat: 'frompdf', title: 'PDF → Excel', color: 'c-green', icon: 'excel',
    desc: 'PDF içindeki tabloları Excel (.xlsx) çalışma kitabına aktarın.',
    kind: 'simple', accept: ['pdf'], multiple: false,
    endpoint: '/api/convert/pdf-to-excel',
    fields: [PW_FIELD],
    build: (files, o) => ({ file_id: files[0].file_id, password: o.password || null }),
  },
  {
    id: 'pdf-to-text', cat: 'frompdf', title: 'PDF → Metin', color: 'c-slate', icon: 'filetext',
    desc: 'PDF’teki tüm metni düz metin (.txt) olarak çıkarın.',
    kind: 'simple', accept: ['pdf'], multiple: false,
    endpoint: '/api/convert/pdf-to-text',
    fields: [PW_FIELD],
    build: (files, o) => ({ file_id: files[0].file_id, password: o.password || null }),
  },

  // ---------------- EDİTÖR & İŞARETLE ----------------
  {
    id: 'editor', cat: 'mark', title: 'PDF Editörü', color: 'c-violet', icon: 'edit', badge: 'Görsel',
    desc: 'Metin, şekil, çizim, vurgu, görsel ve imza ekleyin — hepsi tek yerde.',
    kind: 'editor', accept: ['pdf'], multiple: false, editorTool: 'select',
  },
  {
    id: 'watermark', cat: 'mark', title: 'Filigran Ekle', color: 'c-teal', icon: 'watermark',
    desc: 'Metin veya görsel filigran ekleyin; opaklık, açı ve döşemeyi ayarlayın.',
    kind: 'simple', accept: ['pdf'], multiple: false,
    endpoint: '/api/edit/watermark-text',
    fields: [
      { key: 'wtype', label: 'Filigran türü', type: 'segment', default: 'text',
        options: [{ value: 'text', label: 'Metin' }, { value: 'image', label: 'Görsel' }] },
      { key: 'text', label: 'Filigran metni', type: 'text', default: 'GİZLİ', showIf: (o) => o.wtype === 'text' },
      { key: 'image_file_id', label: 'Filigran görseli', type: 'imageupload', showIf: (o) => o.wtype === 'image' },
      { key: 'color', label: 'Renk', type: 'color', default: '#888888', showIf: (o) => o.wtype === 'text' },
      { key: 'fontsize', label: 'Yazı boyutu', type: 'range', default: 48, min: 12, max: 120, unit: 'pt', showIf: (o) => o.wtype === 'text' },
      { key: 'rotation', label: 'Açı', type: 'range', default: 45, min: 0, max: 90, unit: '°' },
      { key: 'opacity', label: 'Opaklık', type: 'range', default: 25, min: 5, max: 100, unit: '%' },
      { key: 'tiled', label: 'Sayfayı döşe (tekrarla)', type: 'checkbox', default: false, showIf: (o) => o.wtype === 'text' },
      PAGES_FIELD, PW_FIELD,
    ],
    dynamicEndpoint: (o) => o.wtype === 'image' ? '/api/edit/watermark-image' : '/api/edit/watermark-text',
    build: (files, o) => {
      if (o.wtype === 'image') {
        return { file_id: files[0].file_id, image_file_id: o.image_file_id, opacity: o.opacity / 100, scale: 0.5, pages: o.pages || null, password: o.password || null };
      }
      return { file_id: files[0].file_id, text: o.text, color: o.color, fontsize: +o.fontsize, rotation: +o.rotation, opacity: o.opacity / 100, tiled: !!o.tiled, pages: o.pages || null, password: o.password || null };
    },
  },
  {
    id: 'page-numbers', cat: 'mark', title: 'Sayfa Numarası', color: 'c-amber', icon: 'hash',
    desc: 'Sayfalara numara ekleyin; konum ve biçimi özelleştirin.',
    kind: 'simple', accept: ['pdf'], multiple: false,
    endpoint: '/api/edit/page-numbers',
    fields: [
      { key: 'position', label: 'Konum', type: 'select', default: 'alt-orta',
        options: [
          { value: 'ust-sol', label: 'Üst sol' }, { value: 'ust-orta', label: 'Üst orta' }, { value: 'ust-sag', label: 'Üst sağ' },
          { value: 'alt-sol', label: 'Alt sol' }, { value: 'alt-orta', label: 'Alt orta' }, { value: 'alt-sag', label: 'Alt sağ' },
        ] },
      { key: 'fmt', label: 'Biçim', type: 'select', default: '{n}',
        options: [{ value: '{n}', label: '1, 2, 3…' }, { value: '{n}/{total}', label: '1/10, 2/10…' }, { value: 'Sayfa {n}', label: 'Sayfa 1…' }, { value: '- {n} -', label: '- 1 -' }] },
      { key: 'start_at', label: 'Başlangıç numarası', type: 'number', default: 1, min: 0 },
      { key: 'fontsize', label: 'Yazı boyutu', type: 'range', default: 11, min: 7, max: 28, unit: 'pt' },
      { key: 'color', label: 'Renk', type: 'color', default: '#333333' },
      PAGES_FIELD, PW_FIELD,
    ],
    build: (files, o) => ({ file_id: files[0].file_id, position: o.position, fmt: o.fmt, start_at: +o.start_at, fontsize: +o.fontsize, color: o.color, pages: o.pages || null, password: o.password || null }),
  },
  {
    id: 'header-footer', cat: 'mark', title: 'Üst/Alt Bilgi', color: 'c-indigo', icon: 'header',
    desc: 'Her sayfaya üst bilgi ve/veya alt bilgi metni ekleyin.',
    kind: 'simple', accept: ['pdf'], multiple: false,
    endpoint: '/api/edit/header-footer',
    fields: [
      { key: 'header', label: 'Üst bilgi metni', type: 'text', default: '' },
      { key: 'footer', label: 'Alt bilgi metni', type: 'text', default: '' },
      { key: 'fontsize', label: 'Yazı boyutu', type: 'range', default: 10, min: 7, max: 20, unit: 'pt' },
      { key: 'color', label: 'Renk', type: 'color', default: '#555555' },
      PW_FIELD,
    ],
    build: (files, o) => ({ file_id: files[0].file_id, header: o.header, footer: o.footer, fontsize: +o.fontsize, color: o.color, password: o.password || null }),
  },
  {
    id: 'redact', cat: 'mark', title: 'Redaksiyon', color: 'c-red', icon: 'redact', badge: 'Görsel',
    desc: 'Hassas alanları çizerek kalıcı olarak karartın (içerik silinir).',
    kind: 'editor', accept: ['pdf'], multiple: false, editorTool: 'redact',
  },
  {
    id: 'sign', cat: 'mark', title: 'PDF İmzala', color: 'c-pink', icon: 'sign', badge: 'Görsel',
    desc: 'İmzanızı çizin veya yükleyin, ardından sayfaya yerleştirin.',
    kind: 'editor', accept: ['pdf'], multiple: false, editorTool: 'signature',
  },

  // ---------------- GÜVENLİK ----------------
  {
    id: 'protect', cat: 'security', title: 'PDF Şifrele', color: 'c-red', icon: 'lock',
    desc: 'Parola koruması ve izin kısıtlamaları ekleyin (AES-256).',
    kind: 'simple', accept: ['pdf'], multiple: false,
    endpoint: '/api/security/protect',
    fields: [
      { key: 'password', label: 'Açılış parolası', type: 'password', default: '' },
      { key: 'allow_print', label: 'Yazdırmaya izin ver', type: 'checkbox', default: true },
      { key: 'allow_copy', label: 'Metin kopyalamaya izin ver', type: 'checkbox', default: true },
      { key: 'allow_modify', label: 'Düzenlemeye izin ver', type: 'checkbox', default: false },
    ],
    build: (files, o) => ({ file_id: files[0].file_id, password: o.password, allow_print: !!o.allow_print, allow_copy: !!o.allow_copy, allow_modify: !!o.allow_modify }),
    requireField: 'password',
  },
  {
    id: 'unlock', cat: 'security', title: 'Şifre Kaldır', color: 'c-green', icon: 'unlock',
    desc: 'Parolayı doğrulayıp korumasız bir kopya oluşturun.',
    kind: 'simple', accept: ['pdf'], multiple: false,
    endpoint: '/api/security/unlock',
    fields: [{ key: 'password', label: 'Mevcut parola', type: 'password', default: '' }],
    build: (files, o) => ({ file_id: files[0].file_id, password: o.password }),
    requireField: 'password',
  },
  {
    id: 'flatten', cat: 'security', title: 'Düzleştir', color: 'c-slate', icon: 'layers',
    desc: 'Anotasyon ve form alanlarını sabitleyerek belgeyi düzleştirin.',
    kind: 'simple', accept: ['pdf'], multiple: false,
    endpoint: '/api/security/flatten',
    fields: [PW_FIELD],
    build: (files, o) => ({ file_id: files[0].file_id, password: o.password || null }),
  },
  {
    id: 'metadata', cat: 'security', title: 'Meta Veri Düzenle', color: 'c-blue', icon: 'info',
    desc: 'Başlık, yazar, konu ve anahtar kelime bilgilerini düzenleyin.',
    kind: 'metadata', accept: ['pdf'], multiple: false,
  },

  // ---------------- FORMLAR ----------------
  {
    id: 'fill-form', cat: 'forms', title: 'Form Doldur', color: 'c-violet', icon: 'form',
    desc: 'PDF form alanlarını (AcroForm) otomatik algılayıp doldurun.',
    kind: 'forms', accept: ['pdf'], multiple: false,
  },
  {
    id: 'extract-form', cat: 'forms', title: 'Form Verisi Çıkar', color: 'c-teal', icon: 'formdata',
    desc: 'Doldurulmuş form alanlarındaki verileri okuyun ve dışa aktarın.',
    kind: 'forms-extract', accept: ['pdf'], multiple: false,
  },
];

export const TOOLS_BY_ID = Object.fromEntries(TOOLS.map(t => [t.id, t]));

export const ACCEPT_MIME = {
  pdf: 'application/pdf',
  image: 'image/*',
  office: '.docx,.doc,application/vnd.openxmlformats-officedocument.wordprocessingml.document',
};

export function acceptAttr(accept) {
  return (accept || ['pdf']).map(a => ACCEPT_MIME[a] || '').filter(Boolean).join(',');
}
