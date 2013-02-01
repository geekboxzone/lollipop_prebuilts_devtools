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
    echo "Usage: $0 [project_to_update] [-f]"
    echo "      (default: updates all jars.)"
    exit 1
  fi
  shift
done


# Define projects to build and files to copy.
function list_projects() {
  add_project sdklib      @./post_update.sh
  add_project sdkuilib    in:tools/swt
  add_project swtmenubar  in:tools/swt
  add_project ddmlib
  add_project manifmerger
  add_project jobb etc/jobb etc/jobb.bat
}

# ----
# List of targets to build, e.g. :jobb:jar
BUILD_LIST_base=""
BUILD_LIST_swt=""
# List of files to copy.
# Syntax:
#     relative/dir              (copy, relative to src & dest)
#     src/rel/dir|dst/rel/dir   (copy, with different destination name)
#     @relative_script          (executes script in dest/proj dir)
COPY_LIST_base=""
COPY_LIST_swt=""

function get_map() {
  #$1=map name (BUILD_LIST or COPY_LIST)
  #$2=map key  (base or swt)
  eval local V=\$$1_$2
  echo $V
}

function append_map() {
  #$1=map name (BUILD_LIST or COPY_LIST)
  #$2=map key  (base or swt)
  #$3=value to append (will be space separated)
  eval local V=\$$1_$2
  eval $1_$2=\"$V $3\"
}

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
  append_map BUILD_LIST $repo ":$proj:jar"

  # Copy the resulting JAR
  local dst=$proj/$proj.jar
  local src=`(cd ../../tools/$repo ; ./gradlew :$proj:properties | \
          awk 'BEGIN { B=""; N=""; V="" } \
               /^archivesBaseName:/ { N=$2 } \
               /^buildDir:/         { B=$2 } \
               /^version:/          { V=$2 } \
               END { print B "/libs/" N "-" V ".jar" }'i )`
  append_map COPY_LIST $repo "$src|$dst"

  # Copy all the optional files
  while [[ -n "$1" ]]; do
    append_map COPY_LIST $repo "$proj/$1"
    shift
  done
  return 0
}

function build() {
  local repo=$1
  echo
  local buildlist=`get_map BUILD_LIST $repo`
  if [[ -z "$buildlist" ]]; then
    echo "## WARNING: nothing to build in tools/$repo."
    return 1
  else
    # To build tools/swt, we'll need to first locally publish some
    # libs from tools/base.
    if [[ "$repo" == "swt" ]]; then
      echo "## PublishLocal in tools/base (needed for tools/swt)"
      ( cd ../../tools/base ; ./gradlew publishLocal )
    fi
    echo "## Building tools/$repo: $buildlist"
    ( cd ../../tools/$repo ; ./gradlew $buildlist )
    return 0
  fi
}

function copy_files() {
  local repo=$1
  echo
  local copylist=`get_map COPY_LIST $repo`
  if [[ -z "$copylist" ]]; then
    echo "## WARNING: nothing to copy in tools/$repo."
  else
    for f in $copylist; do
      if [[ "${f/@//}" == "$f" ]]; then
        src="${f%%|*}"    # strip part after  | if any
        dst="${f##*|}"    # strip part before | if any
        if [[ ${src:0:1} != "/" ]]; then src=../../tools/$repo/$src; fi
        $DRY cp -v $src $dst
      else
        # syntax is proj/@script_name
        d="${f%%@*}"      # string part after @, that's the proj dir name
        f="${f##*@}"      # strip part before @, script name is what's left.
        echo "## Execute $d => $f"
        ( cd "$d" && pwd && $DRY $f )
      fi
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

