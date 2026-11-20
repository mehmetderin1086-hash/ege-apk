import struct,sys,zipfile
def parse(data):
    out=[];strings=[];resids=[];ns={}
    pos=8;depth=0
    while pos<len(data):
        t,hs,sz=struct.unpack_from('<HHI',data,pos)
        if t==0x0001:
            sc,stc,fl,so,sso=struct.unpack_from('<IIIII',data,pos+8)
            utf8=fl&0x100
            offs=struct.unpack_from('<%dI'%sc,data,pos+28)
            base=pos+so
            for o in offs:
                p=base+o
                if utf8:
                    n=data[p];p+=1
                    if n&0x80:p+=1
                    n=data[p];p+=1
                    if n&0x80:n=((n&0x7f)<<8)|data[p];p+=1
                    strings.append(data[p:p+n].decode('utf8','replace'))
                else:
                    n=struct.unpack_from('<H',data,p)[0];p+=2
                    if n&0x8000:n=((n&0x7fff)<<16)|struct.unpack_from('<H',data,p)[0];p+=2
                    strings.append(data[p:p+2*n].decode('utf16','replace'))
        elif t==0x0180:
            resids=list(struct.unpack_from('<%dI'%((sz-8)//4),data,pos+8))
        elif t==0x0102:
            nsi,name,aStart,aSize,aCount=struct.unpack_from('<iiHHH',data,pos+16)
            attrs=[]
            for i in range(aCount):
                a=pos+16+aStart+i*aSize
                ans,an,araw,_,_,dt,dv=struct.unpack_from('<iiiHBBI',data,a)
                nm=strings[an] if an>=0 and an<len(strings) and strings[an] else ('res0x%08x'%resids[an] if an<len(resids) else '?')
                if araw>=0:v=strings[araw]
                elif dt==3:v=strings[dv]
                elif dt==1:v='@0x%08x'%dv
                elif dt==0x12:v='true' if dv else 'false'
                elif dt in(0x10,0x11):v=str(dv if dv<2**31 else dv-2**32) if dt==0x10 else hex(dv)
                else:v='(t%d)0x%x'%(dt,dv)
                attrs.append('%s="%s"'%(nm,v))
            out.append('  '*depth+'<'+strings[name]+' '+' '.join(attrs)+'>');depth+=1
        elif t==0x0103:depth-=1
        pos+=sz
    return '\n'.join(out)
z=zipfile.ZipFile(sys.argv[1]);print(parse(z.read('AndroidManifest.xml')))
