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
JAR_DETECT=""

while [[ -n "$1" ]]; do
  if [[ "$1" == "-f" ]]; then
    DRY=""
  elif [[ "$1" == "-m" ]]; then
    MK_MERGE_MSG=""
  elif [[ "$1" == "-u" ]]; then
    JAR_DETECT="1"
  elif [[ $1 =~ ^[a-z]+ ]]; then
    FILTER="$FILTER ${1/.jar/} "
  else
    echo "Unknown argument: $1"
    echo "Usage: $0 [-f] [-m] [-u]"
    echo "       -f: actual do thing. Default is dry-run."
    echo "       -m: do NOT generate a .git/MERGE_MSG"
    echo "       -u: detect and git-revert unchanged JAR files"
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

function preserve_jars() {
  JAR_TMP_DIR=`mktemp -d -t prebuiltsjarcopy.XXXXXXXX`
  for i in `find . -name "*.jar"` ; do
    tmp_jar=`echo $i | tr "./" "__"`
    cp "$i" "$JAR_TMP_DIR/$tmp_jar"
  done
}

function revert_unchanged_jars() {
  for i in `find . -name "*.jar"` ; do
    tmp_jar=`echo $i | tr "./" "__"`
    dst_jar="$JAR_TMP_DIR/$tmp_jar"
    dst_hash=`get_jar_hash $dst_jar`
    src_hash=`get_jar_hash $i`
    if [[ $dst_hash == $src_hash ]]; then
      echo "# Revert unchanged file $i"
      git checkout -- $i
    else
      echo "! Keep changed file $i"
    fi
  done
}

function get_jar_hash() {
  # $1: the jar file to hash

  # Explanation:
  # - unzip -v prints a "verbose" list of a zip's content including each file path, size, timestamp and CRC32
  # - we don't want the timestamp so we use sed to first remove the time (12:34) and the date (13-14-15).
  # - finally get a md5 of the zip output.
  # if the md5 changes, the zip's content has changed (new file, different content size, different CRC32)
  unzip -v $1 | sed -n -e "/[0-9][0-9]:[0-9][0-9]/s/[0-9][0-9]:[0-9][0-9]// ; s/[0-9][0-9]-[0-9][0-9]-[0-9][0-9]//p" | md5sum
}


if [[ -n $JAR_DETECT ]]; then preserve_jars; fi
for r in base swt; do
  update $r
done
if [[ -n $JAR_DETECT ]]; then revert_unchanged_jars; fi
if [[ -n $MK_MERGE_MSG ]]; then merge_msg; fi
if [[ -n $DRY ]]; then
  echo
  echo "## WARNING: DRY MODE. Run with -f to actually copy files."
fi

