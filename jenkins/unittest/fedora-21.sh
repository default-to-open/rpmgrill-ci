#! /usr/bin/env bash
set -e -u

declare -r SCRIPT_PATH=$(readlink -f $0)
declare -r SCRIPT_DIR=$(cd $(dirname $SCRIPT_PATH) && pwd)
declare -r LIB_DIR=$(readlink -f $SCRIPT_DIR/../../lib/)

source $LIB_DIR/utils.bash
source $LIB_DIR/docker.bash
source $SCRIPT_DIR/lib/unittest.bash
source $SCRIPT_DIR/lib/fedora_job.bash

unittest_run fedora:21 "$@"
