#!/usr/bin/env bash

# TODO POSIX compliance
#   -replace 'read -d' for parsing

warn() {
    echo -e "warning: $@" 1>&2
}
die() {
    echo -e "error: $@" 1>&2
    exit 1
}
contains() {
    test "${2#*$1}" != "$2"
}
rm_comments() {
    sed 's:#.*$::g;/^\-*$/d;s/ *$//' $1
}

if date -v 1d > /dev/null 2>&1;
then BSD_DATE=true
else BSD_DATE=false
fi
date_utc_fmt() {
    date_utc=$1
    format=$2
    if [ "$BSD_DATE" = "true" ]
    then date -jf "%FT%T+00:00 %Z" "$date_utc UTC" "+$format"
    else date -d "$date_utc" +"$format"
    fi
}

if [ -z "$XDG_CACHE_HOME" ];
then CCH_DIR="$HOME/.cache/ytrecent"
else CCH_DIR="$XDG_CACHE_HOME/ytrecent"
fi
if [ -z "$XDG_RUNTIME_DIR" ];
then RNT_DIR="$CCH_DIR/runtime"
else RNT_DIR="$XDG_RUNTIME_DIR/ytrecent"
fi
if [ -z "$XDG_CONFIG_HOME" ];
then CFG_DIR="$HOME/.config/ytrecent"
else CFG_DIR="$XDG_CONFIG_HOME/ytrecent"
fi

# ytr config fallbacks/defaults
[ -z "$YTR_PLAYER" ] && YTR_PLAYER=mpv
[ -z "$YTR_TITLE_LEN" ] && YTR_TITLE_LEN=80
[ -z "$YTR_SINCE_DAYS" ] && YTR_SINCE_DAYS=30
[ -z "$YTR_COLS" ] && YTR_COLS="NaTD"
[ -z "$YTR_DATE_FMT" ] && YTR_DATE_FMT="%a %e %b %H:%M"

# URL prefixes
VIDEO_URL="https://www.youtube.com/watch?v="
FEED_URL="https://www.youtube.com/feeds/videos.xml?channel_id="
CHNL_URL="https://www.youtube.com/channel/"
USER_URL="https://www.youtube.com/user/"
# channel id regex
CHID_REGEX="[a-zA-Z0-9\_-]{24}"
# user channels
CHID_FILE=$CFG_DIR/channel_ids
# cached videos
ENTRIES=$CCH_DIR/entries
# cached columns
COL_ID=$CCH_DIR/col_id
COL_AUTHOR=$CCH_DIR/col_author
COL_TITLE=$CCH_DIR/col_title_full
COL_DATE=$CCH_DIR/col_date_utc
# tmp postprocess columns
COL_URL=$RNT_DIR/col_url
COL_NUM=$RNT_DIR/col_num
COL_NUM_ZERO=$RNT_DIR/col_num_zero
COL_NUM_PAD=$RNT_DIR/col_num_pad
COL_TITLE_TR=$RNT_DIR/col_title_tr
COL_DATE_FMT=$RNT_DIR/col_date_fmt

USAGE="usage: ytr <command> [<args>]

commands:
    channel ch c  -- handle channels to follow
    sync       s  -- fetch list of recent videos from channels
    list    ls l  -- display cached list of videos
    play       p  -- play videos via external player
    help       h  -- show information about ytr and its commands"

DESC="description:
    ytr is a utility for keeping up with YouTube channels from the command
    line. It serves a similar purpose to YouTube subscriptions, but no YouTube
    account is required. A channel can be followed with 'ytr channel add
    <channel>'. 'ytr cache sync' then fetches RSS feeds from youtube.com which
    contain links to recent videos from each channel. Videos are then sorted by
    date of publish and displayed with 'ytr list'. 'ytr play' can be used to
    play these videos immediately through an external video player or web
    browser."

DESC_ENV="environment variables:
    YTR_PLAYER [$YTR_PLAYER]
        command used to play videos $YTR_PLAYER, ytr will call the player
        with the video url as argument
    YTR_TITLE_LEN [$YTR_TITLE_LEN]
        length titles will be truncated in T column for the list command
    YTR_SINCE_DAYS [$YTR_SINCE_DAYS]
        fallback value for list -d option
    YTR_COLS [$YTR_COLS]
        fallback column string for the command
    YTR_DATE_FMT [$YTR_DATE_FMT]
        format passed to 'date' for D column for the list command"

USAGE_SYNC="usage: ytr sync [-qvc]

Fetch RSS feeds containing recent videos from each channel specified in the
local channel list -- $CHID_FILE.
Parse and add these videos to the local cache.

options:
    -q  --  quiet, do not print anything
    -v  --  verbose, print status
    -c  --  clear cache before syncing"

USAGE_CHANNEL_ADD="usage: ytr channel add <url|username|id> [<name>]

Add channel to channel list at $CHID_FILE.
Channel ID and name of channel will be parsed if not provided.

examples:
    add channel by URL:
        ytr add https://www.youtube.com/channel/UC-9-kyTW8ZkZNDHQJ6FgpwQ
    add channel by username:
        ytr add YouTuber123
    add channel by id and choose name:
        ytr add UClgRkhTL3_hImCAmdLfDE4g movies"
USAGE_CHANNEL_REMOVE="usage: ytr channel remove <name>

Remove channel from channel list at $CHID_FILE."
USAGE_CHANNEL="usage: ytr channel <command>

commands:
    add     a   -- add channel to follow
    remove  rm  -- remove channel
    list    ls  -- show followed channels"

USAGE_LIST="usage: ytr list [-sat] [-d <days>] [<columns>]

List videos from local cache.

options:
    -s          --  sync cache before listing
    -d<days>    --  show only videos newer than <days> days old
    -a          --  show all videos, overrides -d
    -t          --  print entries with tabs as separators instead of a table

columns:
    n -- video number, zero padded
    N -- video number, space padded in brackets
    a -- video author
    t -- video title
    T -- video title, truncated
    d -- video publish date
    D -- video publish date, formatted & local
    u -- youtube video id
    U -- youtube video URL

examples:
    default listing: ytr list or ytr list -c $YTR_COLS
    list only full titles: ytr list -c t
    list videos published the last week in cache: ytr list -d7
    sync cache and list videos from this week: ytr list -sd7"

USAGE_PLAY="usage: ytr play [-p] <video_numbers>

Launch a sequence of videos with given command. Each video will be run with
<command> <url>.

options:
    -p -- print video URLs instead of playing

examples:
    play most recent video: ytr play 1
    play three videos in specific order: ytr play 12 7 8"

USAGE_HELP="usage: ytr help [<command>]"

sync_cmd() {
    quiet=false
    verbose=false
    OPTIND=1
    while getopts :qvc flag; do
        case "$flag" in
            q) quiet=true;;
            v) verbose=true;;
            c) rm -rf $CCH_DIR; cache_available=false;;
            [?]) die "invalid flag -- $OPTARG"
        esac
    done
    shift $((OPTIND-1))

    [ -n "$1" ] && die "excess arguments -- $@" "\n\n$USAGE_CACHE_SYNC"
    [ ! -r $CHID_FILE ] && die "no file with channel IDs found at $CHID_FILE"
    [ "$quiet" = "true" ] && verbose=false

    mkdir -p $CCH_DIR || exit 1
    mkdir -p $RNT_DIR || exit 1

    rm_comments $CHID_FILE > $RNT_DIR/chids_stripped
    # rm invalid chids
    while read chid author; do
        if echo $chid | grep -q -E "^$CHID_REGEX$";
        then echo "$chid $author"
        else warn "invalid channel id -- $chid"
        fi
    done < $RNT_DIR/chids_stripped > $RNT_DIR/chids

    # fetch rss feeds
    curl_args="-m1"
    [ "$verbose" = "false" ] && curl_args="$curl_args -s"
    curl $curl_args $(while read chid author; do
        printf '%s%s -o %s/%s ' "$FEED_URL" "$chid" "$RNT_DIR" "$chid"
    done < $RNT_DIR/chids )
    ec=$?
    [ $ec -ne 0 ] && die "fetch failed -- curl exit code $ec"

    if [ "$cache_available" = "true" ]
    then prev_count=$(wc -l < $ENTRIES)
    else prev_count=0
    fi
    # parse videos from channel feeds
    while read chid author; do
        [ "$verbose" = "true" ] && echo "Parsing videos from $author..."
        feed_file=$RNT_DIR/$chid

        # remove header
        sed '1,/entry/d' $feed_file > ${feed_file}_entr

        while IFS=\> read -d \< tag content; do
            if [ "$tag" = "yt:videoId" ]; then
                printf "%s\t" "$content"
            elif [ "$tag" = "title" ]; then
                printf "%s\t%s\t" "$author" "$content"
            elif [ "$tag" = "published" ]; then
                printf "%s\n" "$content"
            fi
        done < ${feed_file}_entr >> $ENTRIES
    done < $RNT_DIR/chids

    # rm duplicates, sort, place columns in separate files, postprocess
    sort -t $'\t' -r -k 4 $ENTRIES | uniq > ${ENTRIES}_sorted
    mv ${ENTRIES}_sorted $ENTRIES
    cut -f 1 $ENTRIES > $COL_ID
    cut -f 2 $ENTRIES > $COL_AUTHOR
    cut -f 3 $ENTRIES > $COL_TITLE
    cut -f 4 $ENTRIES > $COL_DATE
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

    if [ "$quiet" = "false" ]; then
        curr_count=$(wc -l < $ENTRIES)
        diff_count=$(expr $curr_count - $prev_count)
        echo "$diff_count new video(s) found."
    fi
}

channel_add_cmd() {
    channel=$1
    shift
    name=$@
    if echo $channel | grep -q -E "^$CHID_REGEX$"; then
        url=$CHNL_URL$channel
        chid=$channel
    elif echo $channel | grep -q "$CHNL_URL"; then
        url=$channel
        chid=$(echo $channel | cut -d/ -f5)
    elif echo $channel | grep -q "$USER_URL"; then
        url=$channel
    else
        url=$USER_URL$channel
    fi

    if [ -z "$chid" -o -z "$name" ]; then
        mkdir -p $RNT_DIR
        curl -s $url > $RNT_DIR/channel 
        ec=$?
        [ $ec -ne 0 ] && die "channel fetch failed -- curl exit code $ec"
        if [ -z $chid ]; then
            chid=$(awk 'BEGIN { FS="channel_id="; RS="\"" } { print $2 }' \
                   $RNT_DIR/channel | tr -d '\n')
        fi 
    fi;

    echo $chid | grep -q -E "^$CHID_REGEX$" || die "channel id parse failed"
    grep -q "^$chid" $CHID_FILE && die "channel already in list -- $chid"

    [ -z "$name" ] && name=$(sed -n 's/<title>//p' $RNT_DIR/channel | xargs)

    echo $chid $name >> $CHID_FILE
    echo "Added \"$name\", id: \"$chid\""


    rm -rf $RNT_DIR
}

channel_remove_cmd() {
    name=$@
    mkdir -p $RNT_DIR
    rm_comments $CHID_FILE | grep -v -E "^$CHID_REGEX $name$" > $RNT_DIR/new
    mv $RNT_DIR/new $CHID_FILE
    rm -rf $RNT_DIR
}

channel_list_cmd() {
    rm_comments $CHID_FILE | cut -f2- -d' '
}

channel_cmd() {
    command=$1
    shift
    [ -z "$command" ] && channel_list_cmd "$@" && exit 0

    case $command in
        a|add) channel_add_cmd "$@";;
        rm|remove) channel_remove_cmd "$@";;
        ls|list) channel_list_cmd "$@";;
        *) die "invalid command -- $command" "\n\n$USAGE_CACHE";;
    esac
}

list_cmd() {
    sync=false
    days=$YTR_SINCE_DAYS
    all=false
    table=true
    OPTIND=1
    while getopts :sd:at flag; do
        case "$flag" in
            s) sync=true;;
            d) days="$OPTARG";;
            a) all=true;;
            t) table=false;;
            [?]) die "invalid flag -- $OPTARG"
        esac
    done
    shift $((OPTIND-1))
    colstr=$1
    shift
    [ -n "$1" ] && die "excess arguments -- $@" "\n\n$USAGE_LIST"
    [ -z "$colstr" ] && colstr=$YTR_COLS
    [ "$days" -gt 0 ] 2>/dev/null || die "invalid day count -- $days"
    [ "$sync" = "true" ] && sync_cmd -q
    [ "$cache_available" = "false" ] && die "no cache found in $CCH_DIR"

    cols=""
    OPTIND=1
    while getopts :nNatTdDuU col "-$colstr"; do
        case "$col" in
            n) cols="$cols $COL_NUM_ZERO";;
            N) cols="$cols $COL_NUM_PAD";;
            a) cols="$cols $COL_AUTHOR";;
            t) cols="$cols $COL_TITLE";;
            T) cols="$cols $COL_TITLE_TR";;
            d) cols="$cols $COL_DATE";;
            D) cols="$cols $COL_DATE_FMT";;
            u) cols="$cols $COL_ID";;
            U) cols="$cols $COL_URL";;
            [?]) die "invalid column -- $OPTARG"
        esac
    done

    if [ ! "$all" = "true" ]; then
        since=$(expr "$(date +%s)" - \( 86400 \* $days \))
        video_count="0"
        while read date_utc; do
            date=$(date_utc_fmt "$date_utc" "%s")
            if [ $date -lt $since ]
            then break
            else video_count=$(expr $video_count + 1)
            fi
        done < $COL_DATE
    else
        video_count=$cache_count
    fi

    mkdir -p $RNT_DIR
    if contains $COL_URL "$cols"; then
        while read id; do
            echo $VIDEO_URL$id
        done < $COL_ID > $COL_URL
    fi
    if contains $COL_TITLE_TR "$cols"; then
        cut -c1-$YTR_TITLE_LEN $COL_TITLE > $COL_TITLE_TR
    fi
    if contains $COL_NUM "$cols"; then
        pad=$(expr $(echo $video_count | wc -c) - 1) # max width of video number
        for num in $(seq $video_count); do
            printf "%d\n" "$num"
        done > $COL_NUM
        if contains $COL_NUM_ZERO "$cols"; then
            while read num; do
                printf "%0${pad}d\n" "$num"
            done < $COL_NUM > $COL_NUM_ZERO
        fi
        if contains $COL_NUM_PAD "$cols"; then
            while read num; do
                printf "[%${pad}s]\n" "$num"
            done < $COL_NUM > $COL_NUM_PAD
        fi
    fi
    if contains $COL_DATE_FMT "$cols"; then
        head -n $video_count $COL_DATE | while read date; do
            date_utc_fmt "$date" "$YTR_DATE_FMT"
        done > $COL_DATE_FMT
    fi

    # merge column files, grab only recent entries, reverse order of entries
    paste $cols | head -n $video_count | sed '1!G;h;$!d' > $RNT_DIR/columns
    if [ "$table" = "true" ]
    then column -t -s $'\t' $RNT_DIR/columns
    else cat $RNT_DIR/columns
    fi
    rm -rf $RNT_DIR
}

play_cmd() {
    OPTIND=1
    while getopts :p flag; do
        case "$flag" in
            p) YTR_PLAYER="echo";;
            [?]) die "invalid flag -- $OPTARG"
        esac
    done
    shift $((OPTIND-1))
    [ -z $1 ] && die "no video specifed" "\n\n$USAGE_PLAY"
    [ "$cache_available" = "false" ] && die "no video list found in $CCH_DIR"
    
    for num in $@; do
        if [ "1" -le "$num" -a "$num" -le "$cache_count" ] 2>/dev/null; then
            video_id=$(sed "${num}q;d" $COL_ID) # pick out line $num
            $YTR_PLAYER $VIDEO_URL$video_id
        else
            die "invalid video number -- $num" "\n\n$USAGE_PLAY"
        fi
    done
}

help_cmd() {
    topic=$1
    shift
    [ -n "$1" ] && warn "excess arguments -- $@" "\n\n$USAGE_HELP"
    if [ -n "$topic" ]; then
        case $topic in
            channel) echo -e "$USAGE_CHANNEL\n\n$USAGE_CHANNEL_ADD\
                              \n\n$USAGE_CHANNEL_REMOVE";;
            sync) echo "$USAGE_SYNC";;
            list) echo "$USAGE_LIST";;
            play) echo "$USAGE_PLAY";;
            help) echo "$USAGE_HELP";;
            *) warn "invalid topic -- $topic"; help_cmd "help";;
        esac
    else
        echo "ytrecent -- YouTube channel tracker"
        echo -e "\n$USAGE\n\n$DESC\n\n$DESC_ENV"
    fi
}

command=$1
shift
[ -z "$command" ] && list_cmd && exit 0

if [ -r $COL_ID -a -r $COL_AUTHOR -a -r $COL_TITLE -a -r $COL_DATE ]; then
    cache_available=true
    cache_count=$(wc -l < $COL_ID)
else
    cache_available=false
fi
 
case $command in
    s|sync) sync_cmd "$@";;
    c|ch|channel) channel_cmd "$@";;
    l|ls|list) list_cmd "$@";;
    p|play) play_cmd "$@";;
    h|help) help_cmd "$@";;
    *) die "invalid command -- $command" "\n\n$USAGE";;
esac

exit 0
