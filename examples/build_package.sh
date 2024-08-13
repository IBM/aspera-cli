#!/bin/bash
# Usage: ./build_package.sh <gem_name> <gem_version>
# Example: ./build_package.sh aspera-cli 4.18.0
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <gem_name> <gem_version>"
    exit 1
fi
GNU_TAR=tar
if [ "$(uname)" == "Darwin" ]; then
    GNU_TAR=gtar
fi
gem_name=$1
gem_version=$2
set -e
# temp folder to install gems
tmp_dir_install=.tmp_install
# clean, if there were left overs
rm -fr $tmp_dir_install
# retrieve list of necessary gems
echo "Getting gems $gem_name $gem_version"
gem install $gem_name:$gem_version --no-document --install-dir $tmp_dir_install
archive=$gem_name-$gem_version-gems.tgz
gtar -zcf $archive --directory=$tmp_dir_install/cache/. .
rm -fr $tmp_dir_install
echo "Archive: $archive"
