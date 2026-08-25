# DINUVPacker

Windows UV packing and automatic unwrapping tool for Autodesk 3ds Max 2016.
It can either preserve and pack existing UV islands or let the MIT-licensed xatlas
library generate new charts, seams and UVs from the evaluated triangle geometry.

![DINUVPacker icon](assets/icons/DINUVPacker.png)

## Install a release

1. Download and fully extract `DINUVPacker-0.4.8-Max2016-win64.zip`.
2. Double-click `Install.cmd`.
3. Restart 3ds Max when convenient so the MacroScript and toolbar icon are loaded.

### Make the toolbar icon visible in 3ds Max 2016

1. Restart 3ds Max after installation; Max 2016 loads legacy icon groups at startup.
2. Open **Customize > Customize User Interface > Toolbars**.
3. Select category **DIN Tools**.
4. Drag **DIN UV xatlas Pack** onto an existing or new toolbar.
5. If a blank DIN button from an older installation already exists, remove it and
   drag the action onto the toolbar again.

The installer automatically points Max's **Additional Icons** directory to the
writable per-user `usericons` folder and preserves existing custom groups such as
MatinsTools. If the `DINUVPacker` image group still does not appear, run this in
the MAXScript Listener after replacing `<USER>` and `<LANG>` (usually `ENU`):

```maxscript
setDir #userIcons @"C:\Users\<USER>\AppData\Local\Autodesk\3dsMax\2016 - 64bit\<LANG>\usericons"
colorMan.reInitIcons()
```

Close and reopen **Edit Macro Button** after reloading the groups. Its **Group**
list should now contain `DINUVPacker`.

The installer needs no administrator rights. It locates the per-user Max 2016
language profile, creates dated backups of existing files, copies the MacroScript,
helper executable and legacy Max toolbar bitmaps, then verifies every copy with
SHA-256. If several profiles exist, it asks which one to use.
It also archives an obsolete category-prefixed duplicate created by some manual
MacroScript workflows, because that duplicate can override the current icon.
For Max installations with a redirected `#userIcons` path, the legacy bitmap
pairs are also installed beside the MacroScript, which is another documented
icon lookup location.
At MacroScript load time, an application-folder `#userIcons` setting is migrated
to the writable per-user profile after preserving existing custom icon groups.
The installer also updates only the corresponding `Additional Icons` value in
the UTF-16LE Max user INI and keeps a dated backup of that configuration.
Existing custom BMP/PNG groups are first migrated from the previous icon path,
including the classic application `usericons` folder, without modifying it.

## Build

Clone the xatlas submodule and use a MinGW-w64 `g++.exe` on `PATH`, or place a
portable toolchain below `.tools/mingw`:

```powershell
git submodule update --init --recursive
.\build.ps1
```

Output: `bin/DINUVPacker.exe`

## Command line

```text
DINUVPacker.exe input.dinuv output.dinuvresult
```

The text format is deliberately simple so MAXScript 2016 can write and parse it
without a JSON dependency. Input UV and triangle indices are zero-based. Output
contains normalized coordinates plus complete xatlas output topology (`xref` and
output index array), allowing the Max bridge to handle chart vertex duplication.

## 3ds Max 2016

For a manual installation, copy both files to the per-user `usermacros` directory:

- `bin/DINUVPacker.exe`
- `maxscript/DIN_UV_xatlasPack.mcr`

After the next 3ds Max start, run **DIN UV xatlas Pack** from category
**DIN Tools**, or assign it to a shortcut. Select exactly one object with an
**Unwrap UVW** modifier. **Pack Existing UV Islands** preserves seams and only
repacks. **Auto Unwrap + Pack** analyzes the 3D geometry, generates new seams
and UV vertices with xatlas, and replaces the modifier's UV topology inside a
single undoable operation.

The reliable xatlas path is triangle input. Auto Unwrap evaluates the object's
TriMesh and, when the Unwrap input still contains polygons, adds a non-destructive
`DIN xatlas Auto Triangulate` (`Turn To Mesh`) modifier directly below Unwrap.
This preserves the rendered shape while allowing every xatlas seam to be stored
exactly. The stack insertion and UV replacement share one undo operation.
If xatlas needs to split a shared UV vertex, the bridge aborts without applying
scene changes instead of silently damaging the mapping.

The toolbar artwork is supplied in the legacy Max 2016 bitmap/alpha-mask pairs
(`DINUVPacker_16i/16a.bmp` and `DINUVPacker_24i/24a.bmp`) and is referenced by the
MacroScript as `icon:#("DINUVPacker", 1)`.

## Current status

- xatlas dependency vendored and licensed.
- Existing UV mesh ingestion.
- Multi-mesh atlas packing.
- Padding, target resolution, texel density, bilinear, block alignment,
  brute-force quality and rotation controls.
- Strict input validation and deterministic text result.
- MaxScript 2016 bridge with undo support and locale-independent exchange data.
- Topological UV-island IDs are supplied through xatlas face materials, so
  stacked but disconnected islands are packed as separate, non-overlapping charts.
- Auto unwrap mode uses xatlas `AddMesh` to generate charts, parameterize them,
  pack the atlas, and rebuild the Unwrap modifier's UV vertex/face topology.
