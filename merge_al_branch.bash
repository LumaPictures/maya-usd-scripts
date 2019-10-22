#!/bin/bash

set -e

# change to git root dir
cd "$(git rev-parse --show-toplevel)"


usage="USAGE: $0 REMOTE BRANCH DEPENDENCY"
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

function githash () {
    commit="$1"
    if [[ -z "$commit" ]]; then
        commit=HEAD
    fi    
    git show -s --format="%H" "$commit"
}

remote="$1"
branch="$2"

if [[ -z "$3" ]]; then
    dep="develop"
else
    dep="$3"
fi

dep="${remote}/${dep}"

# get the original / unrebased branch
git fetch ${remote} "refs/heads/${branch}:refs/remotes/${remote}/${branch}"

# make sure our version of the branch is reset to match remote
git checkout -B "${branch}" "${remote}/${branch}"

# make sure that there's only one important commit in the branch

exported_commits=( $(git log --no-merges --format=%H "${dep}..${branch}") )

if (( ${#exported_commits[@]} != 1 )); then
    echo "exported/${branch} had more than one commit in '${dep}..${branch}' - aborting."
    echo "You will have to continue manually..."
    exit 1
fi

main_commit="${exported_commits[0]}"

# make sure that the branch has already merged in it's dep
if [[ "$(githash "${branch}")" != "$(git merge-base "${branch}" "${dep}")" ]]; then
    echo "merging ${dep} into ${branch}"
    git merge --no-edit "${dep}"
fi

# This function will take a "stock" AnimalLogic AL_USDMaya repo, and rename /
# delete files and folders to make it "line up" with their locations in maya-usd

function renameALRepo ()
{
    echo "Renaming files in $(current_branch) to match usd_maya layout..."
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

    python "${THIS_DIR}/replace_lic.py" --al
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
renameALRepo
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

git checkout -B "renamed/${branch}" "${branch}"
renameALRepo
git commit -a -m "Renamed / deleted files from ${branch} to match maya-usd layout"

# ok, turn this into a temp branch, and rebase against renamed/${dep}
git branch -f temp

git reset --soft "renamed/${dep}"
git commit --reuse-message="${main_commit}"

git branch -D temp

echo "made renamed/${branch} - should have roughly the same content as ${main_commit}"

# ###############
# # Make a patch that gives all changes between "renamed/${dep}" and "renamed/${branch}"
# # ...this may be used when resolving merge conflicts

git diff "renamed/${dep}" "renamed/${branch}" > ../"branch.diff"


# ###############
# Try to cherry-pick our exported changes...

new_branch="${branch/pr/pr/al}"

git checkout -B "${new_branch}" dev

set +e

succeeded=0
if git cherry-pick "renamed/${branch}"; then
    echo 'Cherry-pick succeeded! Unbelieveable!'
    succeeded=1
else
    echo 'Cherry-pick failed, as expected...'

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

    echo "...done removing files."
fi

set -e


if (( $succeeded )); then
    echo 'SUCCESS!!!!!!'
else
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

function applyALDiff ()
{
    alPath="$1"
    adPath=plugin/al/"$1"
    git apply ../branch.diff --include="$adPath"
    result="$?"
    if (( $result == 0 )); then
        echo "success!"
        git add "$adPath"
        git rm "$alPath"
    else
        echo
        echo '!!!!!!!!!!!'
        echo 'failure!'
        echo '!!!!!!!!!!!'
    fi
}

# # applyALDiff third_party/maya/lib/usdMaya/debugCodes.cpp
# # applyALDiff third_party/maya/lib/usdMaya/debugCodes.h

