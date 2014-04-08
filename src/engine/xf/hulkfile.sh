#!/bin/bash
#
# hulkfile callbacks
# Copyright (c) 2013 Plowshare team
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

declare -gA HULKFILE_FUNCS
HULKFILE_FUNCS['dl_parse_error']='hulkfile_dl_parse_error'
HULKFILE_FUNCS['dl_parse_countdown']='hulkfile_dl_parse_countdown'

hulkfile_dl_parse_error() {
    local PAGE=$1

    PAGE=$(replace '<div class="err">' '' <<< "$PAGE")

    xfilesharing_dl_parse_error_generic "$PAGE"
}

hulkfile_dl_parse_countdown () {
    local -r PAGE=$1
    local WAIT_TIME

    WAIT_TIME=$(parse_tag_quiet 'font-family:tahoma; font-size:28pt;' 'span' <<< "$PAGE")

    echo "$WAIT_TIME"
}
