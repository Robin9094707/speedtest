# RJ Speedtest auf deinem iPhone

## Download

Im neuesten erfolgreichen [GitHub-Actions-Lauf](https://github.com/Robin9094707/speedtest/actions/workflows/ios.yml) unter **Artifacts** das Paket **RJ-Speedtest-IPA** herunterladen. Das äußere ZIP entpacken. Darin liegt `RJ-Speedtest.ipa`.

## Installation

Die IPA enthält eine echte native ARM64-iOS-App, ist aber **nicht mit einem Apple-Zertifikat signiert**. iOS installiert sie deshalb nicht einfach beim Antippen. Importiere sie in deinen bereits eingerichteten Sideloading-Signer (z. B. AltStore, SideStore oder Sideloadly), signiere sie mit deinem eigenen Apple-Profil und installiere sie über dessen Ablauf. Die Verfügbarkeit und Laufzeit der Signierung hängen von deinem Profil und dem verwendeten Werkzeug ab. Bei Aufforderung die von iOS verlangte Entwicklerfreigabe einrichten.

Alternativ das Projekt in Xcode 26+ öffnen, das eigene Team wählen, das angeschlossene iPhone als Ziel wählen und „Run“ starten. Ein passendes Signierungsprofil ist für die Geräteinstallation erforderlich. Keine Apple-Passwörter oder Zertifikate ins öffentliche Repository hochladen.

**Voraussetzungen:** iPhone oder iPad mit iOS/iPadOS 17 oder neuer. Liquid Glass wird ab iOS/iPadOS 26 genutzt. Der Build enthält keine Simulator-App.

## Beim ersten Start

1. „Los geht’s“ antippen und nach Wunsch Standort „Beim Verwenden der App“ erlauben.
2. Falls kein WLAN-Name erscheint: auf dem Startbildschirm das Netzprofil antippen und das WLAN benennen. Wenn eine WLAN-Kennung vorliegt, „Namen für dieses WLAN merken“ wählen; künftig wird er automatisch zugeordnet. Ohne Kennung bleibt eine manuelle Auswahl nötig.
3. In den Einstellungen bei Bedarf Datenlimit und Testdauer anpassen.
4. „Speedtest starten“ antippen. Die App geöffnet lassen. Nach Download folgt automatisch Upload.
5. Ergebnisse stehen im Verlauf. Antippen zum Notieren, Teilen oder Löschen; Messungen mit Standort stehen auch auf der Karte.

## Falls etwas nicht klappt

- **Installation abgelehnt:** zuerst Signierung, Provisioning und iOS-Version im Sideloading-Werkzeug prüfen. Die angebotene IPA ist absichtlich unsigniert.
- **WLAN-Name fehlt:** Standort „Beim Verwenden“ mit genauer Position erlauben und die Erkennung im Netzprofil aktualisieren. Die Signatur muss das Entitlement `com.apple.developer.networking.wifi-info` enthalten und das Provisioningprofil muss es erlauben. Das lässt sich durch eine zusätzliche Nachfrage nach „Lokales Netzwerk“ nicht ersetzen. Wenn iOS weder SSID noch BSSID freigibt, kann die App verschiedene WLANs nicht zuverlässig erkennen. Ein manuelles Netzprofil verwenden. Die zusätzliche `Speedtest.entitlements` dokumentiert die optionale Wi-Fi-Berechtigung; nur verwenden, wenn das eigene Provisioningprofil sie unterstützt.
- **Kein Kartenpin:** Standortfreigabe prüfen. Es wird nur eine aktuelle Position mit verwertbarer Genauigkeit gespeichert. Tests ohne Standort bleiben im Verlauf.
- **HTTP-Fehler oder keine Daten:** Verbindung, VPN/Filter und Captive Portal prüfen, später erneut versuchen. Öffentliche Cloudflare-Endpunkte können begrenzen oder ausfallen.
- **Test bricht beim Appwechsel ab:** bewusstes Verhalten; iOS erlaubt keine verlässliche dauerhafte Speedtest-Messung im Hintergrund.
- **Speedtest langsamer als erwartet:** andere Downloads pausieren, dicht am Router testen, ausreichend Datenbudget und mehrere Verbindungen wählen. Ergebnisse hängen auch vom Messserver und der Strecke dorthin ab.

Wenn du einen Fehler meldest: iPhone-Modell, iOS-Version, App-Buildnummer, Sideloading-Werkzeug, Netztyp und genaue Fehlermeldung angeben. Keine privaten Zertifikate oder Apple-Zugangsdaten teilen.

## Ergebnisbild teilen

Nach einem Test „Ergebnis als Bild teilen“ wählen oder ein Ergebnis im Verlauf öffnen. Die Vorschau wird aus den gespeicherten Messwerten als Bild in hoher Auflösung erzeugt. Sie enthält Download, Upload, HTTP-Ping, Jitter, Dauer, Datenmengen, Live-Spitzen und Messserver. Ein gespeicherter Standort erscheint als Koordinaten und, wenn Apple die Karte laden kann, als Kartenausschnitt. Standort und Notiz lassen sich vor dem Teilen ausschalten. „Bild teilen“ öffnet das iOS-Menü für Nachrichten, WhatsApp, AirDrop und weitere Apps. Es wird keine Nachricht automatisch verschickt.

## Neu in Version 2.0

- **Einblicke** bündelt Statistik, Rekorde, A/B-Vergleich, Router-Labor und Transferzeit-Rechner.
- **Verlauf** bietet Favoriten, Tags, Zeitfilter und Sortierungen. Tags im Testergebnis bearbeiten, danach „Notiz und Tags speichern“ wählen.
- **Router-Labor** vergleicht benannte Plätze in selbst gestarteten Runden. Das Datenlimit gilt für jeden einzelnen Test.
- **Karte**: oben rechts Favoriten, Zeitraum, Uploadanzeige und Satellitenbild wählen.
- **Wiederherstellen**: in den Einstellungen einen früher exportierten JSON-Verlauf auswählen, Vorschau ansehen und ergänzen. Bestehende Tests werden nicht überschrieben.
- Bestehende App-Daten bleiben bei einem normalen Update mit derselben App-Kennung und passenden Signierung erhalten. Die App nicht vorher löschen, wenn du deine lokalen Daten behalten möchtest.
