#!/usr/bin/env python3
"""XcodeGen sonrası düzeltme (13 Eki 2026): `group: Ortak/Resources` ile eklenen Oku kaynakları (Engine, VoiceSamples, MEBKatalog)
XcodeGen tarafından ayrıca yolu yansıtan 'DersPodcast/Resources' grubuna da konuyor; Xcode 'member of multiple groups' uyarısı verip
rastgele birini seçiyor. Yanlış üyelik seçilince yol DersPodcast/DersPodcast/Resources/… olarak çözülür ve derleme kaynakları
bulamaz. Bu betik yansıtılan gruptaki çift üyelikleri siler; yalnız ad tabanlı (yolsuz) Ortak/Resources üyeliği kalır.
Kullanım: xcodegen generate && python3 pbxproj-duzelt.py"""
import re
import sys
from pathlib import Path

path = Path(sys.argv[1] if len(sys.argv) > 1 else "Ikra.xcodeproj/project.pbxproj")
s = path.read_text()
pattern = re.compile(r"\n\t\t([0-9A-F]{24}) /\* ([^*]+) \*/ = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \((.*?)\);(.*?)\n\t\t\};", re.S)
groups = {m.group(1): m for m in pattern.finditer(s)}
def has_path(m): return re.search(r"\n\t\t\tpath = ", m.group(4)) is not None
def children(m): return re.findall(r"([0-9A-F]{24}) /\*", m.group(3))
removed = 0
# Her silmeden sonra gruplar yeniden okunur: aynı yansıtılmış grupta birden çok çift üyelik olabilir (Engine + VoiceSamples).
while True:
    groups = {m.group(1): m for m in pattern.finditer(s)}
    parents = {}
    for gid, m in groups.items():
        for c in children(m):
            parents.setdefault(c, []).append(gid)
    target = None
    for cid, ps in parents.items():
        named = [p for p in ps if not has_path(groups[p])]
        mirrored = [p for p in ps if has_path(groups[p])]
        if named and mirrored:
            target = (cid, mirrored[0])
            break
    if not target:
        break
    cid, p = target
    m = groups[p]
    new_children, n = re.subn(r"\n\t\t\t\t" + cid + r" /\* [^*]+ \*/,", "", m.group(3))
    if not n:
        raise SystemExit(f"çocuk satırı bulunamadı: {cid} @ {p}")
    s = s.replace(m.group(0), m.group(0).replace(m.group(3), new_children, 1), 1)
    removed += n
# Boş kalan yansıtılmış grupları üstlerinden ve tanımlardan sil (yalnız çocuğu kalmayanlar).
for _ in range(4):
    groups = {m.group(1): m for m in pattern.finditer(s)}
    empty = [gid for gid, m in groups.items() if has_path(m) and not children(m)]
    if not empty:
        break
    for gid in empty:
        s = s.replace(groups[gid].group(0), "", 1)
        s = re.sub(r"\n\t\t\t\t" + gid + r" /\* [^*]+ \*/,", "", s)
path.write_text(s)
print(f"pbxproj düzeltildi: {removed} çift üyelik kaldırıldı")
