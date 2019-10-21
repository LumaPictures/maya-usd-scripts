set -e

if [[ -z "$1" ]]; then
    echo "usage: $0 REMOTE"
    echo "First argument must be the git remote that the AL develop branch can be found on"
    exit 1
fi

remote="$1"

if ! git rev-parse --verify -q $remote/develop > /dev/null ; then
    echo "Given remote '$remote' did not have a develop branch"
    echo "(ie, '$remote/develop' did not exist)"
    exit 1
fi

# change to git root dir
cd "$(git rev-parse --show-toplevel)"

# Some commit reference points:

# 19a1e755c258c9ac0d7495fa0add62508ff377a1 - plugins/AL_USDMaya (initial import of pixar from submodule)
# 825ca13dd77af84872a063f146dee1799e8be25c - plugins/AL_USDMaya (some removals)
# 141bab7eba1d380868e822a51f8c8f85e1c0b66f - plugins/AL_USDMaya (identical contents as above)
# e5e10a28d0ba0535e83675399a5d15314fb79ec9 - plugin/al (renamed dir)

# Removed in 825ca13dd77af84872a063f146dee1799e8be25c
# D       plugins/AL_USDMaya/.gitignore
# D       plugins/AL_USDMaya/AL_USDMaya_Corporate_CLA.pdf
# D       plugins/AL_USDMaya/AL_USDMaya_Individual_CLA.pdf
# D       plugins/AL_USDMaya/CHANGELOG.md
# D       plugins/AL_USDMaya/NOTICE.txt
# D       plugins/AL_USDMaya/PULL_REQUEST_TEMPLATE.md
# D       plugins/AL_USDMaya/build_docker_centos6.sh
# D       plugins/AL_USDMaya/build_docker_centos7.sh
# D       plugins/AL_USDMaya/build_lib.sh
# D       plugins/AL_USDMaya/cmake/defaults/CXXHelpers.cmake
# D       plugins/AL_USDMaya/cmake/defaults/Version.cmake
# D       plugins/AL_USDMaya/cmake/defaults/msvcdefaults.cmake
# D       plugins/AL_USDMaya/cmake/modules/FindMaya.cmake
# D       plugins/AL_USDMaya/cmake/modules/FindUFE.cmake
# D       plugins/AL_USDMaya/cmake/modules/FindUSD.cmake
# D       plugins/AL_USDMaya/docker/Dockerfile_centos6
# D       plugins/AL_USDMaya/docker/Dockerfile_centos7
# D       plugins/AL_USDMaya/docker/README.md
# D       plugins/AL_USDMaya/docker/build_alusdmaya.sh
# D       plugins/AL_USDMaya/setup_environment.sh

dev_mergebase=$(git merge-base $remote/develop dev)
al_develop_commit=$(git show -s --format="%H" develop)

# This function will take a "stock" AnimalLogic AL_USDMaya repo, and rename /
# delete files and folders to make it "line up" with their locations in maya-usd

function renameALRepo ()
{
    # Get in line with e5e10a28d0ba0535e83675399a5d15314fb79ec9
    # We move in two steps because the AL repo originally has a dir called
    # "plugin", which we still want to move into plugin - ie,
    #    plugin => plugin/al/plugin
    # By doing in two stages, it makes sure it doesn't treat this initial
    # 'plugin' dir special

    mkdir -p temp    
    git mv -k $(ls -A) temp

    mkdir -p plugin
    git mv temp plugin/al

    git rm -f plugin/al/.gitignore
    git rm -f plugin/al/AL_USDMaya_Corporate_CLA.pdf
    git rm -f plugin/al/AL_USDMaya_Individual_CLA.pdf
    git rm -f plugin/al/CHANGELOG.md
    git rm -f plugin/al/NOTICE.txt
    git rm -f plugin/al/PULL_REQUEST_TEMPLATE.md
    git rm -f plugin/al/build_docker_centos6.sh
    git rm -f plugin/al/build_docker_centos7.sh
    git rm -f plugin/al/build_lib.sh
    git rm -f plugin/al/setup_environment.sh
    git rm -rf plugin/al/docker/

    git mv plugin/al/cmake cmake

    python replace_lic.py --al
}

##############################
# branch: renamed_mergebase
##############################
# Make a branch that's IDENTICAL to the last-merged AL develop commit, except
# with directory renames/ file moves / deletions to get files into the same
# place as in the dev branch of Maya-USD
# 
# This branch is a useful reference point, and will be used to make a diff /
# patch file which will handy when doing merges.

echo "Checking out last-merged al-develop commit ($dev_mergebase)"
git checkout -B renamed_mergebase $dev_mergebase
echo "...renaming files to match maya-usd layout.."
renameALRepo
git commit -a -m "Renamed / deleted files from previously-merged develop to match maya-usd layout"
echo "...done renaming files"

##############################
# branch: renamed_al_develop
##############################
# Make a branch that's IDENTICAL to AL's latest develop, except with directory
# renames/ file moves / deletions to get files into the same place as in the
# dev branch of Maya-USD
# 
# This branch is a useful reference point, and will be used to make a diff /
# patch file which will handy when doing merges.

echo "Checking out latest al-develop commit ($al_develop_commit)"
git checkout -B renamed_al_develop $remote/develop
renameALRepo
echo "...renaming files to match maya-usd layout.."
git commit -a -m "Renamed / deleted files from AL develop to match maya-usd layout"
echo "...done renaming files"

###############
# Make a patch that gives all changes between renamed_mergebase and renamed_al_develop
# ...this will be used when resolving merge conflicts

git diff renamed_mergebase renamed_al_develop > ../al_develop.diff
echo "Created diff of new changes to merge in"


###############
# Now that we have our helper diff, merge pixar-usd dev into latest maya-usd master

git checkout dev

# attempt the merge - this will give a lot of merge conflicts...
echo "Attempting merge..."

set +e

if git merge $remote/develop; then
    echo 'merge succeeded! Unbelieveable!'
else
    echo 'merge failed, as expected...'
fi

echo "Removing files that aren't used by maya-usd"

# These files were removed / we don't care about:
git rm -f CHANGELOG.md
git rm -f .gitignore
git rm -f AL_USDMaya_Corporate_CLA.pdf
git rm -f AL_USDMaya_Individual_CLA.pdf
git rm -f CHANGELOG.md
git rm -f NOTICE.txt
git rm -f PULL_REQUEST_TEMPLATE.md
git rm -f build_docker_centos6.sh
git rm -f build_docker_centos7.sh
git rm -f build_lib.sh
git rm -f setup_environment.sh
git rm -rf docker/

echo "Remaining conflicts to be resolved:"
echo "==========================================================="
git status
echo "==========================================================="
echo "(See the commented out section of the script for tips)"

# # These were new files, that we're moving into their proper places:

# git mv docs/cameraProxy.md plugin/al/docs/cameraProxy.md
# git mv lib/AL_USDMaya/AL/usdmaya/cmds/ListTranslators.cpp plugin/al/lib/AL_USDMaya/AL/usdmaya/cmds/ListTranslators.cpp
# git mv lib/AL_USDMaya/AL/usdmaya/cmds/SyncFileIOGui.cpp plugin/al/lib/AL_USDMaya/AL/usdmaya/cmds/SyncFileIOGui.cpp
# git mv lib/AL_USDMaya/AL/usdmaya/cmds/SyncFileIOGui.h plugin/al/lib/AL_USDMaya/AL/usdmaya/cmds/SyncFileIOGui.h
# git mv lib/AL_USDMaya/AL/usdmaya/nodes/ProxyUsdGeomCamera.cpp plugin/al/lib/AL_USDMaya/AL/usdmaya/nodes/ProxyUsdGeomCamera.cpp
# git mv lib/AL_USDMaya/AL/usdmaya/nodes/ProxyUsdGeomCamera.h plugin/al/lib/AL_USDMaya/AL/usdmaya/nodes/ProxyUsdGeomCamera.h
# git mv mayautils/AL/maya/tests/mayaplugintest/utils/PluginTranslatorOptionsTest.cpp plugin/al/mayautils/AL/maya/tests/mayaplugintest/utils/PluginTranslatorOptionsTest.cpp
# git mv mayautils/AL/maya/utils/PluginTranslatorOptions.cpp plugin/al/mayautils/AL/maya/utils/PluginTranslatorOptions.cpp
# git mv mayautils/AL/maya/utils/PluginTranslatorOptions.h plugin/al/mayautils/AL/maya/utils/PluginTranslatorOptions.h
# git mv plugin/AL_USDMayaTestPlugin/AL/usdmaya/fileio/import_instances.cpp plugin/al/plugin/AL_USDMayaTestPlugin/AL/usdmaya/fileio/import_instances.cpp
# git mv plugin/AL_USDMayaTestPlugin/AL/usdmaya/fileio/test_activeInActiveTranslators.cpp plugin/al/plugin/AL_USDMayaTestPlugin/AL/usdmaya/fileio/test_activeInActiveTranslators.cpp
# git mv plugin/AL_USDMayaTestPlugin/AL/usdmaya/nodes/test_ProxyUsdGeomCamera.cpp plugin/al/plugin/AL_USDMayaTestPlugin/AL/usdmaya/nodes/test_ProxyUsdGeomCamera.cpp
# git mv plugin/AL_USDMayaTestPlugin/AL/usdmaya/test_DiffGeom.cpp plugin/al/plugin/AL_USDMayaTestPlugin/AL/usdmaya/test_DiffGeom.cpp
# git mv translators/CommonTranslatorOptions.cpp plugin/al/translators/CommonTranslatorOptions.cpp
# git mv translators/CommonTranslatorOptions.h plugin/al/translators/CommonTranslatorOptions.h

# git add lib/AL_USDMaya/AL/usdmaya/cmds/ListTranslators.h
# git mv lib/AL_USDMaya/AL/usdmaya/cmds/ListTranslators.h plugin/al/lib/AL_USDMaya/AL/usdmaya/cmds/ListTranslators.h

# git add mayautils/AL/maya/utils/Utils.cpp
# git mv mayautils/AL/maya/utils/Utils.cpp plugin/al/mayautils/AL/maya/utils/Utils.cpp

# # both deleted:

# git rm lib/AL_USDMaya/AL/usdmaya/cmds/ProxyShapeSelectCommands.cpp
# git rm lib/AL_USDMaya/AL/usdmaya/cmds/ProxyShapeSelectCommands.h
# git rm plugin/al/lib/AL_USDMaya/AL/usdmaya/cmds/ProxyShapeSelectCommands.cpp
# git rm plugin/al/lib/AL_USDMaya/AL/usdmaya/cmds/ProxyShapeSelectCommands.h

# # newly deleted:

# git rm plugin/al/lib/AL_USDMaya/AL/usdmaya/DrivenTransformsData.cpp
# git rm plugin/al/lib/AL_USDMaya/AL/usdmaya/DrivenTransformsData.h
# git rm plugin/al/lib/AL_USDMaya/AL/usdmaya/fileio/translators/CameraTranslator.cpp
# git rm plugin/al/lib/AL_USDMaya/AL/usdmaya/fileio/translators/MeshTranslator.cpp
# git rm plugin/al/lib/AL_USDMaya/AL/usdmaya/fileio/translators/NurbsCurveTranslator.cpp
# git rm plugin/al/lib/AL_USDMaya/AL/usdmaya/nodes/proxy/DrivenTransforms.cpp
# git rm plugin/al/lib/AL_USDMaya/AL/usdmaya/nodes/proxy/DrivenTransforms.h
# git rm plugin/al/plugin/AL_USDMayaTestPlugin/AL/usdmaya/nodes/proxy/test_DrivenTransforms.cpp

# When I inspected these, determined we didn't care about any of the changes in
# these files between renamed_mergebase and renamed_al_develop - so just checking out
# old version

# git checkout dev -- CMakeLists.txt

# function showALDiff ()
# {
#     git difftool -y renamed_mergebase renamed_al_develop -- "$1" &
# }

# # Manually merged these:

# git mergetool cmake/modules/FindUFE.cmake
# git mergetool plugin/al/lib/AL_USDMaya/AL/usdmaya/nodes/ProxyShapeUI.cpp
# git mergetool plugin/al/mayautils/AL/maya/event/MayaEventManager.cpp
# git mergetool plugin/al/mayautils/AL/maya/utils/MenuBuilder.h
# git mergetool plugin/al/mayautils/AL/maya/utils/NodeHelper.cpp
# git mergetool plugin/al/usdmayautils/AL/usdmaya/utils/DgNodeHelper.cpp

