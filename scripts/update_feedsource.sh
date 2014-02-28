#!/bin/bash

SOURCE_DIR=./dl

update_feed()
{
    name="$1"
    src="$2"
    rev="$3"

    if [ -d "$SOURCE_DIR/$name" ]; then
        new_rev=$(cd "$SOURCE_DIR/$name" && git rev-parse --verify HEAD )
    else
        new_rev=$rev
    fi
    echo $name $src $new_rev
}

while read line; do
    update_feed $line
done < feeds.source > .feeds.source.tmp && mv .feeds.source.tmp feeds.source

git ls-files --modified | grep -Fxq feeds.source && git add feeds.source
exit 0
