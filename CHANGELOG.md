# RJ Speedtest 2.0.0

Ein großes Funktionsupdate mit neuer Einblicke-Navigation und Werkzeugen für wiederholbare Vergleiche.

- Einblicke: Median von Download, Upload und HTTP-Ping, Verlaufsgrafik, Datenverbrauch sowie Netz- und Zeitfilter. Die Grafik zeigt die letzten 200 Tests im Filter; Zusammenfassungen verwenden alle gefilterten Tests.
- A/B-Vergleich: zwei Messungen auswählen, Basis tauschen, absolute und relative Unterschiede anzeigen. Server, Profil, Dauer und Datenlimit helfen bei der Einordnung.
- Router-Labor: Plätze benennen, Messungen bewusst einzeln starten, Runden aufbewahren und die höchste gemessene Downloadrate hervorheben. Server, Datenlimit und Profil müssen innerhalb einer Runde gleich bleiben. Jeder Test hat das bestehende Datenbudget; es gibt keine automatischen Testserien.
- Verlauf: Favoriten, bis zu zwölf Tags, Suche nach Netz, Server, Platz, Notiz und Tags. Nach Download, Upload oder Ping sortieren und Zeiträume filtern.
- Transferzeit-Rechner: Download-/Uploaddauer für 1–200 GB aus echten gespeicherten Messwerten schätzen, ohne Netzwerk-Lasttest.
- Wiederherstellung: frühere JSON-Verlaufsexporte mit Vorschau importieren, IDs deduplizieren und Daten lokal ergänzen. Maximal 40 MB und 10.000 Tests pro Datei. Vorhandene Messungen und Einstellungen werden nicht ersetzt.
- Karte: Favoriten, Zeiträume, Uploadwerte und Satellitenansicht.
- Dashboard: Tagesübersicht, Favoritenanzahl und Übersicht aller Neuerungen.
- Ergebnisansicht: Favoriten, Tags, Vergleichseinstieg und Platzname; Platznamen erscheinen auch im Ergebnisbild.
- Neue Ergebnisse speichern Datenlimit und Serverkennung zusätzlich zur bisherigen Serverbezeichnung.

## Hinweise

Vorhandene Ergebnis- und Einstellungsdateien bleiben kompatibel; neue Ergebnisfelder sind optional. Einblicke aggregieren nur gespeicherte Tests und sind keine Messung des gesamten Router-Datenverbrauchs. Abgebrochene Tests fehlen. Einzelmessungen und Live-Spitzen beweisen keine dauerhafte Verbesserung. WLAN-Erkennung und Signierung haben weiterhin die dokumentierten iOS-Beschränkungen.

Die IPA wird in GitHub Actions kompiliert und als unsigniertes ARM64-Paket bereitgestellt. Auf ausdrücklichen Nutzerwunsch werden bei diesem Update keine Unit-, UI-, Simulator- oder Live-Speedtests ausgeführt.
