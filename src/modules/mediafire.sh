#!/bin/bash
#
# mediafire.com module
# Copyright (c) 2011 Plowshare team
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

MODULE_MEDIAFIRE_REGEXP_URL="http://\(www\.\)\?mediafire\.com/"

MODULE_MEDIAFIRE_DOWNLOAD_OPTIONS="
LINK_PASSWORD,p:,link-password:,PASSWORD,Used in password-protected files"
MODULE_MEDIAFIRE_DOWNLOAD_RESUME=no
MODULE_MEDIAFIRE_DOWNLOAD_FINAL_LINK_NEEDS_COOKIE=no

MODULE_MEDIAFIRE_UPLOAD_OPTIONS="
AUTH_FREE,b:,auth-free:,USER:PASSWORD,Use Free account"
MODULE_MEDIAFIRE_LIST_OPTIONS=""

# Output a mediafire file download URL
# $1: cookie file
# $2: mediafire.com url
# stdout: real file download link
mediafire_download() {
    eval "$(process_options mediafire "$MODULE_MEDIAFIRE_DOWNLOAD_OPTIONS" "$@")"

    local COOKIEFILE="$1"
    local URL="$2"
    local LOCATION PAGE FILE_URL FILENAME

    detect_javascript || return

    LOCATION=$(curl --head "$URL" | grep_http_header_location) || return

    if match '^http://download' "$LOCATION"; then
        log_debug "direct download"
        echo "$LOCATION"
        return 0
    elif match 'errno=999$' "$LOCATION"; then
        return $ERR_LINK_NEED_PERMISSIONS
    elif match 'errno=320$' "$LOCATION"; then
        return $ERR_LINK_DEAD
    elif match 'errno=378$' "$LOCATION"; then
        return $ERR_LINK_DEAD
    elif match 'errno=' "$LOCATION"; then
        log_error "site redirected with an unknown error"
        return $ERR_FATAL
    fi

    PAGE=$(curl -L -c $COOKIEFILE "$URL" | break_html_lines) || return

    if test "$CHECK_LINK"; then
        match 'class="download_file_title"' "$PAGE" && return 0
        return $ERR_LINK_DEAD
    fi

    # reCaptcha
    if match '<textarea name="recaptcha_challenge_field"' "$PAGE"; then

        local PUBKEY WCI CHALLENGE WORD ID
        PUBKEY='6LextQUAAAAAALlQv0DSHOYxqF3DftRZxA5yebEe'
        WCI=$(recaptcha_process $PUBKEY) || return
        { read WORD; read CHALLENGE; read ID; } <<<"$WCI"

        PAGE=$(curl -b "$COOKIEFILE" --data \
            "recaptcha_challenge_field=$CHALLENGE&recaptcha_response_field=$WORD" \
            -H "X-Requested-With: XMLHttpRequest" --referer "$URL" \
            "$URL" | break_html_lines) || return

        # You entered the incorrect keyword below, please try again!
        if match 'incorrect keyword' "$PAGE"; then
            recaptcha_nack $ID
            log_error "Wrong captcha"
            return $ERR_CAPTCHA
        fi

        recaptcha_ack $ID
        log_debug "correct captcha"
    fi

    # When link is password protected, there's no facebook "I like" box (iframe).
    # Use that trick!
    if ! match 'facebook.com/plugins/like' "$PAGE"; then
        log_error "Password-protected links are not supported"
        return $ERR_LINK_PASSWORD_REQUIRED

        # FIXME
        #log_debug "File is password protected"
        #if [ -z "$LINK_PASSWORD" ]; then
        #    LINK_PASSWORD=$(prompt_for_password) || return
        #fi
        #PAGE=$(curl -L -b "$COOKIEFILE" --data "downloadp=$LINK_PASSWORD" "$URL" | break_html_lines) || return
    fi

    FILE_URL=$(echo "$PAGE" | parse_attr "<div.*download_link" "href") || return
    FILENAME=$(curl -I "$FILE_URL" | grep_http_header_content_disposition) || return

    echo "$FILE_URL"
    test -n "$FILENAME" && echo "$FILENAME"
}

# Upload a file to mediafire
# $1: cookie file
# $2: input file (with full path)
# $3: remote filename
# stdout: mediafire.com download link
mediafire_upload() {
    eval "$(process_options mediafire "$MODULE_MEDIAFIRE_UPLOAD_OPTIONS" "$@")"

    local COOKIEFILE="$1"
    local FILE="$2"
    local DESTFILE="$3"
    local SZ=$(get_filesize "$FILE")
    local BASE_URL='http://www.mediafire.com'
    local XML UKEY USER FOLDER_KEY MFUL_CONFIG UPLOAD_KEY QUICK_KEY TRY

    if [ -n "$AUTH_FREE" ]; then
        # Get ukey cookie entry (mandatory)
        curl -c "$COOKIEFILE" -o /dev/null "$BASE_URL"

        # HTTPS login (login_remember=on not required)
        LOGIN_DATA='login_email=$USER&login_pass=$PASSWORD&submit_login=Login+to+MediaFire'
        LOGIN_RESULT=$(post_login "$AUTH_FREE" "$COOKIEFILE" "$LOGIN_DATA" \
                'https://www.mediafire.com/dynamic/login.php?popup=1' "-b $COOKIEFILE")

        # If successful, two entries are added into cookie file: user and session
        SESSION=$(parse_cookie 'session' < "$COOKIEFILE")
        if [ -z "$SESSION" ]; then
            log_error "login process failed"
            return $ERR_FATAL
        fi
    fi

    # Warning message
    if [ "$SZ" -gt 209715200 ]; then
        log_error "warning: file is bigger than 200MB, site may not support it"
    fi

    log_debug "Get uploader configuration"
    XML=$(curl -b "$COOKIEFILE" "$BASE_URL/basicapi/uploaderconfiguration.php?$$" | break_html_lines) ||
            { log_error "Couldn't upload file!"; return 1; }

    UKEY=$(echo "$XML" | parse_quiet ukey '<ukey>\([^<]*\)<\/ukey>')
    USER=$(echo "$XML" | parse_quiet user '<user>\([^<]*\)<\/user>')
    FOLDER_KEY=$(echo "$XML" | parse_quiet folderkey '<folderkey>\([^<]*\)<\/folderkey>')
    MFUL_CONFIG=$(echo "$XML" | parse_quiet MFULConfig '<MFULConfig>\([^<]*\)<\/MFULConfig>')

    log_debug "folderkey: $FOLDER_KEY"
    log_debug "ukey: $UKEY"
    log_debug "MFULConfig: $MFUL_CONFIG"

    if [ -z "$UKEY" -o -z "$FOLDER_KEY" -o -z "$MFUL_CONFIG" -o -z "$USER" ]; then
        log_error "Can't parse uploader configuration!"
        return $ERR_FATAL
    fi

    # HTTP header "Expect: 100-continue" seems to confuse server
    # Note: -b "$COOKIEFILE" is not required here
    XML=$(curl_with_log -0 \
        -F "Filename=$DESTFILE" \
        -F "Upload=Submit Query" \
        -F "Filedata=@$FILE;filename=$DESTFILE" \
        --user-agent "Shockwave Flash" \
        --referer "$BASE_URL/basicapi/uploaderconfiguration.php?$$" \
        "$BASE_URL/douploadtoapi/?type=basic&ukey=$UKEY&user=$USER&uploadkey=$FOLDER_KEY&upload=0") || return

    # Example of answer:
    # <?xml version="1.0" encoding="iso-8859-1"?>
    # <response>
    #  <doupload>
    #   <result>0</result>
    #   <key>sf22seu6p7d</key>
    #  </doupload>
    # </response>
    UPLOAD_KEY=$(echo "$XML" | parse_quiet 'key' '<key>\([^<]*\)<\/key>')

    # Get error code (<result>)
    if [ -z "$UPLOAD_KEY" ]; then
        local ERR_CODE=$(echo "$XML" | parse_quiet 'result' '<result>\([^<]*\)')
        log_error "mediafire internal error: ${ERR_CODE:-n/a}"
        return $ERR_FATAL
    fi

    log_debug "polling for status update (with key $UPLOAD_KEY)"

    for TRY in 1 2 3; do
        wait 2 seconds || return

        XML=$(curl "$BASE_URL/basicapi/pollupload.php?key=$UPLOAD_KEY&MFULConfig=$MFUL_CONFIG") || return
        if match '<description>No more requests for this key</description>' "$XML"; then
            QUICK_KEY=$(echo "$XML" | parse_quiet 'quickkey' '<quickkey>\([^<]*\)<\/quickkey>')

            echo "$BASE_URL/?$QUICK_KEY"
            return 0
        fi
    done

    log_error "Can't get quick key!"
    return $ERR_FATAL
}

# List a mediafire shared file folder URL
# $1: mediafire folder url (http://www.mediafire.com/?sharekey=...)
# $2: recurse subfolders (null string means not selected)
# stdout: list of links
mediafire_list() {
    local URL="$1"

    PAGE=$(curl "$URL" | break_html_lines_alt)

    if ! match '/js/myfiles.php/' "$PAGE"; then
        log_error "not a shared folder"
        return $ERR_FATAL
    fi

    local JS_URL=$(echo "$PAGE" | parse 'LoadJS(' '("\(\/js\/myfiles\.php\/[^"]*\)')
    local DATA=$(curl "http://mediafire.com$JS_URL" | sed "s/\([)']\);/\1;\n/g")

    # get number of files
    NB=$(echo "$DATA" | parse '^var oO' "'\([[:digit:]]*\)'")

    log_debug "There is $NB file(s) in the folder"

    # print filename as debug message & links (stdout)
    # es[0]=Array('1','1',3,'te9rlz5ntf1','82de6544620807bf025c12bec1713a48','my_super_file.txt','14958589','14.27','MB','43','02/13/2010', ...
    DATA=$(echo "$DATA" | grep 'es\[' | tr -d "'" | delete_last_line)
    while IFS=, read -r _ _ _ FID _ FILENAME _; do
        log_debug "$FILENAME"
        echo "http://www.mediafire.com/?$FID"
    done <<< "$DATA"

    # Alternate (more portable?) version:
    #
    # while read LINE; do
    #     FID=$(echo "$LINE" | cut -d, -f4)
    #     FILENAME=$(echo "$LINE" | cut -d, -f6)
    #     log_debug "$FILENAME"
    #     echo "http://www.mediafire.com/?$FID"
    # done <<< "$DATA"

    return 0
}
