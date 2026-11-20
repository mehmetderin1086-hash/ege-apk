on run
	set projectPath to "/Users/mehmetderin/Developer/seslab"
	set healthURL to "http://127.0.0.1:8010/api/system/status"
	-- Her açılışta benzersiz adres kullanılır; Chrome eski SesLab sekmesini ve
	-- önbellekte kalan JavaScript/CSS dosyalarını yeniden kullanamaz.
	set cacheKey to do shell script "/bin/date +%s"
	set appURL to "http://localhost:8010/?seslab=" & cacheKey & "#/tts"
	set logPath to "/tmp/seslab-launcher.log"

	if my sesLabIsReady(healthURL) is false then
		set startCommand to "cd " & quoted form of projectPath & " && nohup .venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8010 >> " & quoted form of logPath & " 2>&1 < /dev/null &"
		try
			do shell script startCommand
		on error errorMessage
			display alert "SesLab başlatılamadı" message errorMessage as critical
			return
		end try

		repeat with attempt from 1 to 45
			delay 1
			if my sesLabIsReady(healthURL) then exit repeat
		end repeat
	end if

	if my sesLabIsReady(healthURL) then
		open location appURL
	else
		display alert "SesLab hazır olamadı" message "Başlatma günlüğü: " & logPath buttons {"Tamam"} default button "Tamam" as critical
	end if
end run

on sesLabIsReady(healthURL)
	try
		do shell script "/usr/bin/curl --fail --silent --max-time 2 " & quoted form of healthURL & " >/dev/null"
		return true
	on error
		return false
	end try
end sesLabIsReady
