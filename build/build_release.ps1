[CmdletBinding()]
param([string]$ProjectRoot)

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $scriptDirectory = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($scriptDirectory)) {
        $scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    $ProjectRoot = Split-Path -Parent $scriptDirectory
}
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
function Write-Step([string]$Message) { Write-Host ""; Write-Host "==> $Message" -ForegroundColor Cyan }
function Invoke-Checked([string]$FilePath, [string[]]$Arguments, [string]$Description) {
    Write-Host "   $Description"
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Description zakończyło się kodem błędu $LASTEXITCODE." }
}
try {
    $root = [System.IO.Path]::GetFullPath($ProjectRoot)
    $parser = Join-Path $root "tools\LocaleParser\bin\LocaleParser-0.1.16-SNAPSHOT.jar"
    $plDir = Join-Path $root "translations\pl"
    $enDir = Join-Path $root "translations\en"
    $clDir = Join-Path $root "CL_files"
    $sourceMod = Join-Path $root "Spolszczenie_EUIV_Community_Edition"
    $jrepl = Join-Path $root "JREPL.BAT"
    $buildRoot = Join-Path $root "build"
    $workRoot = Join-Path $buildRoot "_work"
    $supplyDir = Join-Path $workRoot "supply"
    $eu4Dir = Join-Path $workRoot "eu4"
    $stageRoot = Join-Path $workRoot "staging"
    $stageMod = Join-Path $stageRoot "Spolszczenie_EUIV_Community_Edition"
    $distDir = Join-Path $root "dist"
    $zipName = "Europa-Universalis-IV-Community-Translation-2.0-PL.zip"
    $finalZip = Join-Path $distDir $zipName
    $tempZip = Join-Path $workRoot $zipName

    Write-Step "Sprawdzanie wymagań i plików wejściowych"
    if (-not (Get-Command java -ErrorAction SilentlyContinue)) { throw "Nie znaleziono Java. Zainstaluj JDK/JRE 17 lub nowsze i dodaj java do PATH." }
    $javaVersionOutput = (& java -version 2>&1 | Out-String)
    $javaVersionMatch = [System.Text.RegularExpressions.Regex]::Match($javaVersionOutput, '(?m)^(?:openjdk|java)(?: version)?\s+"?(?<version>\d+(?:\.\d+)*)')
    if (-not $javaVersionMatch.Success) { throw "Nie można odczytać wersji Java: $javaVersionOutput" }
    $javaVersionParts = $javaVersionMatch.Groups["version"].Value.Split(".")
    $javaMajor = [int]$javaVersionParts[0]
    if ($javaMajor -eq 1 -and $javaVersionParts.Length -gt 1) { $javaMajor = [int]$javaVersionParts[1] }
    if ($javaMajor -lt 17) { throw "LocaleParser wymaga Java 17 lub nowszej. Wykryto: $($javaVersionMatch.Groups["version"].Value)" }
    if (-not (Test-Path -LiteralPath $parser -PathType Leaf)) { throw "Brak LocaleParser: $parser" }
    foreach ($dir in @($plDir, $enDir, $clDir, $sourceMod)) {
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { throw "Brak wymaganego katalogu: $dir" }
    }
    if (-not (Test-Path -LiteralPath $jrepl -PathType Leaf)) { throw "Brak wymaganego narzędzia JREPL.BAT: $jrepl" }

    $plFiles = @(Get-ChildItem -LiteralPath $plDir -File -Filter "*.yml")
    $enFiles = @(Get-ChildItem -LiteralPath $enDir -File -Filter "*.yml")
    $clFiles = @(Get-ChildItem -LiteralPath $clDir -File -Filter "*.yml")
    if ($plFiles.Count -eq 0) { throw "Katalog translations\pl nie zawiera plików YAML." }
    if ($enFiles.Count -eq 0) { throw "Katalog translations\en nie zawiera plików YAML." }
    if ($clFiles.Count -eq 0) { throw "Katalog CL_files nie zawiera plików YAML." }
    $missingEnglish = @($plFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $enDir $_.Name) -PathType Leaf) })
    if ($missingEnglish.Count -gt 0) { throw "Brakuje angielskich plików referencyjnych dla: $($missingEnglish.Name -join ', ')" }

    Write-Host "   Tłumaczenia PL: $($plFiles.Count)"
    Write-Host "   Pliki referencyjne EN: $($enFiles.Count)"
    Write-Host "   Pliki Custom Localisation: $($clFiles.Count)"
    Write-Host "   Java: $(& java -version 2>&1 | Select-Object -First 1)"

    Write-Step "Przygotowanie czystego katalogu roboczego"
    if (Test-Path -LiteralPath $workRoot) { Remove-Item -LiteralPath $workRoot -Recurse -Force }
    New-Item -ItemType Directory -Path $supplyDir, $eu4Dir, $stageRoot, $distDir -Force | Out-Null

    Write-Step "Uzupełnianie pustych tłumaczeń na podstawie EN"
    Invoke-Checked "java" @("-jar", $parser, "folder_supply", $plDir, $enDir, $supplyDir, "yaml") "LocaleParser folder_supply"
    $suppliedFiles = @(Get-ChildItem -LiteralPath $supplyDir -File -Filter "*.yml")
    if ($suppliedFiles.Count -ne $plFiles.Count) { throw "Nieprawidłowa liczba plików po folder_supply: oczekiwano $($plFiles.Count), otrzymano $($suppliedFiles.Count)." }

    Write-Step "Dodawanie plików Custom Localisation"
    foreach ($file in $clFiles) { Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $supplyDir $file.Name) -Force }
    $customFile = Join-Path $supplyDir "custom_localisation_l_english.yml"
    if (-not (Test-Path -LiteralPath $customFile -PathType Leaf)) { throw "Nie znaleziono custom_localisation_l_english.yml wymaganego przez korektę pustych wartości." }

    Write-Step "Korekta pustych wartości Custom Localisation"
    $cmdLine = 'call "{0}" ": \q \q" ": \q\q" /m /x /t "|" /f "{1}" /o -' -f $jrepl, $customFile
    & $env:ComSpec /d /c $cmdLine
    if ($LASTEXITCODE -ne 0) { throw "JREPL.BAT zakończył się kodem błędu $LASTEXITCODE." }

    Write-Step "Konwersja lokalizacji do formatu EU4 (charset polish)"
    Invoke-Checked "java" @("-jar", $parser, "folder_to_eu4", $supplyDir, $eu4Dir, "polish") "LocaleParser folder_to_eu4"
    $builtFiles = @(Get-ChildItem -LiteralPath $eu4Dir -File -Filter "*.yml")
    $expectedFiles = $plFiles.Count + $clFiles.Count
    if ($builtFiles.Count -ne $expectedFiles) { throw "Nieprawidłowa liczba wygenerowanych plików: oczekiwano $expectedFiles, otrzymano $($builtFiles.Count)." }
    $emptyFiles = @($builtFiles | Where-Object { $_.Length -eq 0 })
    if ($emptyFiles.Count -gt 0) { throw "Wynik zawiera puste pliki: $($emptyFiles.Name -join ', ')" }

    Write-Step "Przygotowanie stagingowej kopii moda"
    Copy-Item -LiteralPath $sourceMod -Destination $stageMod -Recurse
    $stageLocalisation = Join-Path $stageMod "localisation"
    if (Test-Path -LiteralPath $stageLocalisation) { Remove-Item -LiteralPath $stageLocalisation -Recurse -Force }
    New-Item -ItemType Directory -Path $stageLocalisation -Force | Out-Null
    foreach ($file in $builtFiles) { Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $stageLocalisation $file.Name) }

    $descriptor = Join-Path $stageMod "descriptor.mod"
    if (-not (Test-Path -LiteralPath $descriptor -PathType Leaf)) { throw "W katalogu moda brakuje descriptor.mod." }
    $descriptorText = [System.IO.File]::ReadAllText($descriptor)
    $descriptorText = [System.Text.RegularExpressions.Regex]::Replace($descriptorText, '(?m)^\s*(?:path|remote_file_id)\s*=.*(?:\r?\n|$)', '')
    [System.IO.File]::WriteAllText($descriptor, $descriptorText, [System.Text.UTF8Encoding]::new($false))

    $stagedFiles = @(Get-ChildItem -LiteralPath $stageLocalisation -File -Filter "*.yml")
    if ($stagedFiles.Count -ne $expectedFiles) { throw "Walidacja stagingu nie powiodła się: lokalizacje=$($stagedFiles.Count), oczekiwano=$expectedFiles." }

    Write-Step "Tworzenie i sprawdzanie archiwum ZIP"
    if (Test-Path -LiteralPath $tempZip) { Remove-Item -LiteralPath $tempZip -Force }
    Compress-Archive -Path $stageMod -DestinationPath $tempZip -CompressionLevel Optimal -Force
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($tempZip)
    try {
        $prefix = "Spolszczenie_EUIV_Community_Edition/"
        $hasDescriptor = $archive.Entries | Where-Object { $_.FullName -eq ($prefix + "descriptor.mod") }
        $hasLocalisation = $archive.Entries | Where-Object { $_.FullName -like ($prefix + "localisation/*.yml") } | Select-Object -First 1
        if (-not $hasDescriptor) { throw "Archiwum ZIP nie zawiera descriptor.mod." }
        if (-not $hasLocalisation) { throw "Archiwum ZIP nie zawiera plików lokalizacji." }
    } finally { $archive.Dispose() }

    Move-Item -LiteralPath $tempZip -Destination $finalZip -Force
    Remove-Item -LiteralPath $workRoot -Recurse -Force
    Write-Host ""
    Write-Host "BUILD ZAKOŃCZONY POMYŚLNIE" -ForegroundColor Green
    Write-Host "Pliki lokalizacji: $expectedFiles"
    Write-Host "Paczka: $finalZip"
    exit 0
}
catch {
    Write-Host ""
    Write-Host "BUILD NIE POWIÓDŁ SIĘ" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "Katalog roboczy (jeśli został utworzony) pozostawiono do diagnostyki."
    exit 1
}
