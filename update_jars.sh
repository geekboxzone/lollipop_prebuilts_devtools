#!/bin/bash

set -e            # fail on errors

if [[ $(uname) == "Darwin" ]]; then
  PROG_DIR=$(dirname "$0")
else
  PROG_DIR=$(readlink -f $(dirname "$0"))
fi
cd "$PROG_DIR"

DRY="echo"        # default to dry mode unless -f is specified
MK_MERGE_MSG="1"  # 1 to update the MERGE_MSG, empty to do not generate it
MERGE_MSG=""      # msg to generate

while [[ -n "$1" ]]; do
  if [[ "$1" == "-f" ]]; then
    DRY=""
  elif [[ "$1" == "-m" ]]; then
    MK_MERGE_MSG=""
  elif [[ $1 =~ ^[a-z]+ ]]; then
    FILTER="$FILTER ${1/.jar/} "
  else
    echo "Unknown argument: $1"
    echo "Usage: $0 [-f] [-m]"
    echo "       -f: actual do thing. Default is dry-run."
    echo "       -m: do NOT generate a .git/MERGE_MSG"
    exit 1
  fi
  shift
done


function update() {
  echo
  local repo=$1

  local SHA1=$( cd ../../tools/$repo ; git show-ref --head --hash HEAD )
  MERGE_MSG="$MERGE_MSG
tools/$repo: @ $SHA1"

  ( $DRY cd ../../tools/$repo && $DRY ./gradlew publishLocal pushDistribution )
}

function merge_msg() {
  local dst=.git/MERGE_MSG
  if [[ -n $DRY ]]; then
    echo "The following would be output to $dst (use -m to prevent this):"
    dst=/dev/stdout
  fi
  cat >> $dst <<EOMSG
Update SDK prebuilts.
Origin:
$MERGE_MSG

EOMSG
}

for r in base swt; do
  update $r
done
if [[ $MK_MERGE_MSG ]]; then merge_msg; fi
if [[ -n $DRY ]]; then
  echo
  echo "## WARNING: DRY MODE. Run with -f to actually copy files."
fi

