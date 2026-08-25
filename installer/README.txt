DINUVPacker 0.4.8 fuer Autodesk 3ds Max 2016 (64-bit)
=========================================================

Installation
------------
1. ZIP vollstaendig entpacken.
2. Install.cmd doppelklicken.
3. Falls mehrere Max-2016-Sprachprofile vorhanden sind, das gewuenschte Profil waehlen.
4. 3ds Max beim naechsten passenden Zeitpunkt neu starten.

Der Installer benoetigt keine Administratorrechte und schreibt ausschliesslich in
das Autodesk-Benutzerprofil unter %LOCALAPPDATA%. Vorhandene Dateien werden als
datierte .backup-Dateien gesichert. Jede kopierte Datei wird per SHA-256 geprueft.

In 3ds Max
-----------
1. 3ds Max nach der Installation neu starten.
2. Customize > Customize User Interface > Toolbars oeffnen.
3. Kategorie DIN Tools waehlen.
4. DIN UV xatlas Pack auf eine Toolbar ziehen.
5. Einen alten leeren DIN-Button vorher entfernen und neu hinzufuegen.

Der Installer stellt Additional Icons automatisch auf den beschreibbaren
Benutzerordner um und uebernimmt vorhandene MatinsTools-/BMAX-Icongruppen.

Macro: DIN UV xatlas Pack

Pack Existing UV Islands behaelt vorhandene Seams bei.
Auto Unwrap + Pack erzeugt neue Seams und UVs und ist ueber Undo rueckgaengig.

Projekt und Quellcode: https://github.com/DINmatin/DINUVPacker
xatlas: https://github.com/jpcy/xatlas (MIT-Lizenz)
