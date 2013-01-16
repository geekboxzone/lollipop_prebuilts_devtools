#!/bin/bash

set -e        # fail on errors
DRY="echo"    # default to dry mode unless -f is specified
FILTER=""     # name of a specific jar to update (default: update them all)

while [[ -n "$1" ]]; do
  if [[ "$1" == "-f" ]]; then
    DRY=""
  elif [[ -z "$FILTER" ]]; then
    FILTER="$1"
  else
    echo "Unknown argument: $1"
    echo "Usage: $0 [-f] [project_to_update]"
    echo "      (default: updates all jars.)"
    exit 1
  fi
  shift
done


# Define projects to build and files to copy.
function list_projects() {
  add_project sdklib
  add_project sdkuilib    in:tools/swt
  add_project swtmenubar  in:tools/swt
  add_project ddmlib
  add_project manifmerger
  add_project jobb etc/jobb etc/jobb.bat
}

# ----
# List of targets to build, e.g. :jobb:jar
declare -A BUILD_LIST    # -A==associative array, aka a map[string]=>string
# List of files to copy. Syntax: relative/dir (relative to src & dest) or src/rel/dir|dst/rel/dir.
declare -A COPY_LIST

function add_project() {
  # $1=project name
  # $2=optional in:tools/swt repo (default: tools/base)
  # $2...=optional files to copy (relative to project dir)
  local proj=$1
  shift

  if [[ -n "$FILTER" && "$proj" != "$FILTER" ]]; then
    echo "## Skipping project $proj"
    return
  fi

  local repo="base"
  if [[ "$1" == "in:tools/swt" ]]; then
    repo="swt"
    shift
  fi

  echo "## Getting gradle properties for project tools/$repo/$proj"
  # Request to build the jar for that project
  BUILD_LIST[$repo]="${BUILD_LIST[$repo]} :$proj:jar"

  # Copy the resulting JAR
  local dst=$proj/$proj.jar
  local src=`(cd ../../tools/$repo ; ./gradlew :$proj:properties | \
          awk 'BEGIN { B=""; N=""; V="" } \
               /^archivesBaseName:/ { N=$2 } \
               /^buildDir:/         { B=$2 } \
               /^version:/          { V=$2 } \
               END { print B "/libs/" N "-" V ".jar" }'i )`
  COPY_LIST[$repo]="${COPY_LIST[$repo]} $src|$dst"

  # Copy all the optiona files
  while [[ -n "$1" ]]; do
    COPY_LIST[$repo]="${COPY_LIST[$repo]} $proj/$1"
    shift
  done
  return 0
}

function build() {
  local repo=$1
  echo
  if [[ -z "${BUILD_LIST[$repo]}" ]]; then
    echo "## WARNING: nothing to build in tools/$repo."
    return 1
  else
    # To build tools/swt, we'll need to first locally publish some
    # libs from tools/base.
    if [[ "$repo" == "swt" ]]; then
      echo "## PublishLocal in tools/base (needed for tools/swt)"
      ( cd ../../tools/base ; ./gradlew publishLocal )
    fi
    echo "## Building tools/$repo: ${BUILD_LIST[$repo]}"
    ( cd ../../tools/$repo ; ./gradlew ${BUILD_LIST[$repo]} )
    return 0
  fi
}

function copy_files() {
  local repo=$1
  echo
  if [[ -z "${COPY_LIST[$repo]}" ]]; then
    echo "## WARNING: nothing to copy in tools/$repo."
  else
    for f in ${COPY_LIST[$repo]}; do
      src="${f%%|*}"    # strip part after  | if any
      dst="${f##*|}"    # strip part before | if any
      if [[ ${src:0:1} != "/" ]]; then src=../../tools/$repo/$src; fi
      $DRY cp -v $src $dst
    done
  fi
}

list_projects
for r in base swt; do
  if build $r; then
    copy_files $r
  fi
done
if [[ -n $DRY ]]; then
  echo
  echo "## WARNING: DRY MODE. Run with -f to actually copy files."
fi

