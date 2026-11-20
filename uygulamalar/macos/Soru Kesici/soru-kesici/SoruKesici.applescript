use scripting additions

property projeDizini : "/Users/mehmetderin/Developer/soru-kesici"
property arayuzAdresi : "http://127.0.0.1:8756"
property gunlukYolu : "/tmp/soru-kesici.log"

on run
	if my sunucuHazir() is false then
		set baslatKomutu to "cd " & quoted form of projeDizini & " && " & ¬
			"if [ -x .venv/bin/python ]; then " & ¬
			"/usr/bin/nohup .venv/bin/python soru_kes_web.py >>" & quoted form of gunlukYolu & " 2>&1 </dev/null & " & ¬
			"else exit 2; fi"
		
		try
			do shell script baslatKomutu
		on error hataMetni number hataKodu
			if hataKodu is 2 then
				display dialog "Soru Kesici Python ortamı bulunamadı." & return & projeDizini buttons {"Tamam"} default button "Tamam" with icon stop
			else
				display dialog "Soru Kesici başlatılamadı:" & return & hataMetni buttons {"Tamam"} default button "Tamam" with icon stop
			end if
			return
		end try
		
		repeat with deneme from 1 to 45
			delay 1
			if my sunucuHazir() then exit repeat
		end repeat
	end if
	
	if my sunucuHazir() then
		do shell script "/usr/bin/open " & quoted form of arayuzAdresi
	else
		display dialog "Soru Kesici hazır olamadı." & return & "Başlatma günlüğü: " & gunlukYolu buttons {"Tamam"} default button "Tamam" with icon stop
	end if
end run

on sunucuHazir()
	try
		do shell script "/usr/bin/curl --fail --silent --max-time 2 " & quoted form of arayuzAdresi & " >/dev/null"
		return true
	on error
		return false
	end try
end sunucuHazir
