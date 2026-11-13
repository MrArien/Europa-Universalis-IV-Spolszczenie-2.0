# Budowanie paczki EU4 Community Translation 2.0

## Wymagania
- Windows 10/11.
- Java 17 lub nowsza dostępna w PATH.
- Kompletne katalogi translations/pl, translations/en oraz CL_files.
- tools/LocaleParser/bin/LocaleParser-0.1.16-SNAPSHOT.jar.
- JREPL.BAT (wykorzystywany do dotychczasowej korekty pustych wartości Custom Localisation).

Nie trzeba kompilować LocaleParsera ani instalować Maven. Repozytorium zawiera gotowy JAR z zależnościami.

## Budowanie
Uruchom PowerShell w katalogu repozytorium:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build\build_release.ps1

## Co robi builder
1. Sprawdza Javę, JAR, katalogi wejściowe i kompletność plików referencyjnych EN.
2. Czyści wyłącznie własny katalog roboczy build/_work.
3. Uruchamia LocaleParser folder_supply na translations/pl i translations/en.
4. Dodaje pliki z CL_files.
5. Uruchamia korektę pustych wartości w custom_localisation_l_english.yml przez JREPL.BAT.
6. Konwertuje komplet do formatu EU4 przy użyciu charsetu polish.
7. Kopiuje istniejący mod do stagingu i podmienia lokalizacje wyłącznie w kopii.
8. Usuwa z kopii stagingowej lokalne path i remote_file_id z descriptor.mod.
9. Weryfikuje liczbę i niepustość plików oraz zawartość archiwum ZIP.
10. Zapisuje paczkę w dist/.

## Wynik
    dist/
    └── Europa-Universalis-IV-Community-Translation-2.0-PL.zip

Archiwum zawiera katalog Spolszczenie_EUIV_Community_Edition wraz z descriptor.mod, zasobami moda i wygenerowanym katalogiem localisation/.

## Bezpieczeństwo i ograniczenia
- Builder nie modyfikuje źródłowych translations/, CL_files/ ani katalogu moda.
- Poprzednia paczka w dist/ jest zastępowana dopiero po zbudowaniu i wstępnej walidacji nowego ZIP-a.
- W razie błędu katalog build/_work pozostaje do diagnostyki.
- Skrypt nie zmienia version ani supported_version w descriptor.mod. Te wartości muszą zostać ustalone na podstawie docelowego wydania i faktycznie testowanej wersji gry.
- Pomyślne utworzenie ZIP-a nie zastępuje testu uruchomienia moda w grze.
