#!/bin/bash
# Script that is run after this jar is updated.
# It is run from this directory.
set -e
mkdir -p repository
cd repository
unzip ../sdklib.jar `unzip -l ../sdklib.jar | sed -n '/xsd$/s/.* \(.*\)$/\1/p'`
