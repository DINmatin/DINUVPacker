/*
    DIN UV xatlas Pack 0.4.6
    Autodesk 3ds Max 2016 / MAXScript bridge for DINUVPacker.exe.

    Packs the existing UV topology or uses xatlas to generate new seams and UVs
    for exactly one selected object containing an Unwrap UVW modifier.
    Existing UV faces are fan-triangulated for packing. Auto Unwrap evaluates a
    real TriMesh and can insert a non-destructive Turn To Mesh below Unwrap so
    every xatlas seam can be represented exactly.
*/

-- Some legacy Max installations have #userIcons redirected to the protected
-- application folder (as on the original MatinsTools workstation). Move that
-- setting to this Max user's writable profile before registering the macro.
try
(
    local dinLocalAppData = systemTools.getEnvVariable "LOCALAPPDATA"
    if dinLocalAppData != undefined do
    (
        local dinMaxRoot = pathConfig.appendPath dinLocalAppData "Autodesk\\3dsMax\\2016 - 64bit"
        local dinProfileDirectories = getDirectories (pathConfig.appendPath dinMaxRoot "*")
        local dinDesiredIconDirectory = undefined
        for dinProfileDirectory in dinProfileDirectories where dinDesiredIconDirectory == undefined do
        (
            local dinInstalledMacro = pathConfig.appendPath dinProfileDirectory "usermacros\\DIN_UV_xatlasPack.mcr"
            if doesFileExist dinInstalledMacro do
                dinDesiredIconDirectory = pathConfig.appendPath dinProfileDirectory "usericons"
        )

        if dinDesiredIconDirectory != undefined do
        (
            local dinOldIconDirectory = getDir #userIcons
            if not doesDirectoryExist dinDesiredIconDirectory do makeDir dinDesiredIconDirectory all:true

            -- Preserve existing custom groups such as matinsTools and bmax.
            if dinOldIconDirectory != undefined and dinOldIconDirectory != dinDesiredIconDirectory and doesDirectoryExist dinOldIconDirectory do
            (
                for dinPattern in #("*.bmp", "*.png") do
                (
                    local dinOldIcons = getFiles (pathConfig.appendPath dinOldIconDirectory dinPattern)
                    for dinOldIcon in dinOldIcons do
                    (
                        local dinNewIcon = pathConfig.appendPath dinDesiredIconDirectory ((getFilenameFile dinOldIcon) + (getFilenameType dinOldIcon))
                        if not doesFileExist dinNewIcon do copyFile dinOldIcon dinNewIcon
                    )
                )
            )

            setDir #userIcons dinDesiredIconDirectory
            colorMan.reInitIcons()
        )
    )
)
catch (format "DINUVPacker: could not initialize the per-user icon path: %\n" (getCurrentException()))

macroScript DIN_UV_xatlasPack
category:"DIN Tools"
tooltip:"DIN UV - Pack Existing Islands with xatlas"
buttonText:"DIN UV xatlas Pack"
icon:#("DINUVPacker", 1)
(
    global DIN_UV_xatlasPack_dialog

    try (destroyDialog DIN_UV_xatlasPack_dialog) catch()

    rollout DIN_UV_xatlasPack_dialog "DIN UV xatlas Pack 0.4.6" width:330
    (
        group "Target Atlas"
        (
            spinner spn_resolution "Resolution:" range:[64,16384,1024] type:#integer fieldWidth:70
            spinner spn_padding "Padding in pixels:" range:[0,256,8] type:#integer fieldWidth:70
        )
        group "Quality"
        (
            checkbox chk_rotate "Rotate islands for packing" checked:true
            checkbox chk_axis "Pre-align islands to convex-hull axis" checked:true
            checkbox chk_bruteforce "Best quality / brute force (slower)" checked:true
            checkbox chk_bilinear "Reserve bilinear-filter border" checked:true
            checkbox chk_blockalign "Align to 4x4 texture blocks" checked:false
        )
        label lbl_scope "Scope: all UV faces of one selected object" align:#left
        button btn_pack "Pack Existing UV Islands" height:32 width:290
        button btn_auto "Auto Unwrap + Pack (Create New Seams)" height:32 width:290
        label lbl_status "Ready" align:#left width:310

        fn DIN_getExecutablePath =
        (
            local localAppData = systemTools.getEnvVariable "LOCALAPPDATA"
            if localAppData == undefined then return undefined
            local maxRoot = pathConfig.appendPath localAppData "Autodesk\\3dsMax\\2016 - 64bit"
            local preferred = pathConfig.appendPath maxRoot "ENU\\usermacros\\DINUVPacker.exe"
            if doesFileExist preferred then return pathConfig.normalizePath preferred

            -- Max 2016's getFiles() does not reliably expand a wildcard in a
            -- parent directory component. Enumerate language profiles first.
            local profileDirectories = getDirectories (pathConfig.appendPath maxRoot "*")
            for profileDirectory in profileDirectories do
            (
                local candidate = pathConfig.appendPath profileDirectory "usermacros\\DINUVPacker.exe"
                if doesFileExist candidate then return pathConfig.normalizePath candidate
            )
            undefined
        )

        fn DIN_getUnwrapModifier node =
        (
            for modifier in node.modifiers where classOf modifier == Unwrap_UVW do return modifier
            undefined
        )

        fn DIN_getModifierIndex node modifier =
        (
            for modifierIndex = 1 to node.modifiers.count where node.modifiers[modifierIndex] == modifier do return modifierIndex
            0
        )

        fn DIN_getUserTempDirectory =
        (
            -- getDir #temp can resolve to the protected 3ds Max installation
            -- directory in Max 2016. Use the Windows user's TEMP/TMP instead.
            local tempDirectory = systemTools.getEnvVariable "TEMP"
            if tempDirectory == undefined or tempDirectory == "" do
                tempDirectory = systemTools.getEnvVariable "TMP"
            if tempDirectory == undefined or tempDirectory == "" do
            (
                local localAppData = systemTools.getEnvVariable "LOCALAPPDATA"
                if localAppData != undefined and localAppData != "" do
                    tempDirectory = pathConfig.appendPath localAppData "Temp"
            )
            if tempDirectory == undefined or tempDirectory == "" then undefined
            else pathConfig.normalizePath tempDirectory
        )

        fn DIN_readTextFile path =
        (
            if not doesFileExist path then return ""
            local stream = openFile path mode:"rt"
            if stream == undefined then return ""
            local text = ""
            while not eof stream do text += (readLine stream) + "\n"
            close stream
            text
        )

        -- The exchange format always uses a decimal point, independent of the
        -- Windows/3ds Max locale (important on German and Swedish systems).
        fn DIN_floatToken value =
        (
            substituteString (formattedPrint value format:"1.9f") "," "."
        )

        fn DIN_findUvIslands node unwrapModifier vertexCount faceCount =
        (
            -- Connected components of the existing UV-index topology. Their
            -- IDs are passed as xatlas face materials so stacked but separate
            -- islands cannot be merged into one chart.
            local faceVertices = #()
            faceVertices.count = faceCount
            local vertexFaces = #()
            vertexFaces.count = vertexCount
            for vertexIndex = 1 to vertexCount do vertexFaces[vertexIndex] = #()

            for faceIndex = 1 to faceCount do
            (
                local degree = unwrapModifier.unwrap6.numberPointsInFaceByNode faceIndex node
                local vertices = #()
                for corner = 1 to degree do
                (
                    local vertexIndex = unwrapModifier.unwrap6.getVertexIndexFromFaceByNode faceIndex corner node
                    append vertices vertexIndex
                    appendIfUnique vertexFaces[vertexIndex] faceIndex
                )
                faceVertices[faceIndex] = vertices
            )

            local islandIds = #()
            islandIds.count = faceCount
            for faceIndex = 1 to faceCount do islandIds[faceIndex] = 0
            local islandCount = 0
            for seedFace = 1 to faceCount where islandIds[seedFace] == 0 do
            (
                islandCount += 1
                local queue = #(seedFace)
                local queueIndex = 1
                islandIds[seedFace] = islandCount
                while queueIndex <= queue.count do
                (
                    local currentFace = queue[queueIndex]
                    queueIndex += 1
                    for vertexIndex in faceVertices[currentFace] do
                    (
                        for neighbourFace in vertexFaces[vertexIndex] where islandIds[neighbourFace] == 0 do
                        (
                            islandIds[neighbourFace] = islandCount
                            append queue neighbourFace
                        )
                    )
                )
            )
            #(islandIds, islandCount)
        )

        fn DIN_writeInput path node unwrapModifier =
        (
            local vertexCount = unwrapModifier.unwrap6.numberVerticesByNode node
            local faceCount = unwrapModifier.unwrap6.numberPolygonsByNode node
            if vertexCount < 3 or faceCount < 1 then throw "The Unwrap UVW modifier contains no usable UV topology."

            local triangleCount = 0
            for faceIndex = 1 to faceCount do
            (
                local degree = unwrapModifier.unwrap6.numberPointsInFaceByNode faceIndex node
                if degree < 3 then throw ("Invalid UV face degree at face " + faceIndex as string)
                triangleCount += degree - 2
            )
            local islandInfo = DIN_findUvIslands node unwrapModifier vertexCount faceCount
            local faceIslandIds = islandInfo[1]

            local stream = createFile path
            if stream == undefined then throw ("Cannot create xatlas input file: " + path)
            format "DINUVPACK 2\n" to:stream
            format "resolution %\n" spn_resolution.value to:stream
            format "padding %\n" spn_padding.value to:stream
            format "texels_per_unit 0\n" to:stream
            format "bilinear %\n" (if chk_bilinear.checked then 1 else 0) to:stream
            format "block_align %\n" (if chk_blockalign.checked then 1 else 0) to:stream
            format "brute_force %\n" (if chk_bruteforce.checked then 1 else 0) to:stream
            format "rotate_charts %\n" (if chk_rotate.checked then 1 else 0) to:stream
            format "rotate_to_axis %\n" (if chk_axis.checked then 1 else 0) to:stream
            format "mesh_count 1\n" to:stream
            format "mesh 0 % %\n" vertexCount triangleCount to:stream

            for vertexIndex = 1 to vertexCount do
            (
                local position = unwrapModifier.unwrap6.getVertexPositionByNode currentTime vertexIndex node
                format "uv % % %\n" (vertexIndex - 1) (DIN_floatToken position.x) (DIN_floatToken position.y) to:stream
            )

            local triangleIndex = 0
            for faceIndex = 1 to faceCount do
            (
                local degree = unwrapModifier.unwrap6.numberPointsInFaceByNode faceIndex node
                local firstVertex = unwrapModifier.unwrap6.getVertexIndexFromFaceByNode faceIndex 1 node
                for corner = 2 to (degree - 1) do
                (
                    local secondVertex = unwrapModifier.unwrap6.getVertexIndexFromFaceByNode faceIndex corner node
                    local thirdVertex = unwrapModifier.unwrap6.getVertexIndexFromFaceByNode faceIndex (corner + 1) node
                    format "tri % % % % %\n" triangleIndex (firstVertex - 1) (secondVertex - 1) (thirdVertex - 1) (faceIslandIds[faceIndex] - 1) to:stream
                    triangleIndex += 1
                )
            )
            format "endmesh\nend\n" to:stream
            close stream
            #(vertexCount, faceCount, triangleCount, islandInfo[2])
        )

        fn DIN_writeAutoInput path node unwrapModifier =
        (
            local geometry = snapshotAsMesh node
            if geometry == undefined or geometry.numverts < 3 or geometry.numfaces < 1 then throw "Could not evaluate the selected object's triangle geometry."
            local vertexCount = geometry.numverts
            local faceCount = geometry.numfaces
            local triangleCount = faceCount
            local faceDegrees = #()
            faceDegrees.count = faceCount
            local triangleGeometryFaces = #()
            triangleGeometryFaces.count = faceCount
            for faceIndex = 1 to faceCount do
            (
                faceDegrees[faceIndex] = 3
                triangleGeometryFaces[faceIndex] = getFace geometry faceIndex
            )

            local stream = createFile path
            if stream == undefined then throw ("Cannot create xatlas input file: " + path)
            format "DINUVPACK 3\nmode auto\n" to:stream
            format "resolution %\n" spn_resolution.value to:stream
            format "padding %\n" spn_padding.value to:stream
            format "texels_per_unit 0\n" to:stream
            format "bilinear %\n" (if chk_bilinear.checked then 1 else 0) to:stream
            format "block_align %\n" (if chk_blockalign.checked then 1 else 0) to:stream
            format "brute_force %\n" (if chk_bruteforce.checked then 1 else 0) to:stream
            format "rotate_charts %\n" (if chk_rotate.checked then 1 else 0) to:stream
            format "rotate_to_axis %\n" (if chk_axis.checked then 1 else 0) to:stream
            format "mesh_count 1\nmesh 0 % %\n" vertexCount triangleCount to:stream

            for vertexIndex = 1 to vertexCount do
            (
                local position = getVert geometry vertexIndex
                format "pos % % % %\n" (vertexIndex - 1) (DIN_floatToken position.x) (DIN_floatToken position.y) (DIN_floatToken position.z) to:stream
            )

            for faceIndex = 1 to faceCount do
            (
                local triangle = triangleGeometryFaces[faceIndex]
                format "tri % % % %\n" (faceIndex - 1) ((triangle.x as integer) - 1) ((triangle.y as integer) - 1) ((triangle.z as integer) - 1) to:stream
            )
            format "endmesh\nend\n" to:stream
            close stream
            geometry = undefined
            #(vertexCount, faceCount, triangleCount, faceDegrees, triangleGeometryFaces)
        )

        fn DIN_prepareAutoTriangleTopology node unwrapModifier expectedFaces =
        (
            local faceCount = unwrapModifier.unwrap6.numberPolygonsByNode node
            local alreadyTriangles = faceCount == expectedFaces.count
            if alreadyTriangles do
            (
                for faceIndex = 1 to faceCount while alreadyTriangles do
                    if unwrapModifier.unwrap6.numberPointsInFaceByNode faceIndex node != 3 do alreadyTriangles = false
            )

            local triangleModifier = undefined
            if not alreadyTriangles do
            (
                local unwrapIndex = DIN_getModifierIndex node unwrapModifier
                if unwrapIndex < 1 then throw "Could not locate the Unwrap UVW modifier in the stack."
                triangleModifier = Turn_to_Mesh()
                triangleModifier.name = "DIN xatlas Auto Triangulate"
                triangleModifier.useInvisibleEdges = true
                triangleModifier.selectionConversion = 1
                addModifier node triangleModifier before:unwrapIndex
                faceCount = unwrapModifier.unwrap6.numberPolygonsByNode node
            )

            if faceCount != expectedFaces.count then
                throw ("Triangulated stack topology mismatch: expected " + expectedFaces.count as string + " faces, got " + faceCount as string + ".")
            for faceIndex = 1 to faceCount do
            (
                if unwrapModifier.unwrap6.numberPointsInFaceByNode faceIndex node != 3 then
                    throw ("Face " + faceIndex as string + " is still not triangular after stack conversion.")
                local expected = expectedFaces[faceIndex]
                for corner = 1 to 3 do
                (
                    local actualIndex = unwrapModifier.unwrap6.getVertexGeomIndexFromFaceByNode faceIndex corner node
                    local expectedIndex = (if corner == 1 then expected.x else if corner == 2 then expected.y else expected.z) as integer
                    if actualIndex != expectedIndex then
                        throw ("Triangle order mismatch at face " + faceIndex as string + ". No UV topology was applied.")
                )
            )
            triangleModifier
        )

        fn DIN_parseResult path expectedVertexCount =
        (
            local stream = openFile path mode:"rt"
            if stream == undefined then throw ("Cannot read xatlas result: " + path)
            local packedPositions = #()
            packedPositions.count = expectedVertexCount
            local atlasCount = 0
            local chartCount = 0
            local atlasWidth = 0
            local atlasHeight = 0
            local duplicateConflict = false

            while not eof stream do
            (
                local line = readLine stream
                local parts = filterString line " \t"
                if parts.count > 0 do
                (
                    case parts[1] of
                    (
                        "atlas_width": if parts.count >= 2 do atlasWidth = parts[2] as integer
                        "atlas_height": if parts.count >= 2 do atlasHeight = parts[2] as integer
                        "atlas_count": if parts.count >= 2 do atlasCount = parts[2] as integer
                        "chart_count": if parts.count >= 2 do chartCount = parts[2] as integer
                        "vertex":
                        (
                            if parts.count < 7 then throw "Malformed vertex line in xatlas result."
                            local xref = (parts[3] as integer) + 1
                            local vertexAtlas = parts[4] as integer
                            if xref >= 1 and xref <= expectedVertexCount and vertexAtlas >= 0 do
                            (
                                local position = [parts[6] as float, parts[7] as float, 0]
                                if packedPositions[xref] == undefined then packedPositions[xref] = position
                                else if distance packedPositions[xref] position > 0.00001 do duplicateConflict = true
                            )
                        )
                        default:()
                    )
                )
            )
            close stream

            if atlasCount != 1 then throw ("This bridge currently requires exactly one atlas; xatlas returned " + atlasCount as string + ".")
            if atlasWidth <= 0 or atlasHeight <= 0 then throw "xatlas returned an invalid atlas size."
            if duplicateConflict then throw "xatlas split one input UV vertex into different chart positions. No scene changes were applied."

            local positionedCount = 0
            for position in packedPositions where position != undefined do positionedCount += 1
            if positionedCount == 0 then throw "xatlas returned no mapped UV vertices."
            #(packedPositions, atlasWidth, atlasHeight, chartCount, positionedCount)
        )

        fn DIN_applyPositions node unwrapModifier packedPositions =
        (
            local lastChanged = 0
            for vertexIndex = 1 to packedPositions.count where packedPositions[vertexIndex] != undefined do
            (
                local oldPosition = unwrapModifier.unwrap6.getVertexPositionByNode currentTime vertexIndex node
                local newPosition = [packedPositions[vertexIndex].x, packedPositions[vertexIndex].y, oldPosition.z]
                unwrapModifier.unwrap6.setVertexPosition2ByNode currentTime vertexIndex newPosition false false node
                lastChanged = vertexIndex
            )
            if lastChanged > 0 do
            (
                local oldPosition = unwrapModifier.unwrap6.getVertexPositionByNode currentTime lastChanged node
                local finalPosition = [packedPositions[lastChanged].x, packedPositions[lastChanged].y, oldPosition.z]
                unwrapModifier.unwrap6.setVertexPosition2ByNode currentTime lastChanged finalPosition false true node
            )
            lastChanged
        )

        fn DIN_parseAutoResult path =
        (
            local stream = openFile path mode:"rt"
            if stream == undefined then throw ("Cannot read xatlas result: " + path)
            local packedPositions = #()
            local outputIndices = #()
            local atlasCount = 0
            local chartCount = 0
            local atlasWidth = 0
            local atlasHeight = 0
            local expectedVertexCount = 0
            local expectedIndexCount = 0
            local degenerateVertexCount = 0

            while not eof stream do
            (
                local line = readLine stream
                local parts = filterString line " \t"
                if parts.count > 0 do
                (
                    case parts[1] of
                    (
                        "atlas_width": if parts.count >= 2 do atlasWidth = parts[2] as integer
                        "atlas_height": if parts.count >= 2 do atlasHeight = parts[2] as integer
                        "atlas_count": if parts.count >= 2 do atlasCount = parts[2] as integer
                        "chart_count": if parts.count >= 2 do chartCount = parts[2] as integer
                        "mesh":
                        (
                            if parts.count < 6 then throw "Malformed mesh line in xatlas result."
                            expectedVertexCount = parts[4] as integer
                            expectedIndexCount = parts[5] as integer
                            packedPositions = #()
                            outputIndices = #()
                        )
                        "vertex":
                        (
                            if parts.count < 7 then throw "Malformed vertex line in xatlas result."
                            local outputVertex = (parts[2] as integer) + 1
                            local vertexAtlas = parts[4] as integer
                            if outputVertex != packedPositions.count + 1 or outputVertex > expectedVertexCount then throw "xatlas output vertices are not contiguous and ordered."
                            append packedPositions (if vertexAtlas >= 0 then [parts[6] as float, parts[7] as float, 0] else undefined)
                        )
                        "index":
                        (
                            if parts.count < 3 then throw "Malformed index line in xatlas result."
                            local indexSlot = (parts[2] as integer) + 1
                            local outputVertex = (parts[3] as integer) + 1
                            if indexSlot != outputIndices.count + 1 or indexSlot > expectedIndexCount then throw "xatlas output indices are not contiguous and ordered."
                            if outputVertex < 1 or outputVertex > expectedVertexCount then throw "xatlas returned an invalid indexed vertex."
                            append outputIndices outputVertex
                        )
                        default:()
                    )
                )
            )
            close stream

            if atlasCount != 1 then throw ("This bridge currently requires exactly one atlas; xatlas returned " + atlasCount as string + ".")
            if atlasWidth <= 0 or atlasHeight <= 0 or chartCount < 1 then throw "xatlas returned incomplete auto-unwrap metadata."
            if expectedVertexCount < 3 or expectedIndexCount < 3 then throw "xatlas returned no usable auto-unwrap topology."
            if packedPositions.count != expectedVertexCount then throw ("xatlas returned " + packedPositions.count as string + " of " + expectedVertexCount as string + " expected output vertices.")
            if outputIndices.count != expectedIndexCount then throw ("xatlas returned " + outputIndices.count as string + " of " + expectedIndexCount as string + " expected indices.")
            local referencedVertices = #{}
            referencedVertices.count = expectedVertexCount
            for outputVertex in outputIndices do referencedVertices[outputVertex] = true
            -- xatlas intentionally leaves vertices belonging only to zero-area
            -- triangles without an atlas position. Such geometry has no useful
            -- UV area, so collapse only those UV corners instead of aborting the
            -- complete unwrap of the otherwise valid mesh.
            for outputVertex = 1 to expectedVertexCount where referencedVertices[outputVertex] and packedPositions[outputVertex] == undefined do
            (
                packedPositions[outputVertex] = [0, 0, 0]
                degenerateVertexCount += 1
            )
            #(packedPositions, outputIndices, atlasWidth, atlasHeight, chartCount, degenerateVertexCount)
        )

        fn DIN_buildFaceOutputMap faceDegrees outputIndices =
        (
            local faceMap = #()
            faceMap.count = faceDegrees.count
            local triangleOffset = 0
            for faceIndex = 1 to faceDegrees.count do
            (
                local degree = faceDegrees[faceIndex]
                local cornerMap = #()
                cornerMap.count = degree
                for fanTriangle = 0 to (degree - 3) do
                (
                    local baseIndex = (triangleOffset + fanTriangle) * 3
                    local originalCorners = #(1, fanTriangle + 2, fanTriangle + 3)
                    for triangleCorner = 1 to 3 do
                    (
                        local originalCorner = originalCorners[triangleCorner]
                        local outputVertex = outputIndices[baseIndex + triangleCorner]
                        if cornerMap[originalCorner] == undefined then cornerMap[originalCorner] = outputVertex
                        else if cornerMap[originalCorner] != outputVertex then
                            throw ("xatlas created a seam inside polygon face " + faceIndex as string + ". Triangulate that face before Auto Unwrap.")
                    )
                )
                faceMap[faceIndex] = cornerMap
                triangleOffset += degree - 2
            )
            if triangleOffset * 3 != outputIndices.count then throw "xatlas output topology does not match the exported faces."
            faceMap
        )

        fn DIN_applyAutoTopology node unwrapModifier packedPositions faceMap =
        (
            local uvVertexByOutput = #()
            uvVertexByOutput.count = packedPositions.count
            for faceIndex = 1 to faceMap.count do
            (
                for corner = 1 to faceMap[faceIndex].count do
                (
                    local outputVertex = faceMap[faceIndex][corner]
                    local uvVertex = uvVertexByOutput[outputVertex]
                    if uvVertex == undefined then
                    (
                        unwrapModifier.unwrap6.setFaceVertexByNode packedPositions[outputVertex] faceIndex corner false node
                        uvVertex = unwrapModifier.unwrap6.getVertexIndexFromFaceByNode faceIndex corner node
                        uvVertexByOutput[outputVertex] = uvVertex
                    )
                    else
                    (
                        unwrapModifier.unwrap6.setFaceVertexIndexByNode faceIndex corner uvVertex node
                    )
                )
            )

            local lastChanged = 0
            for outputVertex = 1 to uvVertexByOutput.count where uvVertexByOutput[outputVertex] != undefined do
            (
                unwrapModifier.unwrap6.setVertexPosition2ByNode currentTime uvVertexByOutput[outputVertex] packedPositions[outputVertex] false false node
                lastChanged = uvVertexByOutput[outputVertex]
            )
            if lastChanged > 0 do
            (
                local finalOutput = findItem uvVertexByOutput lastChanged
                unwrapModifier.unwrap6.setVertexPosition2ByNode currentTime lastChanged packedPositions[finalOutput] false true node
            )

            local currentVertexCount = unwrapModifier.unwrap6.numberVerticesByNode node
            local usedVertices = #{}
            usedVertices.count = currentVertexCount
            for faceIndex = 1 to faceMap.count do
                for corner = 1 to faceMap[faceIndex].count do
                    usedVertices[unwrapModifier.unwrap6.getVertexIndexFromFaceByNode faceIndex corner node] = true
            for vertexIndex = 1 to currentVertexCount where not usedVertices[vertexIndex] do
                unwrapModifier.unwrap6.markAsDeadByNode vertexIndex node
            lastChanged
        )

        on chk_rotate changed state do chk_axis.enabled = state

        fn DIN_runOperation autoUnwrap =
        (
            if selection.count != 1 then
            (
                messageBox "Select exactly one object containing an Unwrap UVW modifier." title:"DIN UV xatlas Pack"
                return false
            )

            local node = selection[1]
            local unwrapModifier = DIN_getUnwrapModifier node
            if unwrapModifier == undefined then
            (
                messageBox "The selected object has no Unwrap UVW modifier." title:"DIN UV xatlas Pack"
                return false
            )

            if autoUnwrap and not (queryBox "Auto Unwrap replaces the existing UV topology and creates new seams.\n\nFor polygon objects it may add a non-destructive 'DIN xatlas Auto Triangulate' modifier below Unwrap so all seams can be represented.\n\nContinue?\n\n(The operation can be undone.)" title:"DIN UV xatlas Pack") then return false

            local executable = DIN_getExecutablePath()
            if executable == undefined or not doesFileExist executable then
            (
                local executableMessage = if executable == undefined then "No DINUVPacker.exe was found in a Max 2016 user profile." else executable
                messageBox ("DINUVPacker.exe was not found:\n" + executableMessage) title:"DIN UV xatlas Pack"
                return false
            )

            local token = timestamp() as string
            local tempDirectory = DIN_getUserTempDirectory()
            if tempDirectory == undefined or not doesDirectoryExist tempDirectory then
            (
                messageBox "No writable Windows user TEMP directory was found." title:"DIN UV xatlas Pack"
                return false
            )
            local inputPath = pathConfig.appendPath tempDirectory ("DINUVPack_" + token + ".dinuv")
            local outputPath = pathConfig.appendPath tempDirectory ("DINUVPack_" + token + ".result")
            local logPath = pathConfig.appendPath tempDirectory ("DINUVPack_" + token + ".log")
            local operationSucceeded = false

            try
            (
                lbl_status.text = if autoUnwrap then "Exporting 3D topology..." else "Exporting UV topology..."
                local topologyInfo = if autoUnwrap then (DIN_writeAutoInput inputPath node unwrapModifier) else (DIN_writeInput inputPath node unwrapModifier)
                if doesFileExist outputPath do deleteFile outputPath
                if doesFileExist logPath do deleteFile logPath

                lbl_status.text = if autoUnwrap then "Auto unwrapping with xatlas..." else "Packing with xatlas..."
                local command = "\"" + executable + "\" \"" + inputPath + "\" \"" + outputPath + "\" > \"" + logPath + "\" 2>&1"
                local exitCode = -1
                hiddenDOSCommand command startpath:(getFilenamePath executable) prompt:"DIN xatlas packing..." donotwait:false exitCode:&exitCode
                if exitCode != 0 then throw ("DINUVPacker failed with exit code " + exitCode as string + ".\n\n" + DIN_readTextFile logPath)
                if not doesFileExist outputPath then throw "DINUVPacker did not create a result file."

                local result = if autoUnwrap then (DIN_parseAutoResult outputPath) else (DIN_parseResult outputPath topologyInfo[1])
                lbl_status.text = if autoUnwrap then "Applying new UV topology..." else "Applying packed UVs..."
                local undoLabel = if autoUnwrap then "DIN xatlas Auto Unwrap" else "DIN xatlas Pack UV Islands"
                undo undoLabel on
                (
                    if autoUnwrap then
                    (
                        DIN_prepareAutoTriangleTopology node unwrapModifier topologyInfo[5]
                        local faceMap = DIN_buildFaceOutputMap topologyInfo[4] result[2]
                        DIN_applyAutoTopology node unwrapModifier result[1] faceMap
                    )
                    else
                    (
                        DIN_applyPositions node unwrapModifier result[1]
                    )
                )
                completeRedraw()
                if autoUnwrap then
                (
                    local degenerateNote = if result[6] > 0 then (", " + result[6] as string + " degenerate UV vertices collapsed") else ""
                    lbl_status.text = ("Done: " + result[5] as string + " new charts, " + result[1].count as string + " UV vertices, " + result[3] as string + "x" + result[4] as string + degenerateNote)
                )
                else
                    lbl_status.text = ("Done: " + topologyInfo[4] as string + " islands / " + result[4] as string + " charts, " + result[5] as string + " UV vertices, " + result[2] as string + "x" + result[3] as string)
                format "DIN UV xatlas Pack: %\n" lbl_status.text
                operationSucceeded = true
            )
            catch
            (
                local errorText = getCurrentException()
                lbl_status.text = "Failed - see message"
                messageBox ("Packing failed:\n\n" + errorText) title:"DIN UV xatlas Pack"
            )

            if operationSucceeded do
            (
                if doesFileExist inputPath do deleteFile inputPath
                if doesFileExist outputPath do deleteFile outputPath
                if doesFileExist logPath do deleteFile logPath
            )
            operationSucceeded
        )

        on btn_pack pressed do DIN_runOperation false
        on btn_auto pressed do DIN_runOperation true
    )

    createDialog DIN_UV_xatlasPack_dialog style:#(#style_titlebar, #style_sysmenu, #style_toolwindow)
)
