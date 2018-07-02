#!/usr/bin/env bash

warn() {
    echo -e "warning: $@" 1>&2
}
die() {
    echo -e "error: $@" 1>&2
    exit 1
}

fetch() {
    USAGE="usage: $0 fetch [-l] [-r]"
    list=false
    while getopts :rl flag; do
        case "$flag" in
            l) list=true;;
            [?]) die "invalid flag -- $OPTARG"
        esac
    done
    shift $((OPTIND-1))
    [ -n "$1" ] && die "excess arguments" "\n$USAGE"

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
    [ $? -ne 0 ] && die "unable to fetch videos, connection failed"

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

    # sort, place columns in separate files, postprocess
    sort -t $'\t' -k 4 $ENTRIES_TMP -o $ENTRIES_TMP
    cut -f 1 $ENTRIES_TMP > $COL_ID
    cut -f 2 $ENTRIES_TMP > $COL_AUTHOR
    cut -f 3 $ENTRIES_TMP > $COL_TITLE
    cut -f 5 $ENTRIES_TMP > $COL_DATE
    # replace html entities
    sed "s/&nbsp;/ /g;
        s/&amp;/\&/g;
        s/&lt;/\</g;
        s/&gt;/\>/g;
        s/&quot;/\"/g;
        s/&ldquo;/\"/g;
        s/&rdquo;/\"/g;" $COL_TITLE > ${COL_TITLE}_rc
    mv ${COL_TITLE}_rc $COL_TITLE
    cut -c1-$TITLE_LEN $COL_TITLE > ${COL_TITLE}_tr
    mv ${COL_TITLE}_tr $COL_TITLE
    rm -rf $RNT_DIR
    cache_available=true
    cache_count=$(wc -l < $COL_ID)
    [ "$list" = "true" ] && list
}
list() {
    USAGE="usage: $0 list"
    [ -n "$1" ] && die "excess arguments" "\n$USAGE"
    [ "$cache_available" = "false" ] && die "no video list found in $CCH_DIR"

    cols="$COL_NUM $COL_AUTHOR $COL_TITLE $COL_DATE"
    mkdir -p $RNT_DIR
    pad=$(expr $(echo $cache_count | wc -c) - 1)
    echo $len 1>&2
    rm -f $COL_NUM
    for i in $(seq $cache_count -1 1); do
        printf "[%${pad}s]\n" "$i" >> $COL_NUM
    done

    paste $cols > $ENTRIES_TMP
    column -t -s $'\t' $ENTRIES_TMP
    rm -rf $RNT_DIR
}
watch() {
    USAGE="usage: $0 watch video_number..."

    [ "$cache_available" = "false" ] && die "no video list found in $CCH_DIR"
    [ -z $1 ] && die "no video specifed" "\n$USAGE"
    
    for num in $@; do
        if [ "1" -le "$num" -a "$num" -le "$cache_count" ] 2>/dev/null; then
            lineno=$(expr $cache_count - $num + 1)
            video_id=$(sed "${lineno}q;d" $COL_ID) # pick out specific line
            video_url=$VIDEO_URL$video_id
            mpv $video_url
        else
            die "invalid video number -- $num" "\n$USAGE"
        fi
    done
}
clean() {
    rm -f $COL_AUTHOR $COL_TITLE $COL_DATE $COL_ID
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
COL_NUM=$RNT_DIR/col_num
COL_ID=$CCH_DIR/col_id
COL_AUTHOR=$CCH_DIR/col_author
COL_TITLE=$CCH_DIR/col_title
COL_DATE=$CCH_DIR/col_date

# format of date output, will be used for sorting
DATE_FMT="%a %e %b"
# truncate titles longer than below
TITLE_LEN=70

USAGE="usage: $0 action [option]..."

# regex to channel ids
CHID_REGEX="^[a-zA-Z0-9\_-]{24}$"
# start of urls to rss feeds with recent videos
FEED_URL="https://www.youtube.com/feeds/videos.xml?channel_id="
VIDEO_URL="https://www.youtube.com/watch?v="

operation=$1
shift

if [ -z "$operation" ]; then
    die "no action specified" "\n$USAGE"
fi

if [ -r $COL_ID -a -r $COL_AUTHOR -a -r $COL_TITLE -a -r $COL_DATE ]
then
    cache_available=true
    cache_count=$(wc -l < $COL_ID)
else
    cache_available=false
fi

case $operation in
    fetch) fetch $@;;
    list) list $@;;
    watch) watch $@;;
    *) die "invalid operation -- $operation";;
esac

exit 0
