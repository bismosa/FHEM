Dies sind meine Erweiterungen für die Haussteuerung FHEM

Alle aufgeführten Module sind nur als Beispiel zu verstehen. Ich kann nicht für eine Fehlerfreiheit garantieren!
Vor der Benutzung in einem Produktivsystem müssen diese Module gründlich getestet werden! 

# Alle Module
<b>Auf Updates prüfen (update check):</b>

`update check https://raw.githubusercontent.com/bismosa/FHEM/master/controls_all.txt`

<b>Auf die neueste Version updaten (update all):</b>

`update all https://raw.githubusercontent.com/bismosa/FHEM/master/controls_all.txt`

<b>Alle meine Module zum regulären FHEM Updateprozess hinzufügen (update add):</b>

`update add https://raw.githubusercontent.com/bismosa/FHEM/master/controls_all.txt`

`update check`

`update all`

# Blitzer:
Dieses Modul such anhand der Koordinaten die aktuellen Blitzerdaten von www.verkehrslage.de heraus und erstellt einen Text, der in FTUI dargestellt werden kann
Dies ist nur zu demonstrationszwecken gedacht. Bitte die Bedingungen von www.verkehrslage.de beachten

<b>Nur Modul Blitzer installieren:</b>

`update all https://raw.githubusercontent.com/bismosa/FHEM/master/controls_Blitzer.txt`

# MAX_Temperatur:
Dieses Modul erweitert die MAX-Heizkörpersteuerung um weitere Einstellmöglichkeiten.
Möglichkeiten:<br>
		- Setzen der Temperatur für ein oder mehrere Heizkörperthermostate.<br>
		- Setzen der Temperatur und der Zeit (Urlaubsmodus).<br>
		- Gruppen können für dieses Modul festgelegt werden.<br>
		- Es können einzelne Devices hinzugefügt oder auch ausgeschlossen werden.<br>
		- Das Layout für die Auswahlfelder kann beliebig angepasst werden.<br>

<b>Nur Modul MAX_Temperatur installieren:</b>

`update all https://raw.githubusercontent.com/bismosa/FHEM/master/controls_MAX_Temperatur.txt`
