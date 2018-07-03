#!/usr/bin/env bash

warn() {
    echo -e "warning: $@" 1>&2
}
die() {
    echo -e "error: $@" 1>&2
    exit 1
}

fetch_cmd() {
    list=false
    while getopts :l flag; do
        case "$flag" in
            l) list=true;;
            [?]) die "invalid flag -- $OPTARG"
        esac
    done
    shift $((OPTIND-1))
    [ -n "$1" ] && die "excess arguments" "\n\n$USAGE_FETCH"
    [ ! -r $CHID_FILE ] && die "no file with channel IDs found at $CHID_FILE"

    mkdir -p $CCH_DIR || exit 1
    mkdir -p $RNT_DIR || exit 1
    rm -f $ENTRIES_TMP || exit 1

    # rm comments from CHID_FILE
    sed 's:#.*$::g;/^\-*$/d' $CHID_FILE > ${CHIDS_TMP}_stripped
    # rm invalid chids
    CHID_REGEX="^[a-zA-Z0-9\_-]{24}$"
    while read chid author; do
        if echo $chid | grep -q -E $CHID_REGEX;
        then echo "$chid $author"
        else warn "invalid channel id -- $chid"
        fi
    done < ${CHIDS_TMP}_stripped > $CHIDS_TMP
    rm ${CHIDS_TMP}_stripped

    # fetch rss feeds
    FEED_URL="https://www.youtube.com/feeds/videos.xml?channel_id="
    curl -s $(while read chid author; do
        printf '%s%s -o %s/%s ' "$FEED_URL" "$chid" "$RNT_DIR" "$chid"
    done < $CHIDS_TMP)
    [ $? -ne 0 ] && die "unable to fetch videos, connection failed"

    # parse channels
    while read chid author; do
        feed_file=$RNT_DIR/$chid

        # parse videos from channel
        while IFS=\> read -d \< tag content; do
            if [ "$tag" = "yt:videoId" ]; then
                printf "%s\t" "$content"
            elif [ "$tag" = "title" ]; then
                printf "%s\t%s\t" "$author" "$content"
            elif [ "$tag" = "published" ]; then
                printf "%s\n" "$content"
            fi
        done < $feed_file | tail -n +2 >> $ENTRIES_TMP
    done < $CHIDS_TMP
    rm $CHIDS_TMP

    # sort, place columns in separate files, postprocess
    sort -t $'\t' -k 4 $ENTRIES_TMP -o $ENTRIES_TMP
    cut -f 1 $ENTRIES_TMP > $COL_ID
    cut -f 2 $ENTRIES_TMP > $COL_AUTHOR
    cut -f 3 $ENTRIES_TMP > $COL_TITLE
    cut -f 4 $ENTRIES_TMP > $COL_DATE
    cache_available=true
    cache_count=$(wc -l < $COL_ID)
    # replace html entities
    sed "s/&nbsp;/ /g;
        s/&amp;/\&/g;
        s/&lt;/\</g;
        s/&gt;/\>/g;
        s/&quot;/\"/g;
        s/&ldquo;/\"/g;
        s/&rdquo;/\"/g;" $COL_TITLE > ${COL_TITLE}_rc
    mv ${COL_TITLE}_rc $COL_TITLE
    rm -rf $RNT_DIR

    [ "$list" = "true" ] && list_cmd
}
list_cmd() {
    COLS_DEF="NaTD"
    cols=""
    while getopts :nNatTdDi flag; do
        case "$flag" in
            n) cols="$cols $COL_NUM_ZERO";;
            N) cols="$cols $COL_NUM_PAD";;
            a) cols="$cols $COL_AUTHOR";;
            t) cols="$cols $COL_TITLE";;
            T) cols="$cols $COL_TITLE_TR";;
            d) cols="$cols $COL_DATE";;
            D) cols="$cols $COL_DATE_FMT";;
            i) cols="$cols $COL_ID";;
            [?]) die "invalid column -- $OPTARG"
        esac
    done
    shift $((OPTIND-1))
    [ -n "$1" ] && die "excess arguments" "\n\n$USAGE_LIST"
    [ -z "$cols" ] && list_cmd -$COLS_DEF && exit 0;
    [ "$cache_available" = "false" ] && die "no video list found in $CCH_DIR"

    mkdir -p $RNT_DIR
    # truncate titles
    cut -c1-$YTR_TITLE_LEN $COL_TITLE > $COL_TITLE_TR
    # attach numbers to videos
    pad=$(expr $(echo $cache_count | wc -c) - 1) # max width of video number
    for num in $(seq $cache_count -1 1); do
        printf "%d\n" "$num"
    done > $COL_NUM
    while read num; do
        printf "%0${pad}d\n" "$num"
    done < $COL_NUM > $COL_NUM_ZERO
    while read num; do
        printf "[%${pad}s]\n" "$num"
    done < $COL_NUM > $COL_NUM_PAD
        
    # format date
    DATE_FMT="%a %e %b %R"
    if date -v 1d > /dev/null 2>&1;
    then BSD_DATE=true
    else BSD_DATE=false
    fi
    while read date; do
        if [ "$BSD_DATE" = "true" ]
        then date -jf "%FT%T+00:00 %Z" "$date UTC" "+$DATE_FMT"
        else date -d "$date" +"$DATE_FMT"
        fi
    done < $COL_DATE > $COL_DATE_FMT

    paste $cols > $ENTRIES_TMP
    column -t -s $'\t' $ENTRIES_TMP
    rm -rf $RNT_DIR
}
watch_cmd() {
    VIDEO_URL="https://www.youtube.com/watch?v="

    [ "$cache_available" = "false" ] && die "no video list found in $CCH_DIR"
    [ -z $1 ] && die "no video specifed" "\n\n$USAGE_WATCH"
    
    for num in $@; do
        if [ "1" -le "$num" -a "$num" -le "$cache_count" ] 2>/dev/null; then
            lineno=$(expr $cache_count - $num + 1)
            video_id=$(sed "${lineno}q;d" $COL_ID) # pick out specific line
            video_url=$VIDEO_URL$video_id
            $YTR_PLAYER $video_url
        else
            die "invalid video number -- $num" "\n\n$USAGE_WATCH"
        fi
    done
}
clean_cmd() {
    rm -rf $CCH_DIR
}
help_cmd() {
    echo "ytrecent -- YouTube channel tracker"
    echo -e "\n$USAGE"
    echo -e "\ndescription:
    ytr -- "YouTube recent" -- is a utility for keeping up with YouTube
    channels from the command line. It serves a similar purpose to YouTube
    subscriptions, but no YouTube account is required. Channels are specified
    in $CHID_FILE with the following format:
        <channel1 id> <name1>
        <channel2 id> <name2>
             :           :
    'ytr fetch' then parses these IDs and fetches RSS feeds from youtube.com
    which contain links to the most recent 15 videos of the corresponding
    channel. Videos are then sorted by date of publish and displayed with 'ytr
    list'. 'ytr watch' can be used to play these videos immediately through an
    external video player or web browser."
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

[ -z "$YTR_PLAYER" ] && YTR_PLAYER=mpv
[ -z "$YTR_TITLE_LEN" ] && YTR_TITLE_LEN=80

# channel id file format:
# <channel1_id> <channel1_name>
# <channel2_id> <channel2_name>
#      :               :
CHID_FILE="$CFG_DIR/channel_ids"
CHIDS_TMP="$RNT_DIR/chids"
ENTRIES_TMP="$RNT_DIR/entries"
# cached columns
COL_ID=$CCH_DIR/col_id
COL_AUTHOR=$CCH_DIR/col_author
COL_TITLE=$CCH_DIR/col_title
COL_DATE=$CCH_DIR/col_date
# tmp postprocess columns
COL_NUM=$RNT_DIR/col_num
COL_NUM_ZERO=$RNT_DIR/col_num_zero
COL_NUM_PAD=$RNT_DIR/col_num_pad
COL_TITLE_TR=$RNT_DIR/col_title_tr
COL_DATE_FMT=$RNT_DIR/col_date_fmt

USAGE="usage: ytr <command> [<args>]

commands:
    fetch   -- fetch list of videos from channels to a cache
    list    -- display cached list of videos
    watch   -- play videos
    clean   -- clear cached list of videos
    help    -- show help message"
USAGE_FETCH="usage: ytr fetch [-l]"

USAGE_WATCH="usage: ytr watch <video_numbers>

examples:
    play most recent video: ytr watch 1
    play three videos in specific order: ytr watch 12 7 8"

USAGE_LIST="usage: ytr list [-<columns>]

columns:
    n -- video number, zero padded
    N -- video number, bracketed; space padded
    a -- video author
    t -- video title
    T -- video title, truncated
    d -- video publish date
    D -- video publish date, formatted & local
    i -- youtube video id

examples:
    default listing: ytr list or ytr list -$COLS_DEF
    list only full titles: ytr list -t"

command=$1
shift

if [ -z "$command" ]; then
    die "no action specified" "\n\n$USAGE"
fi

if [ -r $COL_ID -a -r $COL_AUTHOR -a -r $COL_TITLE -a -r $COL_DATE ]; then
    cache_available=true
    cache_count=$(wc -l < $COL_ID)
else
    cache_available=false
fi
 
case $command in
    fetch) fetch_cmd "$@";;
    list) list_cmd "$@";;
    watch) watch_cmd "$@";;
    clean) clean_cmd "$@";;
    help) help_cmd "$@";;
    *) die "invalid command -- $command";;
esac

exit 0
