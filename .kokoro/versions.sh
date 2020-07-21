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
 #Grab the dependencyManagement section, turn them into dependencies, and use those
 #to compare with the online version.
 before_depM="$(sed -n '/dependencyManagement/q;p' pom.xml)"
 new_deps="$(sed '1,/dependencyManagement/d' pom.xml | sed -n '/dependencyManagement/q;p' | sed '/<!--/d')"
 line_to_add=$(grep -n -m 1 'dependencyManagement' pom.xml | cut -d: -f1)
 after_depM="$(sed -n "${line_to_add}"',$p' pom.xml)"
 #Concatenate before starting depM section, new deps, and after starting depM section.
 complete_file=$before_depM$new_deps$after_depM
 echo "$complete_file" > .temp-pom.xml
 msg "Comparing dependency management versions with latest google-cloud shared BOM..."
 #Use versions plugin, specifying our remote POM as the most recent shared dependencies BOM.
 #Filter out any lines that don't have anything to do with our dependency version differences.
 #Remove duplicate lines.
 #If we list 'none' for our different dependencies versions, filter it for an empty file.
 mvn versions:compare-dependencies -f .temp-pom.xml -DremotePom=com.google.cloud:google-cloud-shared-dependencies:LATEST | sed -n '/The following property differences were found:/q;p' | sed '1,/The following differences/d' | awk '!seen[$0]++' | grep -vw 'none' >.versions.txt
 rm -f .temp-pom.xml
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

dir=$(dirname "./pom.xml")
versionsCheck "$dir"

if [[ $? == 0 ]]
then
  msg "All checks passed."
  exit 0
else
  msg "Errors found. See log statements above."
  exit 1
fi