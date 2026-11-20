# Kullanım: repack.py girdi.apk çıktı.apk [yol=yerelDosya ...]
# Girdideki girişleri sırasıyla korur, imza dosyalarını atar, verilen girişleri değiştirir,
# sıkıştırılmamış girişleri hizalar (.so -> 16384, diğer -> 4).
import sys,zipfile,struct,zlib
src,dst=sys.argv[1],sys.argv[2]
repl=dict(x.split('=',1) for x in sys.argv[3:])
zin=zipfile.ZipFile(src)
out=open(dst,'wb');cd=[]
for zi in zin.infolist():
    n=zi.filename
    if n.startswith('META-INF/') and n.split('/')[-1].upper().endswith(('.SF','.RSA','.EC','.DSA','MANIFEST.MF')):continue
    data=open(repl[n],'rb').read() if n in repl else zin.read(n)
    method=zi.compress_type
    crc=zlib.crc32(data)&0xffffffff
    comp=data if method==0 else (lambda c:c.compress(data)+c.flush())(zlib.compressobj(9,zlib.DEFLATED,-15))
    name=n.encode()
    off=out.tell();hdr=30+len(name)
    extra=b''
    if method==0:
        al=16384 if n.endswith('.so') else 4
        pad=(-(off+hdr))%al
        if pad: extra=b'\0'*pad
    out.write(struct.pack('<IHHHHHIIIHH',0x04034b50,20,0x0800 if any(ord(c)>127 for c in n) else 0,method,0,0x21,crc,len(comp),len(data),len(name),len(extra))+name+extra+comp)
    cd.append((name,method,crc,len(comp),len(data),off))
import os
mevcut={zi.filename for zi in zin.infolist()}
for n,yol in repl.items():
    if n in mevcut: continue
    data=open(yol,'rb').read();crc=zlib.crc32(data)&0xffffffff
    c=zlib.compressobj(9,zlib.DEFLATED,-15);comp=c.compress(data)+c.flush()
    name=n.encode();off=out.tell()
    out.write(struct.pack('<IHHHHHIIIHH',0x04034b50,20,0,8,0,0x21,crc,len(comp),len(data),len(name),0)+name+comp)
    cd.append((name,8,crc,len(comp),len(data),off))
cdo=out.tell()
for name,method,crc,cs,us,off in cd:
    out.write(struct.pack('<IHHHHHHIIIHHHHHII',0x02014b50,20,20,0,method,0,0x21,crc,cs,us,len(name),0,0,0,0,0,off)+name)
cde=out.tell()
out.write(struct.pack('<IHHHHIIH',0x06054b50,0,0,len(cd),len(cd),cde-cdo,cdo,0))
out.close();print('yazıldı',dst,len(cd),'giriş')
