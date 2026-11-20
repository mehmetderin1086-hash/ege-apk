import sys,struct,zipfile
f=sys.argv[1];d=open(f,'rb').read();z=zipfile.ZipFile(f);bad=[]
for i in z.infolist():
    if i.compress_type: continue
    nl,el=struct.unpack_from('<HH',d,i.header_offset+26);off=i.header_offset+30+nl+el
    al=16384 if i.filename.endswith('.so') else 4
    if off%al: bad.append(i.filename)
print('v2:',d.rfind(b'APK Sig Block 42')>0,'hizasız:',bad,'testzip:',z.testzip())
