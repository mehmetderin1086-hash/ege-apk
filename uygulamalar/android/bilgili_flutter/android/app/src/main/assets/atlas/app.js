const catalog=[
 {id:'saturn',title:'Satürn’ün halkaları',category:'Astronomi',desc:'Buz parçalarından oluşan halkaların yapısını keşfet.',steps:[['Buzdan halkalar','Satürn’ün etrafındaki parlak şeritleri sayısız buz parçası oluşturur. Her parça gezegen çevresinde kendi yörüngesinde hareket eder.'],['Kenardan bak','Modeli yukarı doğru sürükle. Halkalara kenardan baktığında, genişliklerine göre ne kadar ince olduklarını görebilirsin.'],['Halkaların arası','Modeldeki koyu aralığı bul. Gerçek halkalarda parçacık yoğunluğu bölgeden bölgeye değişir. Uyduların kütleçekimi bu yapının biçimlenmesinde rol oynar.']],quiz:['Satürn’ün halkalarını ağırlıklı olarak hangi madde oluşturur?',['Su buzu','Sıvı metal','Volkanik kül'],0,'Halkaların parlak görünmesinde güneş ışığını yansıtan su buzu etkilidir.']},
 {id:'atom',title:'Atomun yapısı',category:'Fizik',desc:'Çekirdeği ve elektronların bulunduğu bölgeyi incele.',steps:[['Merkezde ne var?','Çekirdek protonlardan ve çoğu atomda nötronlardan oluşur. Atomun kütlesinin büyük bölümü bu küçük bölgede toplanır.'],['Elektronlar','Negatif yüklü elektronlar çekirdeğin çevresindeki bölgede bulunur. Çizgiler şematik bir gösterimdir. Elektronların konumları kuantum mekaniğinde olasılıkla tanımlanır.'],['Elementin kimliği','Çekirdekteki proton sayısı elementin atom numarasıdır. Altı protonlu her atom karbondur.']],quiz:['Bir atomun hangi elemente ait olduğunu ne belirler?',['Nötron sayısı','Proton sayısı','Elektronların hızı'],1,'Proton sayısı değiştiğinde atom numarası ve element de değişir.']},
 {id:'galaxy',title:'Sarmal galaksiler',category:'Astronomi',desc:'Yıldızların galaksi diskindeki dağılımını gözlemle.',steps:[['Diski keşfet','Yıldızların büyük bir kısmı dönen bir disk içinde yer alır. Modeli döndürerek aynı diske üstten ve kenardan bak.'],['Sarmal kollar','Gaz ve tozun yoğunlaştığı kollarda yeni yıldızlar doğar. Genç, parlak yıldızlar kolların görünürlüğünü artırır.'],['Galaksi merkezi','Merkezdeki parlak bölgede yıldız yoğunluğu yüksektir. Birçok sarmal galaksinin merkezinde yaşlı yıldızların yoğun olduğu bir şişkinlik bulunur.']],quiz:['Genç ve parlak yıldızlar sarmal kollarda neden sık görülür?',['Diskin dönüşü durduğu için','Merkezde hiç yıldız olmadığı için','Kollarda yıldız oluşumu sürdüğü için'],2,'Kollardaki gaz bulutlarında yeni yıldızlar oluşabilir.']},
 {id:'earth',title:'Dünya’nın katmanları',category:'Yer bilimleri',desc:'Yerkabuğundan iç çekirdeğe doğru bir yolculuk.',steps:[['Yerkabuğu','En dıştaki ince, katı katman kıtaları ve okyanus tabanını taşır. Kesitin dış sınırını bul ve altındaki manto ile kalınlığını karşılaştır.'],['Manto','Kabuğun altındaki manto Dünya’nın en kalın katmanıdır. Büyük ölçüde katı kayaçlardan oluşur ve jeolojik zaman ölçeğinde yavaşça akar.'],['Dış ve iç çekirdek','Turuncu dış çekirdek sıvıdır. Merkezdeki açık renkli iç çekirdek ise yüksek basınç altında katıdır. Her iki bölüm de başlıca demir içerir.']],quiz:['Dünya’nın hangi katmanı sıvı hâldedir?',['Yerkabuğu','Dış çekirdek','İç çekirdek'],1,'Dış çekirdekteki hareketli, elektrik ileten sıvı Dünya’nın manyetik alanının oluşmasına katkıda bulunur.']}
];
const $=s=>document.querySelector(s),panel=$('#panel'),dlg=$('#dialog'),main=$('#main');
const get=id=>catalog.find(l=>l.id===id);
let saved=[],done=[],filter='Tümü',page='',active,step,angle,tilt,frame,returnFocus;
try{const d=JSON.parse(localStorage.getItem('bilgili.atlas.v1')||'{}');saved=catalog.filter(l=>d.saved?.includes(l.id)).map(l=>l.id);done=catalog.filter(l=>d.done?.includes(l.id)).map(l=>l.id)}catch{}
function persist(){try{localStorage.setItem('bilgili.atlas.v1',JSON.stringify({saved,done}))}catch{}}
const bookmark='<svg width="16" height="19" viewBox="0 0 16 20" fill="none" aria-hidden="true"><path d="M3 2h10v15l-5-3-5 3z" stroke="currentColor" stroke-width="1.6"/></svg>';
function card(l){return '<article class="card"><button class="save" data-save="'+l.id+'" aria-label="'+l.title+' dersini kaydet" aria-pressed="'+saved.includes(l.id)+'">'+bookmark+'</button><button class="cardlink" data-open="'+l.id+'"><div class="art"><canvas data-model="'+l.id+'" aria-hidden="true"></canvas><span class="idx">MODEL / 0'+(catalog.indexOf(l)+1)+'</span></div><div class="body"><span class="micro">'+l.category+'</span><h3>'+l.title+'</h3><p>'+l.desc+'</p><span class="meta">'+(done.includes(l.id)?'✓ Tamamlandı':'3 bölüm · 1 soru')+'</span></div></button></article>'}
function render(){
  page=['koleksiyon','ilerleme'].includes(location.hash.slice(1))?location.hash.slice(1):'kesfet';
  document.querySelectorAll('nav a').forEach(a=>{if(a.hash==='#'+page)a.setAttribute('aria-current','page');else a.removeAttribute('aria-current')});
  const explore=page==='kesfet',collection=page==='koleksiyon';
  const list=catalog.filter(l=>explore?(filter==='Tümü'||filter===l.category):collection?saved.includes(l.id):done.includes(l.id));
  main.innerHTML='<div class="intro"><h1>'+(explore?'Bilgi atlası':collection?'Koleksiyonum':'İlerlemem')+'</h1><p>'+(explore?'Bilimi üç boyutlu modellerle keşfet.':collection?'Tekrar keşfetmek için kaydettiğin dersler.':'Tamamladığın dersleri ve atlasındaki ilerlemeyi gör.')+'</p></div>'+
  (explore?'<section class="hero"><div class="hero-copy"><span class="micro hot">◈ &nbsp; Öne çıkan keşif</span><h2>Dünya’nın<br> <em>katmanları</em></h2><p>Yerkabuğundan iç çekirdeğe uzanan bir kesiti üç boyutlu olarak incele.</p><button class="primary" data-open="earth">Keşfe başla &nbsp; ↗</button></div><div class="visual"><img src="earth.webp" alt="Dünya’nın dış yüzeyi ve turuncu tonlarla gösterilen iç katmanları"><span class="coord">YER BİLİMLERİ / KESİT</span></div></section><section class="section"><h2>Keşif kütüphanesi</h2><div class="filters" aria-label="Konu filtresi">'+['Tümü','Astronomi','Fizik','Yer bilimleri'].map(c=>'<button class="chip" data-filter="'+c+'" aria-pressed="'+(filter===c)+'">'+c+'</button>').join('')+'</div></section>':collection?'':'<div class="stat"><strong>'+done.length+' / '+catalog.length+' ders tamamlandı</strong><div class="progress"><i style="width:'+done.length/catalog.length*100+'%"></i></div><span>%'+Math.round(done.length/catalog.length*100)+'</span></div>')+
  (list.length?'<div class="grid">'+list.map(card).join('')+'</div>':'<div class="empty"><p>'+(collection?'Ders kartındaki kayıt simgesine dokunarak ilk dersini ekleyebilirsin.':'Bir dersin sonundaki soruyu doğru yanıtladığında ilerlemen burada görünür.')+'</p><a href="#kesfet"><b>Dersleri keşfet →</b></a></div>');
  thumbnails();
}
function thumbnails(){document.querySelectorAll('[data-model]').forEach(c=>paint(c,c.dataset.model))}
function show(){if(!dlg.open){returnFocus=document.activeElement;dlg.showModal()}}
function head(title){return '<div class="modalhead"><h2>'+title+'</h2><button class="icon" data-close aria-label="Kapat">✕</button></div>'}
function openLesson(id){active=get(id);step=0;angle=active.id==='earth'?.64:.52;tilt=.32;show();lesson()}
function lesson(){
  const l=active,quiz=step===l.steps.length;
  panel.innerHTML=head(l.title)+(quiz?'<div class="pad"><span class="micro">Bilgi testi</span><h3>'+l.quiz[0]+'</h3>'+l.quiz[1].map((a,i)=>'<button class="answer" data-answer="'+i+'">'+a+'</button>').join('')+'<div id="feedback" role="status"></div><div class="lessonnav"><button class="plain" data-back>Geri</button></div></div>':'<canvas class="scene" tabindex="0" aria-label="'+l.title+' modeli. Döndürmek için sürükleyin veya yön tuşlarını kullanın."></canvas><div class="pad"><span class="hint">↔ Sürükleyerek veya yön tuşlarıyla döndür</span><p class="micro">Bölüm '+(step+1)+' / '+l.steps.length+'</p><h3>'+l.steps[step][0]+'</h3><p>'+l.steps[step][1]+'</p><div class="lessonnav"><button class="plain" data-back '+(step===0?'disabled':'')+'>Geri</button><button class="primary" data-next>'+(step===l.steps.length-1?'Teste geç':'Sonraki bölüm')+' →</button></div></div>');
  if(quiz){panel.querySelector('.answer').focus();return}
  const c=$('.scene');paint(c,l.id,angle,tilt);
  function rotate(dx,dy){angle+=dx;tilt=Math.max(-1.55,Math.min(1.55,tilt+dy));cancelAnimationFrame(frame);frame=requestAnimationFrame(()=>paint(c,l.id,angle,tilt))}
  let drag;c.onpointerdown=e=>{c.setPointerCapture(e.pointerId);drag=[e.clientX,e.clientY]};c.onpointermove=e=>{if(drag){rotate((e.clientX-drag[0])*.012,(drag[1]-e.clientY)*.012);drag=[e.clientX,e.clientY]}};c.onlostpointercapture=()=>drag=null;
  c.onkeydown=e=>{const d={ArrowLeft:[-.13,0],ArrowRight:[.13,0],ArrowUp:[0,.13],ArrowDown:[0,-.13]}[e.key];if(d){e.preventDefault();rotate(...d)}};
  c.focus({preventScroll:true});
}
function search(){show();panel.innerHTML=head('Ders ara')+'<div class="pad"><input type="search" aria-label="Ders veya konu" placeholder="Ders veya konu ara…"><div id="results"></div></div>';const input=panel.querySelector('input');
  function results(){const q=input.value.trim().toLocaleLowerCase('tr');$('#results').innerHTML=catalog.filter(l=>(l.title+' '+l.category).toLocaleLowerCase('tr').includes(q)).map(l=>'<button class="result" data-open="'+l.id+'">'+l.title+' · '+l.category+'</button>').join('')||'<p>Ders bulunamadı.</p>'}input.oninput=results;results();input.focus()}
document.addEventListener('click',e=>{
  const b=e.target.closest('button');if(!b)return;
  if(b.id==='search')search();
  else if(b.hasAttribute('data-close'))dlg.close();
  else if(b.dataset.open)openLesson(b.dataset.open);
  else if(b.dataset.filter){filter=b.dataset.filter;render();document.querySelector('[data-filter="'+filter+'"]').focus()}
  else if(b.dataset.save){const id=b.dataset.save;saved=saved.includes(id)?saved.filter(x=>x!==id):[...saved,id];persist();if(page==='koleksiyon')render();else b.setAttribute('aria-pressed',saved.includes(id))}
  else if(b.hasAttribute('data-next')){step++;lesson()}
  else if(b.hasAttribute('data-back')){step--;lesson()}
  else if(b.hasAttribute('data-answer')){
    const right=Number(b.dataset.answer)===active.quiz[2];
    b.classList.add(right?'good':'bad');b.disabled=true;
    $('#feedback').innerHTML=right?'<p><b>Doğru!</b> '+active.quiz[3]+'</p><button class="primary" data-close>Dersi bitir ✓</button>':'<p>Tekrar dene. İstersen önceki bölümü inceleyebilirsin.</p>';
    if(right){panel.querySelectorAll('.answer').forEach(a=>a.disabled=true);if(!done.includes(active.id)){done.push(active.id);persist()}render()}
  }
});
dlg.addEventListener('close',()=>{if(returnFocus?.isConnected)returnFocus.focus();else document.querySelector('nav a[aria-current]').focus()});
dlg.addEventListener('click',e=>{if(e.target===dlg)dlg.close()});
window.addEventListener('hashchange',render);
let resizeTimer;window.addEventListener('resize',()=>{clearTimeout(resizeTimer);resizeTimer=setTimeout(()=>{thumbnails();if(dlg.open&&$('.scene'))paint($('.scene'),active.id,angle,tilt)},140)});
render();
