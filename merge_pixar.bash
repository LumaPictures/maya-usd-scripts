set -e

# change to git root dir
cd "$(git rev-parse --show-toplevel)"

# Some commit reference points:

# 4b46bfd3b5ea96c709547e830bb645d60c21fa29 - plugins/USD (initial import of pixar from submodule)
# 825ca13dd77af84872a063f146dee1799e8be25c - plugins/PXR_USDMaya (renamed dir)
# 141bab7eba1d380868e822a51f8c8f85e1c0b66f - plugins/PXR_USDMaya (identical contents as above)
# e5e10a28d0ba0535e83675399a5d15314fb79ec9 - plugin/pxr (renamed dir)

dev_mergebase=$(git merge-base PXR/dev dev)
pixar_dev_commit=$(git show -s --format="%H" dev)

# This function will take a "stock" pixar USD repo, and rename / delete files
# and folders to make it "line up" with their locations in maya-usd

function renamePixarRepo ()
{
    cd "$(git rev-parse --show-toplevel)"

    # move everything in the root to plugin/pxr
    rm -rf plugin/pxr
    mkdir -p plugin/pxr
    git mv -k $(ls -A) plugin/pxr

    # Move back some of the cmake stuff to the root
    mkdir -p cmake
    git mv plugin/pxr/cmake/defaults/ cmake/
    git mv plugin/pxr/cmake/modules/ cmake/

    # Remove a bunch of files / folders
    git rm -f cmake/defaults/Packages.cmake
    git rm -f cmake/modules/FindGLEW.cmake
    git rm -f cmake/modules/FindPTex.cmake
    git rm -f cmake/modules/FindRenderman.cmake
    git rm -f --ignore-unmatch cmake/modules/FindDraco.cmake
    git rm -f plugin/pxr/.appveyor.yml
    git rm -f plugin/pxr/.gitignore
    git rm -f plugin/pxr/.travis.yml
    git rm -f plugin/pxr/BUILDING.md
    git rm -f plugin/pxr/CHANGELOG.md
    git rm -f plugin/pxr/CONTRIBUTING.md
    git rm -f plugin/pxr/NOTICE.txt
    git rm -f plugin/pxr/README.md
    git rm -f plugin/pxr/USD_CLA_Corporate.pdf
    git rm -f plugin/pxr/USD_CLA_Individual.pdf
    git rm -f --ignore-unmatch VERSIONS.md
    git rm -f plugin/pxr/cmake/macros/generateDocs.py
    git rm -f plugin/pxr/pxr/CMakeLists.txt
    git rm -f plugin/pxr/pxr/pxrConfig.cmake.in

    git rm -rf plugin/pxr/.github/
    git rm -rf plugin/pxr/build_scripts/
    git rm -rf plugin/pxr/extras/
    git rm -rf plugin/pxr/pxr/base/
    git rm -rf plugin/pxr/pxr/imaging/
    git rm -rf plugin/pxr/pxr/usd/
    git rm -rf plugin/pxr/pxr/usdImaging/
    git rm -rf plugin/pxr/third_party/houdini/
    git rm -rf plugin/pxr/third_party/katana/
    git rm -rf plugin/pxr/third_party/renderman-22/

    git mv plugin/pxr/third_party/maya plugin/pxr/maya

    delete_replace_lic=0
    if [[ ! -f replace_lic.py ]]; then
        delete_replace_lic=1
        git checkout dev -- replace_lic.py
    fi
    python replace_lic.py --pxr
    if (( $delete_replace_lic )); then
        rm replace_lic.py
    fi
}

##############################
# branch: renamed_mergebase
##############################
# Make a branch that's IDENTICAL to stock 19.05, except with directory renames/
# file moves / deletions to get files into the same place as in the master
# branch of Maya-USD
# 
# This branch is a useful reference point, and will be used to make a diff /
# patch file which will handy when doing merges.

echo "Checking out last-merged pixar-dev commit ($dev_mergebase)"
git checkout -B renamed_mergebase $dev_mergebase
echo "...renaming files to match maya-usd layout..."
renamePixarRepo
git commit -a -m "Renamed / deleted files from previously-merged dev to match maya-usd layout"
echo "...done renaming files"


##############################
# branch: renamed_pxr_dev
##############################
# Make a branch that's IDENTICAL to pixar's latest usd dev
# (b29152c2896b1b4d03fddbd9c3dcaad133d2c495), except with directory renames/
# file moves / deletions to get files into the same place as in the master
# branch of Maya-USD
# 
# This branch is a useful reference point, and will be used to make a diff /
# patch file which will handy when doing merges.

echo "Checking out latest pixar-dev commit ($pixar_dev_commit)"
git checkout -B renamed_pxr_dev PXR/dev
renamePixarRepo
echo "...renaming files to match maya-usd layout..."
git commit -a -m "Renamed / deleted files from pixar dev to match maya-usd layout"
echo "...done renaming files"

###############
# Make a patch that gives all changes between renamed_v1905 and renamed_pxr_dev
# ...this will be used when resolving merge conflicts

git diff renamed_mergebase renamed_pxr_dev > ../pixar_dev.diff
echo "Created diff of new changes to merge in"


###############
# Now that we have our helper diff, merge pixar-usd dev into latest maya-usd master

git checkout dev

# attempt the merge - this will give a lot of merge conflicts...
echo "Attempting merge..."

set +e

if git merge PXR/dev; then
    echo 'merge succeeded! Unbelieveable!'
else
    echo 'merge failed, as expected...'
fi

echo "Removing files that aren't used by maya-usd"

# These files were removed / we don't care about:

git rm -f cmake/defaults/Packages.cmake
git rm -f cmake/modules/FindGLEW.cmake
git rm -f cmake/modules/FindPTex.cmake
git rm -f cmake/modules/FindRenderman.cmake
git rm -f cmake/modules/FindDraco.cmake
git rm -f .appveyor.yml
git rm -f .travis.yml
git rm -f BUILDING.md
git rm -f CHANGELOG.md
git rm -f CONTRIBUTING.md
git rm -f NOTICE.txt
git rm -f USD_CLA_Corporate.pdf
git rm -f USD_CLA_Individual.pdf
git rm -f VERSIONS.md
git rm -f cmake/macros/generateDocs.py
git rm -f pxr/CMakeLists.txt
git rm -f pxr/pxrConfig.cmake.in
git rm -rf .github/
git rm -rf build_scripts/
git rm -rf extras/
git rm -rf pxr/base/
git rm -rf pxr/imaging/
git rm -rf pxr/usd/
git rm -rf pxr/usdImaging/
git rm -rf third_party/houdini/
git rm -rf third_party/katana/
git rm -rf third_party/renderman-22

set -e

echo "...done removing files."

# for license, decided to just use the Pixar one unaltered... this is the
# LICENSE.txt that stood at the root of the USD project.  Had been removing
# new license bits that didn't apply to the maya plugin... but there were
# already many bits that didn't apply to maya, and having a few more shouldn't
# make a difference... and going forward, will be easier to simply take their
# LICENSE.txt unaltered (moved to plugin/pxr/LICENSE.txt)

git show PXR/dev:LICENSE.txt > plugin/pxr/LICENSE.txt
git add plugin/pxr/LICENSE.txt

echo "Remaining conflicts to be resolved:"
echo "==========================================================="
git status
echo "==========================================================="
echo "(See the commented out section of the script for tips)"

# Ok, this ends the section of stuff that can be run automated.  The rest of this
# is commented out, and can be copy / pasted into a terminal, or just used for
# for reference.

# Basically, you need to go through the added / deleted / merge-conflict files,
# making sure everything seems to be in the right place.  The lines below have
# sections covering ways of handling various issues - the trickiest being when
# a rename was not detected, and our diff needs to be applied. Most of the other
# issues can be resolved with normal git tricks...

################################################################################
# New Files
################################################################################

# These were new files, that we're moving into their proper places:

# git mv third_party/maya/lib/pxrUsdMayaGL/testenv plugin/pxr/maya/lib/pxrUsdMayaGL
# git mv third_party/maya/lib/usdMaya/testenv/UsdReferenceAssemblyChangeRepresentationsTest/* plugin/pxr/maya/lib/usdMaya/testenv/UsdReferenceAssemblyChangeRepresentationsTest
# rm -rf third_party/maya/lib/usdMaya/testenv/UsdReferenceAssemblyChangeRepresentationsTest
# git mv third_party/maya/lib/usdMaya/testenv/UsdExportAssemblyEditsTest plugin/pxr/maya/lib/usdMaya/testenv
# git mv third_party/maya/lib/usdMaya/testenv/testUsdExportAssemblyEdits.py plugin/pxr/maya/lib/usdMaya/testenv/testUsdExportAssemblyEdits.py

# git mv third_party/maya/plugin/pxrUsdTranslators/strokeWriter.* plugin/pxr/maya/plugin/pxrUsdTranslators
# mkdir -p plugin/pxr/maya/plugin/pxrUsdTranslators/testenv/StrokeExportTest
# git mv third_party/maya/plugin/pxrUsdTranslators/testenv/StrokeExportTest/StrokeExportTest.ma plugin/pxr/maya/plugin/pxrUsdTranslators/testenv/StrokeExportTest/StrokeExportTest.ma
# git mv third_party/maya/plugin/pxrUsdTranslators/testenv/testPxrUsdTranslatorsStroke.py plugin/pxr/maya/plugin/pxrUsdTranslators/testenv/testPxrUsdTranslatorsStroke.py


################################################################################
# Changes we don't want
################################################################################


# # When I inspected these, determined we didn't care about any of the changes in
# # these files between renamed_v1905 and renamed_pxr_dev - so just checking out
# # old version

# git checkout dev -- cmake/defaults/Options.cmake

################################################################################
# Bad rename detection - mapped to wrong file (ie, in AL)
################################################################################

# these are conflicts presumably due to bad rename detection
# git checkout dev -- plugin/al/lib/AL_USDMaya/Doxyfile
# git checkout dev -- plugin/al/schemas/AL/usd/schemas/mayatest/ExamplePolyCubeNode.h

################################################################################
# Bad rename detection - didn't detect a rename
################################################################################

# # Most of the rest of these seem to be files whose rename wasn't properly
# # recorded by git - they're marked as modifications to deleted files. Solve by
# # using the patch we made earlier.

function applyPixarRootDiff ()
{
    pxrPath="$1"
    adPath=plugin/pxr/"$1"
    git apply ../pixar_1905_dev.diff --include="$adPath"
    result="$?"
    if (( $result == 0 )); then
        echo "success!"
        git add "$adPath"
        git rm "$pxrPath"
    else
        echo
        echo '!!!!!!!!!!!'
        echo 'failure!'
        echo '!!!!!!!!!!!'
    fi
}

function applyPixarMayaDiff ()
{
    pxrPath="$1"
    adPath=$(echo "$pxrPath" | sed -e 's~third_party/maya~plugin/pxr/maya~')
    git apply ../pixar_1905_dev.diff --include="$adPath"
    result="$?"
    if (( $result == 0 )); then
        echo "success!"
        git add "$adPath"
        git rm "$pxrPath"
    else
        echo
        echo '!!!!!!!!!!!'
        echo 'failure!'
        echo '!!!!!!!!!!!'
    fi
}

# applyPixarRootDiff cmake/macros/Private.cmake

# applyPixarMayaDiff third_party/maya/lib/pxrUsdMayaGL/batchRenderer.cpp
# applyPixarMayaDiff third_party/maya/lib/pxrUsdMayaGL/batchRenderer.h
# applyPixarMayaDiff third_party/maya/lib/pxrUsdMayaGL/hdImagingShapeDrawOverride.cpp
# applyPixarMayaDiff third_party/maya/lib/pxrUsdMayaGL/hdImagingShapeUI.cpp
# applyPixarMayaDiff third_party/maya/lib/pxrUsdMayaGL/hdRenderer.cpp
# applyPixarMayaDiff third_party/maya/lib/pxrUsdMayaGL/instancerShapeAdapter.cpp
# applyPixarMayaDiff third_party/maya/lib/pxrUsdMayaGL/proxyDrawOverride.cpp
# applyPixarMayaDiff third_party/maya/lib/pxrUsdMayaGL/proxyShapeDelegate.cpp
# applyPixarMayaDiff third_party/maya/lib/pxrUsdMayaGL/proxyShapeUI.cpp
# applyPixarMayaDiff third_party/maya/lib/pxrUsdMayaGL/sceneDelegate.cpp
# applyPixarMayaDiff third_party/maya/lib/pxrUsdMayaGL/sceneDelegate.h
# applyPixarMayaDiff third_party/maya/lib/pxrUsdMayaGL/shapeAdapter.cpp
# applyPixarMayaDiff third_party/maya/lib/pxrUsdMayaGL/shapeAdapter.h
# applyPixarMayaDiff third_party/maya/lib/pxrUsdMayaGL/usdProxyShapeAdapter.cpp
# applyPixarMayaDiff third_party/maya/lib/usdMaya/CMakeLists.txt
# applyPixarMayaDiff third_party/maya/lib/usdMaya/editUtil.cpp
# applyPixarMayaDiff third_party/maya/lib/usdMaya/editUtil.h
# applyPixarMayaDiff third_party/maya/lib/usdMaya/hdImagingShape.cpp
# applyPixarMayaDiff third_party/maya/lib/usdMaya/hdImagingShape.h
# applyPixarMayaDiff third_party/maya/lib/usdMaya/readJob.cpp
# applyPixarMayaDiff third_party/maya/lib/usdMaya/referenceAssembly.cpp
# applyPixarMayaDiff third_party/maya/lib/usdMaya/shadingModeImporter.h
# applyPixarMayaDiff third_party/maya/lib/usdMaya/shadingModePxrRis.cpp
# applyPixarMayaDiff third_party/maya/lib/usdMaya/shadingModeUseRegistry.cpp
# applyPixarMayaDiff third_party/maya/lib/usdMaya/testenv/testUsdExportPackage.py
# applyPixarMayaDiff third_party/maya/lib/usdMaya/testenv/testUsdExportRfMLight.py
# applyPixarMayaDiff third_party/maya/lib/usdMaya/testenv/testUsdExportShadingModePxrRis.py
# applyPixarMayaDiff third_party/maya/lib/usdMaya/testenv/testUsdImportRfMLight.py
# applyPixarMayaDiff third_party/maya/lib/usdMaya/testenv/testUsdImportShadingModePxrRis.py
# applyPixarMayaDiff third_party/maya/lib/usdMaya/testenv/testUsdMayaGetVariantSetSelections.py
# applyPixarMayaDiff third_party/maya/lib/usdMaya/testenv/testUsdMayaXformStack.py
# applyPixarMayaDiff third_party/maya/lib/usdMaya/testenv/testUsdReferenceAssemblyChangeRepresentations.py
# applyPixarMayaDiff third_party/maya/lib/usdMaya/translatorModelAssembly.cpp
# applyPixarMayaDiff third_party/maya/lib/usdMaya/translatorRfMLight.cpp
# applyPixarMayaDiff third_party/maya/lib/usdMaya/translatorUtil.cpp
# applyPixarMayaDiff third_party/maya/lib/usdMaya/translatorUtil.h
# applyPixarMayaDiff third_party/maya/lib/usdMaya/translatorXformable.cpp
# applyPixarMayaDiff third_party/maya/lib/usdMaya/util.cpp
# applyPixarMayaDiff third_party/maya/lib/usdMaya/util.h
# applyPixarMayaDiff third_party/maya/lib/usdMaya/wrapEditUtil.cpp
# applyPixarMayaDiff third_party/maya/lib/usdMaya/writeJob.cpp
# applyPixarMayaDiff third_party/maya/lib/usdMaya/writeJobContext.cpp
# applyPixarMayaDiff third_party/maya/plugin/pxrUsdTranslators/CMakeLists.txt
# applyPixarMayaDiff third_party/maya/plugin/pxrUsdTranslators/fileTextureWriter.cpp
# applyPixarMayaDiff third_party/maya/plugin/pxrUsdTranslators/lightReader.cpp
# applyPixarMayaDiff third_party/maya/plugin/pxrUsdTranslators/lightWriter.cpp