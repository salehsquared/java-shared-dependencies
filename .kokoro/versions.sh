#!/bin/bash
# Copyright 2020 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -eo pipefail

## Get the directory of the build script
scriptDir=$(realpath $(dirname "${BASH_SOURCE[0]}"))
## cd to the parent directory, i.e. the root of the git repo
cd ${scriptDir}/..

# include common functions
source ${scriptDir}/common.sh

# Print out Java
java -version
echo $JOB_TYPE

export MAVEN_OPTS="-Xmx1024m -XX:MaxPermSize=128m"

mvn -B dependency:analyze -DfailOnWarning=true

function versionsCheck() {
 msg "Comparing dependencies with google-cloud shared BOM..."
 #Use versions plugin, specifying our remote POM as the most recent shared dependencies BOM.
 #Filter out any lines that don't have anything to do with our dependency version differences.
 #Remove duplicate lines.
 #If we list 'none' for our different dependencies versions, filter it for an empty file.
 mvn versions:compare-dependencies -f pom.xml -DremotePom=com.google.cloud:google-cloud-shared-dependencies:LATEST | sed -n '/The following property differences were found:/q;p' | sed '1,/The following differences/d' | awk '!seen[$0]++' | grep -vw 'none' >.versions.txt
 #If the file is empty.
 if ! [ -s .versions.txt ]
 then
   msg "Success! No dependency version differences!"
 else
    msg "Differences found. See below: "
    msg "You can also check .versions.txt file located in $1."
    cat .versions.txt
    return 1
 fi
}

# Allow failures to continue running the script
set +e

error_count=0
for path in $(find -name ".flattened-pom.xml")
do
  # Check flattened pom in each dir that contains it for completeness
  dir=$(dirname "$path")
  pushd "$dir"
  versionsCheck "$dir"
  error_count=$(($error_count + $?))
  popd
done

if [[ $error_count == 0 ]]
then
  msg "All checks passed."
  exit 0
else
  msg "Errors found. See log statements above."
  exit 1
fi