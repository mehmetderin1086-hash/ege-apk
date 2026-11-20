#!/bin/zsh
cd "${0:A:h}" || exit 2
/usr/bin/python3 araclar/test-merkezi/merkez.py
kod=$?
open "$HOME/Developer/.build/asistan-test-merkezi"
print "Test turu tamamlandı. Çıkış kodu: $kod"
exit $kod
