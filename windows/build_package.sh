#!/bin/bash
# Usage: ./build_package.sh <gem_name> <gem_version>
# Example: ./build_package.sh aspera-cli 4.18.0
set -e
if [ "$#" -lt 2 -o "$#" -gt 3 ]; then
    echo "Usage: $0 <gem_name> <gem_version> [<method>]"
    exit 1
fi
gem_name=$1
gem_version=$2
archtype=${3:-tgz}
echo $archtype
# on macOS, GNU tar is gtar
GNU_TAR=tar
if [ "$(uname)" == "Darwin" ]; then
    GNU_TAR=gtar
fi
# temp folder to install gems
tmp_dir_install=.tmp_install
# clean, if there were left overs
rm -fr $tmp_dir_install
# retrieve list of necessary gems
echo "Getting gems $gem_name $gem_version"
# install gems in a temporary folder
gem install $gem_name:$gem_version --no-document --install-dir $tmp_dir_install
archive=$PWD/$gem_name-$gem_version-gems.$archtype
rm -f $archive
# .gem files are located in cache folder
case $archtype in
tgz)
    $GNU_TAR -zcf $archive --directory=$tmp_dir_install/cache/. .
    ;;
zip)
    pushd $tmp_dir_install/cache
    zip -r $archive *
    popd
    ;;
*)
    echo "ERROR: $archive"
    exit 1
esac
rm -fr $tmp_dir_install
echo "Archive: $archive"
