import struct,sys,zipfile
def strpool(data,pos):
    sc,stc,fl,so,sso=struct.unpack_from('<IIIII',data,pos+8)
    utf8=fl&0x100;offs=struct.unpack_from('<%dI'%sc,data,pos+28);base=pos+so;r=[]
    for o in offs:
        p=base+o
        if utf8:
            n=data[p];p+=1
            if n&0x80:p+=1
            n=data[p];p+=1
            if n&0x80:n=((n&0x7f)<<8)|data[p];p+=1
            r.append(data[p:p+n].decode('utf8','replace'))
        else:
            n=struct.unpack_from('<H',data,p)[0];p+=2
            if n&0x8000:n=((n&0x7fff)<<16)|struct.unpack_from('<H',data,p)[0];p+=2
            r.append(data[p:p+2*n].decode('utf16','replace'))
    return r
d=zipfile.ZipFile(sys.argv[1]).read('resources.arsc')
hs=struct.unpack_from('<H',d,2)[0]
pos=hs;gstr=strpool(d,pos);pos+=struct.unpack_from('<I',d,pos+4)[0]
want=set(sys.argv[2].split(',')) if len(sys.argv)>2 else None
# package
pkgid=struct.unpack_from('<I',d,pos+8)[0];phs=struct.unpack_from('<H',d,pos+2)[0]
ts,_,ks,_=struct.unpack_from('<IIII',d,pos+268)
types=strpool(d,pos+ts);keys=strpool(d,pos+ks)
p=pos+phs;end=pos+struct.unpack_from('<I',d,pos+4)[0]
seen=set()
while p<end:
    t,h,sz=struct.unpack_from('<HHI',d,p)
    if t==0x0201:
        tid=d[p+8];flags=d[p+9];cnt,est=struct.unpack_from('<II',d,p+12)
        tn=types[tid-1]
        if want is None or tn in want:
            sparse=flags&1
            for i in range(cnt):
                if sparse:
                    idx,off=struct.unpack_from('<HH',d,p+h+i*4);off*=4
                else:
                    idx=i;off=struct.unpack_from('<I',d,p+h+i*4)[0]
                    if off==0xffffffff:continue
                e=p+est+off
                esz,efl,kidx=struct.unpack_from('<HHI',d,e)
                if efl&1:continue
                vt=d[e+esz+3];vd=struct.unpack_from('<I',d,e+esz+4)[0]
                val=gstr[vd] if vt==3 else hex(vd)
                k=(tn,keys[kidx],val)
                if k in seen:continue
                seen.add(k);print('0x%02x%02x%04x'%(pkgid,tid,idx),tn,keys[kidx],val)
    p+=sz
