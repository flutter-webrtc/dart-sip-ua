#!/bin/bash
ROOT_DIR=$(cd `dirname $0`/../; pwd)

export PATH="/usr/local/opt/dart@1/bin:$PATH"

dart --version
cd $ROOT_DIR/lib/src
dart $ROOT_DIR/tool/peg/bin/peg.dart general grammar.peg