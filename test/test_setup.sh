#!/bin/bash
#
# Test functions for install script "setup.sh"
# Copyright (c) 2010 Arnau Sanchez
#
# Note that *-auth files are not in the source code, you need to create
# them with your accounts if you want to run the function test suite.
#
# This file is part of Plowshare.
#
# Plowshare is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Plowshare is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Plowshare.  If not, see <http://www.gnu.org/licenses/>.

set -e

ROOTDIR=$(dirname $(dirname "$(readlink -f "$0")"))
SRCDIR=$ROOTDIR/src
TESTSDIR=$ROOTDIR/test
source $ROOTDIR/src/core.sh
source $ROOTDIR/test/lib.sh

### Setup script

PREFIX=/usr
EXPECTED_INSTALLED="bin
bin/plowdel
bin/plowdown
bin/plowlist
bin/plowup
share
share/doc
share/doc/plowshare
share/doc/plowshare/README
share/man
share/man/man1
share/man/man1/plowdel.1
share/man/man1/plowdown.1
share/man/man1/plowlist.1
share/man/man1/plowup.1
share/plowshare
share/plowshare/delete.sh
share/plowshare/download.sh
share/plowshare/core.sh
share/plowshare/list.sh
share/plowshare/modules
share/plowshare/modules/115.sh
share/plowshare/modules/2shared.sh
share/plowshare/modules/4shared.sh
share/plowshare/modules/badongo.sh
share/plowshare/modules/config
share/plowshare/modules/data_hu.sh
share/plowshare/modules/depositfiles.sh
share/plowshare/modules/divshare.sh
share/plowshare/modules/dl_free_fr.sh
share/plowshare/modules/hotfile.sh
share/plowshare/modules/humyo.sh
share/plowshare/modules/mediafire.sh
share/plowshare/modules/megaupload.sh
share/plowshare/modules/netload_in.sh
share/plowshare/modules/rapidshare.sh
share/plowshare/modules/sendspace.sh
share/plowshare/modules/uploading.sh
share/plowshare/modules/usershare.sh
share/plowshare/modules/x7_to.sh
share/plowshare/modules/zshare.sh
share/plowshare/strip_single_color.pl
share/plowshare/strip_threshold.pl
share/plowshare/tesseract
share/plowshare/tesseract/alnum
share/plowshare/tesseract/digit
share/plowshare/tesseract/digit_ops
share/plowshare/tesseract/plowshare_nobatch
share/plowshare/tesseract/upper
share/plowshare/upload.sh"

EXPECTED_UNINSTALLED="bin
share
share/doc
share/man
share/man/man1"

test_setup_script() {
    TEMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/plowshare.XXXXXXXX")

    assert_return 0 "PREFIX=$PREFIX DESTDIR=$TEMPDIR $ROOTDIR/setup.sh install" || return 1
    INSTALLED=$(find "$TEMPDIR$PREFIX" | sed "s#^$TEMPDIR$PREFIX/\?##" | sed '/^$/d' | sort)
    assert_equal_with_diff "$EXPECTED_INSTALLED"  "$INSTALLED" || return 1
    assert_return 0 "PREFIX=$PREFIX DESTDIR=$TEMPDIR $ROOTDIR/setup.sh uninstall" || return 1
    assert_equal "$EXPECTED_UNINSTALLED" \
        "$(find "$TEMPDIR$PREFIX" | sed "s#^$TEMPDIR$PREFIX/\?##" | sed '/^$/d' | sort)" || return 1

    rm -rf $TEMPDIR
}

test_man_pages() {
    find "$ROOTDIR/docs" -name "*.1" | while read PAGE; do
        RES=$(LANG=C MANWIDTH=80 man --warnings -l "$PAGE" 2>&1 1>/dev/null)
        assert_equal "${#RES}" 0 || return 1
    done
}

run_tests "$@"
