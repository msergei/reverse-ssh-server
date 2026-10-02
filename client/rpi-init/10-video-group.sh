#!/bin/bash
# The image grants abc access to /dev/dri only; give it the V4L2 encoder too
gid=$(stat -c '%g' /dev/video11) || exit 0
name=$(getent group "$gid" | cut -d: -f1)
[ -n "$name" ] || { name=hostvideo; groupadd -g "$gid" "$name"; }
usermod -a -G "$name" abc
