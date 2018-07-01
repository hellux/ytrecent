#!/usr/bin/env bash

warn() {
    echo -e "warning: $@" 1>&2
}
die() {
    echo -e "error: $@" 1>&2
    exit 1
}

if [ -z "$XDG_CACHE_HOME" ];
then CCH_DIR="$HOME/.cache/ytrecent"
else CCH_DIR="$XDG_CACHE_HOME/ytrecent"
fi
if [ -z "$XDG_RUNTIME_DIR" ]; then
    RNT_DIR="$CCH_DIR/runtime"
    warn "XDG_RUNTIME_DIR not set, using $CCH_DIR as fallback"
else
    RNT_DIR="$XDG_RUNTIME_DIR/ytrecent"
fi
if [ -z "$XDG_CONFIG_HOME" ];
then CFG_DIR="$HOME/.config/ytrecent"
else CFG_DIR="$XDG_CONFIG_HOME/ytrecent"
fi

# channel id file format:
# <channel1_id> <channel1_name>
# <channel2_id> <channel2_name>
#      :               :
CHID_FILE="$CFG_DIR/channel_ids"
CHIDS_TMP="$RNT_DIR/chids"
ENTRIES_TMP="$RNT_DIR/entries"
COL_ID=$CCH_DIR/col_id
COL_AUTHOR=$CCH_DIR/col_author
COL_TITLE=$CCH_DIR/col_title
COL_DATE=$CCH_DIR/col_date

# format of date output, will be used for sorting
DATE_FMT="%a %e %b"
# truncate titles longer than below
TITLE_LEN=70

USAGE="Usage: $0 action... [-r]"

# regex to channel ids
CHID_REGEX="^[a-zA-Z0-9\_-]{24}$"
# start of urls to rss feeds with recent videos
FEED_URL="https://www.youtube.com/feeds/videos.xml?channel_id="

fetch=false
list=false
clean=false
recode=false
cols="$COL_AUTHOR $COL_TITLE $COL_DATE $COL_ID"

while getopts frlch flag; do
    case "$flag" in
        f) fetch=true;;
        r) recode=true;;
        l) list=true;;
        c) clean=true;;
        h) echo "$USAGE"; exit 0;;
        [?]) echo "$USAGE"; exit 1;;
	esac
done
shift $((OPTIND-1))

if [ "$fetch" = "false" -a "$list" = "false" -a "$clean" = "false" ]; then
    die "no action specified" "\n$USAGE"
fi

if [ -n "$1" ]; then
    die "excess arguments" "\n$USAGE"
fi

set -u

if [ "$fetch" = "true" ]; then
    if [ "$recode" = "true" -a ! -x "$(command -v recode)" ]; then
        warn "'recode' not installed, HTML encodings will remain"
        recode=false
    fi

    if date -v 1d > /dev/null 2>&1;
    then BSD_DATE=true
    else BSD_DATE=false
    fi

    FEEDS_DIR="$RNT_DIR/feeds"
    mkdir -p $RNT_DIR || exit 1
    mkdir -p $CCH_DIR || exit 1
    mkdir -p $FEEDS_DIR || exit 1
    rm -f $ENTRIES_TMP || exit 1

    if [ ! -r $CHID_FILE ]; then
        die "no file with channel IDs found at $CHID_FILE"
    fi

    # rm comments from CHID_FILE
    sed 's:#.*$::g;/^\-*$/d' $CHID_FILE > ${CHIDS_TMP}_stripped
    # rm invalid chids
    while read chid author; do
        if echo $chid | grep -q -E $CHID_REGEX;
        then echo "$chid $author"
        else warn "invalid channel id -- $chid"
        fi
    done < ${CHIDS_TMP}_stripped > $CHIDS_TMP
    rm ${CHIDS_TMP}_stripped

    # fetch rss feeds
    curl -s $(while read chid author; do
        printf '%s%s -o %s/%s ' "$FEED_URL" "$chid" "$FEEDS_DIR" "$chid"
    done < $CHIDS_TMP)

    # parse channels
    while read chid author; do
        feed_file=$FEEDS_DIR/$chid

        # parse videos from channel
        while IFS=\> read -d \< tag content; do
            if [ "$tag" = "yt:videoId" ]; then
                printf "%s\t" "$content"
            elif [ "$tag" = "title" ]; then
                title=$content
                printf "%s\t%s\t" "$author" "$title"
            elif [ "$tag" = "published" ]; then
                date_utc=$content
                if [ "$BSD_DATE" = "true" ]; then
                    date=$(date -jf "%FT%T+00:00 %Z" \
                           "$date_utc UTC" "+$DATE_FMT")
                else 
                    date=$(date -d "$date_utc" +"$DATE_FMT")
                fi
                printf "%s\t%s\n" "$date_utc" "$date"
            fi
        done < $feed_file | tail -n +2 >> $ENTRIES_TMP
    done < $CHIDS_TMP
    rm $CHIDS_TMP
    rm -r $FEEDS_DIR

    # sort, postprocess, place columns in separate files
    sort -t $'\t' -k 4 $ENTRIES_TMP -o $ENTRIES_TMP
    cut -f 1 $ENTRIES_TMP > $COL_ID
    cut -f 2 $ENTRIES_TMP > $COL_AUTHOR
    cut -f 3 $ENTRIES_TMP > $COL_TITLE
    cut -f 5 $ENTRIES_TMP > $COL_DATE
    [ "$recode" = "true" ] && recode -f -q html..ascii $COL_TITLE
    cut -c1-$TITLE_LEN $COL_TITLE > ${COL_TITLE}_tr
    mv ${COL_TITLE}_tr $COL_TITLE
    rm -rf $RNT_DIR
else
    if [ ! -r $COL_ID -o ! -r $COL_AUTHOR -o \
         ! -r $COL_TITLE -o ! -r $COL_DATE ]; then
        die "no cache found in $CCH_DIR"
    fi
fi

if [ "$list" = "true" ]; then
    mkdir -p $RNT_DIR
    paste $cols > $ENTRIES_TMP
    column -t -s $'\t' $ENTRIES_TMP
    rm -rf $RNT_DIR
fi

if [ "$clean" = "true" ]; then
    rm -f $COL_AUTHOR $COL_TITLE $COL_DATE $COL_ID
fi
