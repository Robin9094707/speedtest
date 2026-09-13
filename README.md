# RJ Speedtest 3.0 für iOS

[![iOS App · Tests & IPA](https://github.com/Robin9094707/speedtest/actions/workflows/ios.yml/badge.svg)](https://github.com/Robin9094707/speedtest/actions/workflows/ios.yml)

Eine native, deutschsprachige SwiftUI-App für Robin Juhas. Großer Glastacho, echte Download-/Uploadmessungen, persönliche Karten und Netz-Rekorde. Ab iOS 17; echtes Liquid Glass ab iOS 26, mit Material-Fallback für ältere Versionen. Universal-App für iPhone und iPad.

## IPA herunterladen

1. [GitHub Actions öffnen](https://github.com/Robin9094707/speedtest/actions/workflows/ios.yml).
2. Den neuesten erfolgreichen Lauf wählen.
3. Unter **Artifacts → RJ-Speedtest-IPA** das ZIP herunterladen und entpacken.
4. `RJ-Speedtest.ipa` mit dem eigenen Apple-Profil signieren und installieren. Siehe [INSTALLATION.md](INSTALLATION.md).

**Die automatisch erzeugte IPA ist unsigniert.** Sie lässt sich nicht durch einfaches Antippen auf einem normalen iPhone installieren. Es sind keine fremden Zertifikate, Apple-Zugangsdaten oder private Schlüssel im Repository hinterlegt. TestFlight/App-Store-Verteilung erfordert eine eigene Apple-Developer-Konfiguration.

## Funktionen

- Wählbare Tacho-Skalen: 100, 250, 300, 500, 1.000, 2.500 Mbit/s oder Automatik. Eine feste Skala begrenzt nur den Zeiger; die numerische Messung bleibt offen nach oben.
- Einstellbare Live-Haptik: ruhige bis schnelle, kräftigere Impulse abhängig von Geschwindigkeit und Skala; sanfte Phasenwechsel und Abschlussfeedback. Während Wiederholungspausen, nach Stopp oder im Hintergrund endet die Live-Haptik.
- Schonendere schnelle Downloads mit adaptiven Blöcken bis 100 MB. Vorübergehende Verbindungsfehler und bestimmte HTTP-Fehler lösen höchstens zwei neue Versuche je Phase mit weniger Verbindungen aus. `Retry-After` wird berücksichtigt; längere Serverpausen werden als Countdown angezeigt und über App-Neustarts hinweg gespeichert. Es werden weder Serverlimits umgangen noch unbegrenzt Anfragen wiederholt.
- Fehlgeschlagene Lastversuche verbrauchen weiterhin das vorhandene Datenbudget. Ergebnisse beruhen auf dem erfolgreichen Versuch; Wiederholungen werden in den Details ausgewiesen. HTTP 200 mit einer HTML-Anmeldeseite wird als ungültige Testantwort erklärt, nicht als vermeintlicher Bann.

- Native SwiftUI-Oberfläche mit Liquid Glass, großem Start-/Stoppknopf, adaptivem 270°-Tacho und Live-Kurve.
- Basisskala 1.000 Mbit/s; automatische Erweiterung auf 2.500, 5.000, 10.000 Mbit/s und darüber.
- Ablauf: HTTPS-Latenz und Jitter → Download → Upload. Keine simulierten Messwerte.
- 1, 2, 4, 6 oder 8 parallele Transfers; drei Testdauern, Datenbudget und Mobilfunkbestätigung.
- Standortfreigabe beim Einstieg, freiwillig; aktuelle Position wird beim Start der Lastmessung gespeichert.
- Karte mit Pins, Netzfilter, Ergebnisdetails und Standortgenauigkeit.
- Lokal gespeicherter Verlauf mit Suche, WLAN-/Mobilfunkfilter, Einzel-Löschung, Notizen und Teilen.
- Eigene Download-/Uploadrekorde pro SSID bzw. bewusst gewähltem Netzprofil, mit Animation und Haptik.
- Deutsch, Mbit/s oder MB/s, System-/Hell-/Dunkelmodus, vier Akzentfarben, Bewegung und Transparenz berücksichtigen iOS-Bedienungshilfen.
- JSON-/CSV-Export inklusive Notizen und Orten. Kein Login, kein Werbe-SDK, keine Analytics.

## Messverfahren und Grenzen

Als voreingestellten Anbieter verwendet die App die im offiziellen [Cloudflare-Speedtest-Projekt](https://github.com/cloudflare/speedtest) dokumentierten öffentlichen HTTPS-Endpunkte `https://speed.cloudflare.com/__down?bytes=…` und `https://speed.cloudflare.com/__up`. Kein API-Key, eigenes Server-Abo oder JavaScript-SDK erforderlich. Dies ist eine unabhängige App und keine offizielle Cloudflare-App. Öffentliche Endpunkte können sich ändern, zeitweilig begrenzen oder ausfallen.

Download-Daten werden per `URLSessionDataDelegate` gezählt und sofort verworfen. Uploads enthalten ausschließlich neu erzeugte zufällige Bytes, niemals lokale Dateien. Die Uploadrate zählt erfolgreich per HTTP bestätigte Nutzdaten. Die Chunkgröße passt sich an die Verbindung an. Deshalb können kleine Live-Intervalle beim Upload sprunghaft sein; das Ergebnis verwendet den zeitlichen Durchschnitt bestätigter Transfers, nicht die höchste Nadelspitze. Kurze, am Phasenende noch nicht bestätigte Uploads zählen zum übertragenen Volumen, aber nicht zur finalen Bandbreite.

Die ersten ungefähr 0,8 Sekunden einer Lastphase werden nach Möglichkeit als Anlaufphase aus dem Mittelwert ausgeklammert. Bei sehr früh erreichtem Datenbudget wird die gesamte kurze Phase verwendet. Kleine Budgets können schnelle Verbindungen deshalb unterschätzen. Für schnelle 5G-/Gigabitanschlüsse ist ein längerer Test mit ausreichend Datenbudget sinnvoll.

Latenz ist der Median von sechs kleinen HTTPS-Roundtrips nach einer nicht gewerteten Aufwärmanfrage, einschließlich Serververarbeitung und ohne Abzug von `Server-Timing`. Jitter ist die mittlere absolute Differenz aufeinanderfolgender Roundtrips. **Kein ICMP-Ping, keine Paketverlustmessung und kein Ookla-Zertifikat.** WLAN, Router, VPN, Mobilfunkzelle, der verwendete HTTP-Transport und der gewählte Messserver beeinflussen die Ergebnisse.

Jede Richtung erhält die Hälfte des Nutzdatenbudgets. Das angezeigte „1 GB“-Profil reserviert insgesamt maximal 1.024.000.000 Transferbytes; HTTPS-/TCP-/IP-Overhead und kleine Latenzanfragen sind zusätzlich möglich. Eine Phase endet nach ihrer Testdauer oder beim Erreichen ihres Budgets. Abbruch, Hintergrundwechsel, erkannter Netzwechsel und HTTP-Fehler erzeugen **keinen gespeicherten vollständigen Test**. WLAN-Tests erlauben keinen stillen Mobilfunk-Fallback.

## WLAN-Erkennung

iOS stellt den WLAN-Namen nur unter bestimmten Berechtigungs- und Signierungsbedingungen bereit. Das Projekt enthält das optionale `com.apple.developer.networking.wifi-info`-Entitlement und verwendet `NEHotspotNetwork.fetchCurrent`. Ein Sideload-Signer oder ein kostenloses Apple-Profil kann diese Berechtigung entfernen oder nicht unterstützen. Die App funktioniert trotzdem: Auf dem Startbildschirm einen Namen eingeben oder ein vorhandenes manuelles Profil wählen.

- Erkannte SSIDs bilden eigene Rekordgruppen. Gleich benannte SSIDs werden zusammengefasst.
- Manuelle Profile sind von automatisch erkannten SSIDs getrennt und müssen bewusst richtig gewählt werden.
- Unbenannte WLANs werden niemals pauschal zu einem gemeinsamen WLAN-Rekord vermischt.
- Mobilfunk ohne Profilnamen bildet eine gemeinsame Gruppe. Für getrennte SIMs/Anbieter manuell z. B. „o2“ und „Telekom“ wählen.
- Die App behauptet keine 5G-/LTE-, Provider-, Router- oder Signalstärkenerkennung, die iOS nicht zuverlässig ermöglicht.

## Datenschutz

Historie, Koordinaten und Notizen bleiben im geschützten App-Verzeichnis. Keine eigene Cloud-Synchronisierung. Betriebssystem-Backups können App-Daten entsprechend deinen iOS-Einstellungen enthalten. Für Messanfragen sieht der gewählte Messanbieter die technisch notwendige IP-Adresse und Verbindungsinformationen. Karten verwenden Apple MapKit. Standort und Notizen werden nicht an den Speedtest-Endpunkt gesendet. Exporte enthalten gespeicherte Orte und sind entsprechend bewusst zu teilen.

Der Standort ist optional. Ohne Freigabe bzw. ohne aktuelle Position gibt es ein vollständiges Messergebnis ohne Kartenpin. Es werden keine Hintergrundstandorte erfasst. [Cloudflare-Datenschutz](https://www.cloudflare.com/privacypolicy/).

## Lokal bauen

Voraussetzung: macOS mit Xcode 26 oder neuer und installiertem iOS-SDK.

```sh
python3 scripts/make_icon.py
python3 scripts/generate_project.py
open Speedtest.xcodeproj
```

Schema `Speedtest` wählen. Für eine direkte Geräteinstallation in Xcode das eigene Team wählen und ggf. Bundle-ID sowie unterstützte Capabilities anpassen. Kein Swift-Package-, CocoaPods- oder Homebrew-Download nötig.

## CI und Tests

`.github/workflows/ios.yml` wird bei Push auf `main`, Pull Requests und manuell ausgeführt:

1. Deterministisches Xcode-Projekt und App-Icon erstellen.
2. Auf einem verfügbaren iOS-26+-iPhone-Simulator Unit-Tests und die fünf App-Tabs prüfen.
3. Für ein echtes iPhone ein Release-ARM64-Archiv ohne Codesignatur bauen.
4. `Payload/Speedtest.app` als IPA paketieren und Bundle, Mach-O, Assets und Plattform prüfen.
5. IPA, SHA-256-Prüfsumme, Installationshinweise sowie Testberichte/Screenshots bereitstellen.

Tests decken Einheiten, Skalen über Gigabit, Latenzstatistik, getrennte Netzidentitäten, Rekordberechnung, persistente Notizen und Löschungen, Exporte, HTTP-Fehler und Abbruch ab. Simulator-Tests sind keine Kalibrierung der Bandbreitenmessung auf echter Hardware. Der Test auf deinem iPhone bleibt für reale Funkbedingungen und Sideload-Berechtigungen erforderlich.

## Projektstruktur

```text
Speedtest/Models/       Datenmodelle, Statistik, Rekorde
Speedtest/Services/     Transfers, Standort, Netz, lokale Speicherung
Speedtest/Views/        Tacho, Verlauf, Karte, Einblicke, Vergleiche, Router-Labor, Einstellungen
Speedtest/Resources/    Icon, Info.plist, Datenschutz, Entitlements
Tests/                 Unit- und Transporttests
UITests/               App-Start, Navigation und Screenshots
scripts/               Reproduzierbare Projekt-/Icon-Erstellung, IPA-Prüfung
.github/workflows/     Automatischer Xcode-Test und IPA-Build
```

## Serverauswahl und HTTP 403

Unter dem Startknopf und in den Einstellungen lässt sich der Messserver wechseln. Die App lädt auf Wunsch das öffentliche Verzeichnis, das auch der offizielle [LibreSpeed-CLI](https://github.com/librespeed/speedtest-cli/blob/master/speedtest/speedtest.go) nutzt: `https://librespeed.org/backend-servers/servers.php`. Die Liste wird lokal zwischengespeichert. Auswahl und frühere Ergebnisse bleiben bei Updates erhalten. Es gibt keine automatische Serverrotation und keinen Anbieterwechsel mitten in einer Messung.

LibreSpeed-Downloads verwenden `ckSize` (MiB-Chunks beim PHP-Backend), Upload und HTTP-Ping die im Verzeichnis angegebenen Endpunkte. Alle Verbindungen verwenden HTTPS und die normale iOS-Zertifikatsprüfung. Der gewählte Betreiber sieht die für Verbindungen nötigen Daten; die Verzeichnisabfrage geht an LibreSpeed. Standort, Notizen und Ergebnis-Telemetrie werden nicht an diese Dienste gesendet. Download und Upload eines Tests verwenden denselben Server; dessen Name wird im Ergebnis gespeichert. Andere Standorte und Betreiber können andere Messwerte ergeben.

HTTP 403 bedeutet Zugriffsablehnung, ohne die Ursache zu beweisen. Die App versucht solche Ablehnungen nicht automatisch erneut. Eine `Retry-After`-Pause gilt nur für den jeweiligen Serverhost, auch nach einem Neustart. Die frühere globale Cloudflare-Pause wird dem Cloudflare-Host zugeordnet. Andere Anbieter bleiben manuell auswählbar. Bei fehlendem HTTPS, Wartung oder Überlastung kann auch ein Verzeichniseintrag scheitern; öffentliche Server garantieren weder dauerhafte Verfügbarkeit noch unbegrenzt viele Tests.

## Automatische WLAN-Namen und Bildexport

`NEHotspotNetwork.fetchCurrent` wird um `CNCopyCurrentNetworkInfo` als Fallback ergänzt. Die App fragt nur das verbundene WLAN ab und scannt keine Netze in der Nähe. Eigene Namen werden lokal nach SSID gespeichert, ersatzweise nach einem SHA-256-Hash der BSSID, falls nur diese vorliegt. Roh-BSSIDs werden nicht gespeichert oder geteilt. SSID-basierte Profile halten Mesh-Zugangspunkte zusammen; unabhängige Netze mit identischer SSID lassen sich dadurch nicht unterscheiden. Bei einer BSSID-Zuordnung kann ein anderer Mesh-Zugangspunkt ein eigenes Profil benötigen. Öffentliche IP-Adressen und Standortnähe werden nicht als vermeintlich eindeutige WLAN-Kennungen verwendet.

Im Vordergrund wird die WLAN-Erkennung alle drei Sekunden sowie bei Verbindungs- und Berechtigungswechseln aktualisiert. Ein eigener Name ändert den stabilen Rekordschlüssel nicht. Bestehende Ergebnisse mit diesem Schlüssel werden beim Umbenennen angepasst. Ohne Freigabe einer Kennung durch iOS ist automatische Wiedererkennung nicht möglich. Das mitgelieferte Wi-Fi-Entitlement muss beim Sideloading durch ein geeignetes Provisioningprofil autorisiert werden.

Der Bildexport erzeugt mit SwiftUI ImageRenderer eine 1.500 Pixel breite Ergebniskarte. Das iOS-Teilen-Menü erhält das Bild direkt. Netzname, echte Messwerte, Datenmengen, Messprofil, Server und getrennt beschriftete Live-Spitzen stehen auf der Karte. Gespeicherte Koordinaten sind offline verfügbar; ein optionaler Apple-MapKit-Snapshot ergänzt die Vorschau, ohne das Teilen beim Laden zu blockieren. Standort und Notiz sind vor dem Teilen wählbar. Nachrichten werden ausschließlich über die vom Nutzer bediente Ziel-App verschickt.

## Version 2.0: Einblicke und Werkzeuge

Die bisherige Rekorde-Registerkarte wird zu **Einblicke**. Dort bleiben die Rekorde erreichbar; hinzu kommen Statistik, A/B-Vergleich, Router-Labor und Transferzeit-Rechner. Die vollständigen Neuerungen stehen in [CHANGELOG.md](CHANGELOG.md).

**Router-Labor:** Einblicke → Router-Standort finden → Platz benennen → bewusst einen Test starten. Weitere Plätze in derselben Runde messen. Server, Profil und Datenlimit müssen gleich bleiben; Router-Runden starten keine Tests automatisch. Runden werden anhand der Ergebnis-IDs lokal wiedergefunden. Messwerte zeigen die gesamte Strecke inklusive WLAN und Messserver, nicht nur die Mobilfunkverbindung des Routers.

**Verlauf:** Nach rechts wischen oder im Ergebnis den Stern wählen, um einen Favoriten zu markieren. Tags im Ergebnis mit Kommas trennen. Das Filtermenü erlaubt Zeitfenster, Favoriten und Sortierung nach Download, Upload oder Ping. Der A/B-Vergleich verwendet A als Basis für Prozentwerte; bei einer Nullbasis bleibt der Prozentvergleich aus.

**Wiederherstellen:** Einstellungen → JSON-Verlauf wiederherstellen → Datei wählen → Vorschau → Messungen hinzufügen. Der Import akzeptiert die exportierte Version 1 des Ergebnisarchivs mit ISO-8601-Daten. Neue optionale Ergebnisfelder halten ältere Exporte kompatibel. Vorhandene IDs werden nicht überschrieben; die aktuellen Einstellungen bleiben erhalten. Nutzdaten und Stichproben werden vor dem Hinzufügen auf Format, Grenzen und endliche Zahlen geprüft. Der Import überträgt keine Daten an einen Server.

**Auswertung:** Mediane und Zeitverläufe werden aus gespeicherten Ergebnissen berechnet. Ein Netz-/Zeitraumfilter ist keine kontinuierliche Messung des Anschlusses. Einblicke zählen auch Wiederholungsdaten gespeicherter erfolgreicher Tests, aber keine vollständig abgebrochenen Tests oder Protokolldaten. Transferzeiten sind mathematische Schätzungen bei konstantem Tempo und keine Zusage für echte Downloads.

## Version 3.0: Design, RJ Score und Konfetti

Neue Ergebnis-Karten, ein beleuchteter Tacho, die Akzentfarben Jade/Roségold/Elektrisch und animierte Bewertungsbalken ergänzen das native Glasdesign. Die bewährte Glättung des Tachos bleibt erhalten. Der Startknopf steht vor der Versionsübersicht; der Score erscheint nach einer abgeschlossenen Messung direkt darunter.

**RJ Score (RJ-Modell 1)** ist eine ausdrücklich app-eigene Heuristik aus den vorhandenen Messwerten. Gaming gewichtet HTTP-Ping mit 65 %, Jitter mit 25 % und eine gedeckelte Bandbreitenreserve mit 10 %. Die Reserve begrenzt den Gaming-Wert. Streaming gewichtet Download mit 90 % und Jitter mit 10 %, begrenzt durch die Download-Punkte. Videoanrufe kombinieren beidseitige Bandbreitenreserve (60 %), Ping (25 %) und Jitter (15 %), ebenfalls durch die Reserve begrenzt. Download- und Upload-Punkte folgen eigenen monotonen, stückweise linearen Kurven. Alle Stützpunkte, Grenzen und Formeln sind unter „Was bedeuten die Punkte?“ und in `Speedtest/Models/QualityScore.swift` sichtbar.

Kategorien reichen von 1 bis 10. Der Gesamtscore ist der gewichtete Durchschnitt × 10 (Gaming 30 %, Streaming 20 %, Videoanrufe 20 %, Downloads/Uploads je 15 %), gerundet auf ganze Punkte. Bei fehlender vollständiger Messbasis gibt es keine Bewertung. Alte und neue gespeicherte Tests werden mit demselben Modell bewertet. Es gibt keine zusätzlichen Lasttests, keinen Bonus für viele Tests und keine erfundenen Messwerte. Spielserver-Latenz, Paketverlust, Bufferbloat, Auflösung/Codec und Zahl aktiver Geräte sind nicht gemessen und werden nicht als bekannte Tatsachen dargestellt. Gute Punkte garantieren keine störungsfreie Sitzung.

**Konfetti** erscheint einmal für maximal 3,4 Sekunden nach einem neu abgeschlossenen, gespeicherten Test, wenn mindestens 75 Gesamtpunkte oder ein Netzrekord erreicht wurden. In den Einstellungen lässt es sich auf Netzrekorde beschränken oder ausschalten. Der Effekt läuft nicht beim Öffnen alter Ergebnisse, fängt keine Berührungen ab und stoppt beim Verlassen des Vordergrunds. „Animationen aus“ und iOS „Bewegung reduzieren“ deaktivieren ihn.

Der Score erscheint in Ergebnissen, Verlauf, A/B-Vergleich, Router-Labor und als gefilterter Kategorie-Median in den Einblicken. Im Bildexport kann er separat ausgeblendet werden; die Grafik kennzeichnet ihn ebenfalls als Schätzung. Einstellungen aus früheren Versionen behalten kompatible Standardwerte.
