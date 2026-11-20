// A depth-sorted point surface keeps the models interactive even when WebGL is unavailable.
const models=new Map();
function model(kind){
  if(models.has(kind))return models.get(kind);
  const points=[],tau=Math.PI*2;
  let seed=57;
  function random(){seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296}
  function point(x,y,z,color,size){points.push({x,y,z,color,size})}
  function sphere(radius,color,earth=false){
    for(let i=0;i<7000;i++){
      const y=1-2*i/6999,a=i*2.39996323,r=Math.sqrt(1-y*y),x=r*Math.cos(a),z=r*Math.sin(a);
      if(earth&&x>0&&z>0)continue;
      const light=0.72+0.24*y-0.13*x+0.07*z;
      let base=color;
      if(earth){const land=Math.sin(6*x+2*y)*Math.cos(4*z-3*y)+0.35*Math.sin(14*y+4*z);base=Math.abs(y)>.88?[201,215,207]:land>.12?[115,134,79]:[48,106,133]}
      if(kind==='saturn'){const stripe=0.85+0.13*Math.cos(24*y)+0.05*Math.cos(56*y);base=color.map(v=>v*stripe)}
      point(x*radius,y*radius,z*radius,'rgb('+base.map(v=>Math.round(v*light)).join(',')+')',radius*.036);
    }
  }
  if(kind==='earth'){
    sphere(1,[0,0,0],true);
    for(let i=0;i<9000;i++){const a=random()*Math.PI,r=Math.sqrt(random()),y=r*Math.cos(a),x=r*Math.sin(a),c=r<.2?'#ffd361':r<.55?'#f69b37':r<.96?'#ce542a':'#724a39';point(i%2?x:0,y,i%2?0:x,c,.025)}
  }else if(kind==='saturn'){
    sphere(.58,[225,188,137]);
    for(let i=0;i<12500;i++){const a=random()*tau,r=.73+random()*.56;if(r>1.04&&r<1.08)continue;point(r*Math.cos(a),0,r*Math.sin(a),['#c9ad88','#ead6b3','#a1917a'][Math.floor(r*84)%3],.009+random()*.008)}
  }else if(kind==='atom'){
    for(let k=0;k<3;k++){const tilt=k*Math.PI/3;for(let i=0;i<650;i++){const a=i*tau/650,x=Math.cos(a)*1.05,y=Math.sin(a)*.37;point(x*Math.cos(tilt)-y*Math.sin(tilt),x*Math.sin(tilt)+y*Math.cos(tilt),Math.sin(a)*.5,'#98d8c5',.014)}const t=k+1,x=Math.cos(t)*1.05,y=Math.sin(t)*.37;point(x*Math.cos(tilt)-y*Math.sin(tilt),x*Math.sin(tilt)+y*Math.cos(tilt),Math.sin(t)*.5,'#dbffe6',.075)}
    sphere(.25,[225,169,105]);
  }else{
    for(let i=0;i<8500;i++){const r=Math.pow(random(),.65)*1.17,a=r*4+(i%3)*tau/3+(random()-.5)*(.28+.4*r);point(r*Math.cos(a),(random()-.5)*.15,r*Math.sin(a),r<.24?'#ffdab3':['#b895ca','#ceaeba','#8a84b8'][i%3],.006+random()*.013)}
  }
  models.set(kind,points);return points;
}
function paint(canvas,kind,angle=.52,tilt=.32){
  const rect=canvas.getBoundingClientRect(),ratio=Math.min(window.devicePixelRatio||1,1.6);
  if(!rect.width||!rect.height)return;
  const w=Math.round(rect.width*ratio),h=Math.round(rect.height*ratio);
  if(canvas.width!==w||canvas.height!==h){canvas.width=w;canvas.height=h}
  const ctx=canvas.getContext('2d'),scale=Math.min(h*.43,w*.37),cs=Math.cos(angle),sn=Math.sin(angle),ct=Math.cos(tilt),st=Math.sin(tilt);
  const bg={earth:'#191c19',saturn:'#2e2420',atom:'#19332e',galaxy:'#272337'}[kind];
  ctx.fillStyle=bg;ctx.fillRect(0,0,w,h);
  for(let i=1;i<85;i++){ctx.fillStyle='rgba(245,237,213,'+(.12+(i%4)*.09)+')';ctx.fillRect((Math.sin(i*14.13)*4523%1+1)%1*w,(Math.sin(i*9.2)*3165%1+1)%1*h,ratio,ratio)}
  const projected=model(kind).map(p=>{const x=p.x*cs-p.z*sn,z=p.x*sn+p.z*cs;return [x,p.y*ct-z*st,p.y*st+z*ct,p]});
  projected.sort((a,b)=>a[2]-b[2]);
  for(const [x,y,,p] of projected){ctx.fillStyle=p.color;ctx.beginPath();ctx.arc(w/2+x*scale,h/2-y*scale,p.size*scale,0,Math.PI*2);ctx.fill()}
}
