# Secde Vakti — Windows derleme betiği (derle.sh'nin PowerShell karşılığı).
# Kullanım: .\derle.ps1 <anahtar.p12> <parola> [takma-ad]
# Gerekenler: python, .derleme\araclar altında JDK 17 (jdk\*), android-all.jar, r8lib.jar, apksig-2.3.0.jar.
param(
    [Parameter(Mandatory = $true)][string]$Anahtar,
    [Parameter(Mandatory = $true)][string]$Parola,
    [string]$Takma = "secde"
)
$ErrorActionPreference = "Stop"
$SURUM = "2.2.1"
$KOK = $PSScriptRoot
$IS = Join-Path $KOK ".derleme"
$ARAC = Join-Path $IS "araclar"
$JDK = (Get-ChildItem (Join-Path $ARAC "jdk") -Directory | Select-Object -First 1).FullName + "\bin"
$env:PYTHONUTF8 = "1"

function Calistir([string]$exe, [string[]]$argumanlar) {
    $p = Start-Process -FilePath $exe -ArgumentList $argumanlar -NoNewWindow -Wait -PassThru `
        -RedirectStandardError "$IS\son.err" -RedirectStandardOutput "$IS\son.out"
    Get-Content "$IS\son.out" | Write-Host
    if ($p.ExitCode -ne 0) { Get-Content "$IS\son.err" | Write-Host; throw "Başarısız: $exe (çıkış $($p.ExitCode))" }
}
function Tirnak([string]$s) { '"' + ($s -replace '\\', '/') + '"' }

$GIRDI = "$IS\secde_vakti_1.0.0.apk"
if (-not (Test-Path $GIRDI)) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [IO.Compression.ZipFile]::OpenRead("$KOK\kaynak\secde_vakti_1.0.0.apk.zip")
    [IO.Compression.ZipFileExtensions]::ExtractToFile($z.GetEntry("secde_vakti.apk"), $GIRDI)
    $z.Dispose()
}
if ((Get-FileHash $GIRDI -Algorithm SHA256).Hash -ne "D2DCFF49978AD5C5412C6C94E24AA9F51CEAC83ABC737462108834196A2C63F7") {
    Write-Host "UYARI: girdi APK beklenen 1.0.0 değil; yamalar uymayabilir."
}

# 1) Java katmanı -> dex
Write-Host "1) Java derleniyor"
foreach ($d in "cls", "dex") { if (Test-Path "$IS\$d") { Remove-Item "$IS\$d" -Recurse -Force }; New-Item -ItemType Directory "$IS\$d" | Out-Null }
Get-ChildItem -Recurse "$KOK\native\src" -Filter *.java | ForEach-Object { Tirnak $_.FullName } | Set-Content -Encoding ascii "$IS\kaynaklar.txt"
Calistir "$JDK\javac.exe" @("--release", "11", "-encoding", "UTF-8", "-nowarn", "-cp", (Tirnak "$ARAC\android-all.jar"), "-d", (Tirnak "$IS\cls"), ('"@' + "$IS\kaynaklar.txt" + '"'))
Get-ChildItem -Recurse "$IS\cls" -Filter *.class | ForEach-Object { $_.FullName } | Set-Content -Encoding ascii "$IS\siniflar.txt"
Calistir "$JDK\java.exe" @("-cp", (Tirnak "$ARAC\r8lib.jar"), "com.android.tools.r8.D8", "--release", "--min-api", "24", "--lib", (Tirnak "$ARAC\android-all.jar"), "--output", (Tirnak "$IS\dex"), ('"@' + "$IS\siniflar.txt" + '"'))

# 2) Manifest
Write-Host "2) Manifest"
Calistir "python" @("-I", (Tirnak "$KOK\araclar\manifest_duzenle.py"), (Tirnak $GIRDI), (Tirnak "$IS\AndroidManifest.xml"))

# 3) Tema yaması (libapp.so)
Write-Host "3) Tema yaması"
Add-Type -AssemblyName System.IO.Compression.FileSystem
$YAMALAR = @()
$zip = [IO.Compression.ZipFile]::OpenRead($GIRDI)
foreach ($ABI in "arm64-v8a", "armeabi-v7a", "x86_64") {
    New-Item -ItemType Directory -Force "$IS\lib\$ABI" | Out-Null
    $orj = "$IS\lib\$ABI\libapp.orijinal.so"
    if (-not (Test-Path $orj)) { [IO.Compression.ZipFileExtensions]::ExtractToFile($zip.GetEntry("lib/$ABI/libapp.so"), $orj, $true) }
    Calistir "python" @("-I", (Tirnak "$KOK\araclar\tema_yamasi.py"), (Tirnak $orj), (Tirnak "$IS\lib\$ABI\libapp.so"))
    $YAMALAR += (Tirnak ("lib/$ABI/libapp.so=" + "$IS\lib\$ABI\libapp.so"))
}
$zip.Dispose()

# Görseller, uygulama simgesi ve sesli meal dizini
foreach ($G in Get-ChildItem "$KOK\gorseller" -Filter *.webp) { $YAMALAR += (Tirnak ("assets/secde/" + $G.Name + "=" + $G.FullName)) }
if (Test-Path "$KOK\gorseller\uygulama_simgesi.png") {
    Calistir "python" @("-I", (Tirnak "$KOK\araclar\simge_uret.py"), (Tirnak "$KOK\gorseller\uygulama_simgesi.png"), (Tirnak "$IS\simgeler"))
    foreach ($S in Get-ChildItem "$IS\simgeler" -Filter *.png) { $YAMALAR += (Tirnak ("res/" + $S.Name + "=" + $S.FullName)) }
}
Calistir "python" @("-I", (Tirnak "$KOK\araclar\meal_ses_uret.py"), (Tirnak $GIRDI), (Tirnak "$IS\meal_ses.json"))
$YAMALAR += (Tirnak ("assets/secde/meal_ses.json=" + "$IS\meal_ses.json"))

# 4) Paketle
Write-Host "4) Paketleniyor"
Calistir "python" (@("-I", (Tirnak "$KOK\araclar\repack.py"), (Tirnak $GIRDI), (Tirnak "$IS\imzasiz.apk"),
    (Tirnak ("AndroidManifest.xml=" + "$IS\AndroidManifest.xml")), (Tirnak ("classes3.dex=" + "$IS\dex\classes.dex"))) + $YAMALAR)

# 5) İmzala ve doğrula
Write-Host "5) İmzalanıyor"
$ACIK = @("--add-exports", "java.base/sun.security.x509=ALL-UNNAMED", "--add-exports", "java.base/sun.security.pkcs=ALL-UNNAMED", "--add-exports", "java.base/sun.security.util=ALL-UNNAMED")
Calistir "$JDK\javac.exe" @("-cp", (Tirnak "$ARAC\apksig-2.3.0.jar"), "-d", (Tirnak $IS), (Tirnak "$KOK\araclar\Sign.java"), (Tirnak "$KOK\araclar\Dogrula.java"))
$CP = Tirnak "$ARAC\apksig-2.3.0.jar;$IS"
$CIKTI = "$IS\secde_vakti_$SURUM.apk"
Calistir "$JDK\java.exe" ($ACIK + @("-cp", $CP, "Sign", (Tirnak $Anahtar), $Parola, $Takma, (Tirnak "$IS\imzasiz.apk"), (Tirnak $CIKTI)))
Calistir "python" @("-I", (Tirnak "$KOK\araclar\checkalign.py"), (Tirnak $CIKTI))
Calistir "$JDK\java.exe" ($ACIK + @("-cp", $CP, "Dogrula", (Tirnak $CIKTI)))

# Sürüm arşivi
Get-ChildItem "$KOK\surumler" -Filter "secde_vakti_*.apk.zip" | Where-Object { $_.Name -ne "secde_vakti_$SURUM.apk.zip" } | Remove-Item -Force
$arsiv = "$KOK\surumler\secde_vakti_$SURUM.apk.zip"
if (Test-Path $arsiv) { Remove-Item $arsiv -Force }
$za = [IO.Compression.ZipFile]::Open($arsiv, "Create")
[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($za, $CIKTI, "secde_vakti_$SURUM.apk", "Optimal") | Out-Null
$za.Dispose()
Write-Host "Hazır: $arsiv"
Write-Host "Telefona gönderilecek APK: $CIKTI"
