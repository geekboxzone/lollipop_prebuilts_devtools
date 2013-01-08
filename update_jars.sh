#!/bin/bash

set -e        # fail on errors
DRY="echo"    # default to dry mode unless -f is specified

if [[ "$1" == "-f" ]]; then
  DRY=""
fi

# Define projects to build and files to copy.
function list_projects() {
  add_project manifmerger
  add_project jobb etc/jobb etc/jobb.bat
}

# ----
# List of targets to build, e.g. :jobb:jar
BUILD_LIST=""
# List of files to copy. Syntax: relative/dir (relative to src & dest) or src/rel/dir|dst/rel/dir.
COPY_LIST=""

function add_project() {
  # $1=project name
  # $2...=optional files to copy (relative to project dir)
  local proj=$1
  echo "## Getting properties for project $proj"
  # Request to build the jar for that project
  BUILD_LIST="$BUILD_LIST :$proj:jar"
  # Copy the resulting JAR
  local dst=$proj/$proj.jar
  local src=`(cd ../../tools/base ; ./gradlew :$proj:properties | \
          awk 'BEGIN { B=""; N=""; V="" } \
               /^archivesBaseName:/ { N=$2 } \
               /^buildDir:/         { B=$2 } \
               /^version:/          { V=$2 } \
               END { print B "/libs/" N "-" V ".jar" }'i )`
  COPY_LIST="$COPY_LIST $src|$dst"

  # Copy all the optiona files
  shift
  while [[ -n "$1" ]]; do
    COPY_LIST="$COPY_LIST $proj/$1"
    shift
  done
}

function build() {
  echo
  if [[ -z "$BUILD_LIST" ]]; then
    echo "Error: nothing to build."; exit 1;
  else
    echo "## Building $BUILD_LIST"
    ( cd ../../tools/base ; ./gradlew $BUILD_LIST )
  fi
}

function copy_files() {
  echo
  if [[ -z "$COPY_LIST" ]]; then
    echo "Error: nothing to copy."; exit 1;
  else
    for f in $COPY_LIST; do
      src="${f%%|*}"    # strip part after  | if any
      dst="${f##*|}"    # strip part before | if any
      if [[ ${src:0:1} != "/" ]]; then src=../../tools/base/$src; fi
      $DRY cp -v $src $dst
    done
    if [[ -n $DRY ]]; then
      echo
      echo "## WARNING: DRY MODE. Run with -f to actually copy files."
    fi
  fi
}

list_projects
build
copy_files
