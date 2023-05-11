#!/bin/bash

set -ex

if [[ $# != 2 ]]; then
  echo "$0 <new version> <bug id>" >&2
  exit 1
fi

CURRENT_LINT_VERSION=$(grep release com/android/tools/lint/lint/maven-metadata.xml | sed "s|.*<release>||;s|</release>||")
NEW_LINT_VERSION=$1
BUG_ID=$2

echo "Upgrading metalava lint dependencies from $CURRENT_LINT_VERSION to $NEW_LINT_VERSION"

MVN_DIR=$(mktemp -d)
if [[ ! "$MVN_DIR" || ! -d "$MVN_DIR" ]]; then
  echo "Could not create temp dir into which maven can be downloaded" >&2
  exit 1
fi

function delete_mvn_dir {
  rm -fr ${MVN_DIR}
}

trap delete_mvn_dir EXIT

# Download and unzip Apache Maven 3.9.2
(
  cd $MVN_DIR
  curl https://dlcdn.apache.org/maven/maven-3/3.9.2/binaries/apache-maven-3.9.2-bin.zip --output apache-maven-3.9.2-bin.zip
  unzip apache-maven-3.9.2-bin.zip
)

MVN_BIN_DIR=$(find $MVN_DIR -name bin)

LINT_MODULES=(
  "com.android.tools.lint:lint-api"
  "com.android.tools.lint:lint-checks"
  "com.android.tools.lint:lint-gradle"
  "com.android.tools.lint:lint"
  "com.android.tools:common"
  "com.android.tools:sdk-common"
  "com.android.tools:sdklib"
)

# Add the bin directory containing maven to the path.
export PATH="$PATH:$MVN_BIN_DIR"

# Update all the lint modules.
for i in ${LINT_MODULES[@]}
do
  ../tools/import-maven-artifacts.sh $i:$NEW_LINT_VERSION
done

# Unused dependencies
#   The following directories contain dependencies of the above LINT_MODULES
#   that are not required and so can be deleted.
UNUSED_DEPS=(
  "com/android/tools/analytics-library"
  "com/android/tools/annotations"
  "com/android/tools/build/aapt2-proto"
  "com/android/tools/build/builder-model"
  "com/android/tools/ddms"
  "com/android/tools/dvlib"
  "com/android/tools/layoutlib"
  "com/android/tools/play-sdk-proto"
)
rm -fr ${UNUSED_DEPS[@]}

# Delete the old dependencies
find -name "${CURRENT_LINT_VERSION}" -type d | xargs rm -fr

# Change Android.bp to use new versions
perl -pi -e "s/$CURRENT_LINT_VERSION/$NEW_LINT_VERSION/g" Android.bp

# Add the changes to git.
git add -u
find -name "${NEW_LINT_VERSION}" -type d | xargs git add

git commit -m "Upgrade metalava lint prebuilts to $NEW_LINT_VERSION

$0 $NEW_LINT_VERSION $BUG_ID

Bug: $BUG_ID
Test: m update-api
"

echo "Please run the following to test before submitting"
echo "    m update-api"
