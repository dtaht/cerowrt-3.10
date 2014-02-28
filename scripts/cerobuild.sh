#!/bin/bash

# Steps to setup build:
# 1. Clone cerowrt repository
# 2. Setup feeds.conf
# 3. Setup new env/, pull from cerofiles
# 4. Install packages
# 5. Copy over .config

CEROFILES_URL="https://github.com/dtaht/cerofiles-next.git"
CEROFILES_REVISION="cerofiles/cerowrt-next"

UPDATE=0
HEAD=0
SOURCE_DIR=./dl
UPDATE_ENV=0
UPDATE_PACKAGES=1
INSTALL_PACKAGES=1
UPDATE_CONFIG=0

usage()
{
    cat >&2 <<EOF
Usage: $0 [-uHEPIC] [-s <source dir>]

 -u:                Update package and files repositories to values specified
                    by currently checked out revision.

 -H:                Use branch HEADs for package and files repositories rather than
                    the commits specified by the config files in the current checkout.
                    (This may break the build in unexpected ways.)

 -e:                Force updating the env/ directory from cerofiles (by default it will be
                    updated if the checked out branch is 'cerobuild', or no env exists).

 -P:                Do not update the package feed source repositories.

 -i/I:              Do/do not (re)install the packages listed in packages.list and
                    override.list in cerofiles (default is to install on first run, not on
                    subsequent runs).

 -c:                Force update (override) of .config from the cerofiles config file.

 -s <source dir>:   Specify source directory to keep package repositories in.
                    Default: $SOURCE_DIR
EOF
    exit 1;
}

error()
{
    warning "$@"
    exit 1
}

warning()
{
    echo "--- $@" >&2
}


clone_repository()
{
    name="$1"
    src="$2"

    [ -d "$SOURCE_DIR/$name" ] || git clone "$src" "$SOURCE_DIR/$name" || error "Unable to clone repository for $name"
} > /dev/null

checkout_rev()
{
    name="$1"
    rev="$2"

    if [ "$HEAD" == "1" ]; then
        ( cd "$SOURCE_DIR/$name" && git checkout master && git pull ) || error "Unable to checkout master of repository $name"
    else
        ( cd "$SOURCE_DIR/$name" && git fetch && git checkout "$rev" ) || error "Unable to checkout $rev for $name"
    fi
}

update_env()
{
    [ -d env ] || echo n | ./scripts/env new cerobuild
    (cd env
    if ! git remote | grep -q cerofiles; then
        git remote add cerofiles "$CEROFILES_URL"
    fi
    if [ "$(git symbolic-ref --short HEAD)" != "cerobuild" -a "$UPDATE_ENV" -eq "0" ]; then
        warning "Current env branch is not cerobuild, not merging cerofiles."
    else
        git fetch cerofiles && git merge --no-edit $CEROFILES_REVISION || error "Unable to merge cerofiles"
    fi)
}

relpath()
{
    source="$1"
    target="$2"

    if which realpath > /dev/null 2>&1; then
        realpath -ms --relative-to "$source" "$target"
    else
        if which python > /dev/null 2>&1 && ! python -V 2>&1 | grep -q '2\.[345]'; then
            # Suitable python (v2.6+) found to be used for relpath.
            python -c "import sys, os.path; sys.stdout.write(os.path.relpath('$target', '$source')+'\n')"
        else
            readlink -f "$target"
        fi
    fi
}

add_feed()
{
    name=$1
    target=$(relpath feeds/ "$SOURCE_DIR/$name")
    echo src-link $name $target >> .feeds.conf.cerobuild
}

[ -e ".git" -a -e "scripts/env" -a -e "scripts/feeds" ] || error "Can't find openwrt build scripts. Script run from wrong dir?"

while getopts "uhHs:ePIic" opt; do
    case $opt in
        u) UPDATE=1;;
        h) usage;;
        H) HEAD=1;;
        s) SOURCE_DIR=$OPTARG;;
        e) UPDATE_ENV=1;;
        P) UPDATE_PACKAGES=0;;
        I) INSTALL_PACKAGES=0;;
        i) INSTALL_PACKAGES=1;;
        C) UPDATE_CONFIG=0;;
        c) UPDATE_CONFIG=1;;
    esac
done

if [ -f .cerobuild.config ]; then
    . .cerobuild.config
fi


if [ -f cerofiles.revision ]; then
    [ "$HEAD" == "0" ] && CEROFILES_REVISION=$(<cerofiles.revision)
else
    echo "--- Warning: No cerofiles.revision file found; using tip of 'cerowrt-next' branch."
fi


[ -e "$SOURCE_DIR" ] || mkdir "$SOURCE_DIR" || error "Unable to create $SOURCE_DIR"

if [ "$UPDATE_PACKAGES" == "1" ]; then
    echo "--- Updating packages..."
    echo -n > .feeds.conf.cerobuild
    while read name src rev; do
        [ -d "$SOURCE_DIR/$name" ] || clone_repository $name $src
        checkout_rev $name $rev
        add_feed $name
    done < feeds.source
    ./scripts/feeds update || error "Couldn't update feed indexes"
    [ -e "feeds.conf" ] || ln -s .feeds.conf.cerobuild feeds.conf
fi

echo "--- Updating env from cerofiles..."
update_env

if [ "$INSTALL_PACKAGES" == "1" ]; then
    echo "--- Installing packages..."
    ./scripts/feeds uninstall $(cat env/override.list) || error "Couldn't uninstall overrides"
    ./scripts/feeds install $(cat env/override.list) || error "Couldn't install overrides"
    ./scripts/feeds install $(cat env/packages.list) || error "Couldn't install packages"
fi

if [ ! -e ".config" -o "$UPDATE_CONFIG" == "1" ]; then
    echo "--- Copying .config and running 'make defconfig'..."
    cp env/config-wndr3700v2 .config || error "Unable to copy .config"
    make defconfig || error "Unable to run defconfig"
else
    if [ -e ".config" ]; then
        echo "--- Not overwriting existing .config"
    fi
fi

cat >.cerobuild.config <<EOF
# cerobuild config created at $(date)
INSTALL_PACKAGES=0
SOURCE_DIR="$SOURCE_DIR"
EOF

echo "--- Build updated. Run make to build."
