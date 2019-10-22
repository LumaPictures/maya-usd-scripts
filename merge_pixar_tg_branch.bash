#!/bin/bash

set -e

# change to git root dir
cd "$(git rev-parse --show-toplevel)"


usage="USAGE: $0 REMOTE BRANCH"
if [[ -z "$1" ]]; then
    echo "Missing first arg - name of git remote"
    echo $usage
    exit 1
fi

if [[ -z "$2" ]]; then
    echo "Missing second arg - name of git branch"
    echo $usage
    exit 1
fi

THIS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

function current_branch () {
    git symbolic-ref --short -q HEAD
}

remote="$1"
branch="$2"

# get the original / unrebased branch
git fetch ${remote} "refs/heads/${branch}:refs/remotes/${remote}/${branch}"

# make sure our version of the branch is reset to match remote
git checkout -B "${branch}" "${remote}/${branch}"

# ensure it only has one dep
deps=($(git show "${remote}/${branch}:.topdeps"))
if (( ${#deps[@]} != 1 )); then
    if (( ${#deps[@]} == 0 )); then
        echo "Branch ${branch} had no dependencies!"
    else
        echo "Branch ${branch} had more than one dependency:"
        for dep in "${deps[@]}"
        do
          echo "${dep}"
        done
    fi
    exit 1
fi
dep="${deps[0]}"

if [[ "$dep" == dev ]]; then
    dep="${remote}/dev"
fi

# ###############
# tg export, then get renamed versions

# want to do a tg-export... but that will complain if it's dependency (dev) is
# not in the right place. but the tg branches expect dev to be the PXR dev, not
# the maya_usd dev...

git branch -f dev "${remote}/dev"
git checkout "${branch}"
tg export --force "exported/${branch}"
git branch -f dev origin/dev

# make sure that there's only one commit in exported branch

exported_commits=( $(git log --format=%H "${dep}..exported/${branch}") )

if (( ${#exported_commits[@]} != 1 )); then
    echo "exported/${branch} had more than one commit in '${dep}..exported/${branch}' - aborting."
    echo "You will have to continue manually..."
    exit 1
fi

# This function will take a "stock" pixar USD repo, and rename / delete files
# and folders to make it "line up" with their locations in maya-usd

function renamePixarRepo ()
{
    echo "Renaming files in $(current_branch) to match usd_maya layout..."
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
    if [[ -f .topdeps ]]; then
        git rm -f .topdeps
    fi
    if [[ -f .topmsg ]]; then
        git rm -f .topmsg
    fi
    git rm -f cmake/defaults/Packages.cmake
    git rm -f cmake/modules/FindGLEW.cmake
    git rm -f cmake/modules/FindPTex.cmake
    git rm -f cmake/modules/FindRenderman.cmake
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

    python "${THIS_DIR}/replace_lic.py" --pxr
    echo "Done renaming files in $(current_branch)"
}


##############################
# branch: renamed/${dep}
##############################
# Make a branch that's IDENTICAL to the base dependency, except with directory
# renames / file moves / deletions to get files into the same place as in the
# master branch of Maya-USD
# 
# This branch is a useful reference point, and will be used to make a diff /
# patch file which will handy when doing merges.

git checkout -B "renamed/${dep}" "${dep}"
renamePixarRepo
git commit -a -m "Renamed / deleted files from ${dep} to match maya-usd layout"

##############################
# branch: renamed/${branch}
##############################
# Make a branch that's IDENTICAL to our exported branch, except with directory renames/
# renames / file moves / deletions to get files into the same place as in the
# master branch of Maya-USD
# 
# This branch is a useful reference point, and will be used to make a diff /
# patch file which will handy when doing merges.

git checkout -B "renamed/${branch}" "exported/${branch}"
renamePixarRepo
git commit -a -m "Renamed / deleted files from exported/${branch} to match maya-usd layout"

# ok, turn this into a temp branch, and rebase against renamed/${dep}
git branch -f temp

git reset --soft "renamed/${dep}"
git commit --reuse-message="exported/${branch}"

git branch -D temp

# ###############
# # Make a patch that gives all changes between "renamed/${dep}" and "renamed/${branch}"
# # ...this will be used when resolving merge conflicts

git diff "renamed/${dep}" "renamed/${branch}" > ../"branch.diff"


# ###############
# Try to cherry-pick our exported changes...

git checkout -B "${branch}" dev

set +e

succeeded=0
if git cherry-pick "renamed/${branch}"; then
    echo 'Cherry-pick succeeded! Unbelieveable!'
    succeeded=1
else
    echo 'Cherry-pick failed, as expected...'

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

    echo "...done removing files."
fi

set -e


if (( ! $succeeded )); then
    echo "Remaining conflicts to be resolved:"
    echo "==========================================================="
    git status
    echo "==========================================================="
    echo "(See the commented out section of the script for tips)"
fi

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
    git apply ../branch.diff --include="$adPath"
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
    git apply ../branch.diff --include="$adPath"
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

# applyPixarMayaDiff third_party/maya/lib/usdMaya/debugCodes.cpp
# applyPixarMayaDiff third_party/maya/lib/usdMaya/debugCodes.h

function finishTg ()
{
    git cherry-pick --continue || true
    git checkout "${remote}/${branch}" -- .topdeps .topmsg
    git commit -m "tg create ${branch}"
    git update-ref "refs/top-bases/${branch}" dev
}

if (( $succeeded )); then
    finishTg
    echo 'SUCCESS!!!!!!'
fi