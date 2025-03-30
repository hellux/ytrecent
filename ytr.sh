#!/bin/sh

warn() {
    str=$1
    shift
    printf 'warning: '"$str"'\n' "$@" 1>&2
}
die() {
    str=$1
    shift
    printf 'error: '"$str"'\n' "$@" 1>&2
    rm -rf "$RNT_DIR"
    exit 1
}
contains() {
    test "${2#*$1}" != "$2"
}
rm_comments() {
    sed 's:#.*$::g;/^\-*$/d;s/ *$//' "$1"
}
urlencode() {
    string="$*"
    while [ -n "$string" ]; do
        char="$(echo "$string" | cut -c1)"
        case "$char" in
        [A-Za-z0-9-*.~]) printf %c "$char";;    # unreserved
        *) printf "%%%02x" "'$char"             # reserved
        esac
        string="$(echo "$string" | cut -c2-)"
    done
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
then RNT_DIR="/tmp/ytrecent"
else RNT_DIR="$XDG_RUNTIME_DIR/ytrecent"
fi
if [ -z "$XDG_CONFIG_HOME" ];
then CFG_DIR="$HOME/.config/ytrecent"
else CFG_DIR="$XDG_CONFIG_HOME/ytrecent"
fi

# ytr config fallbacks/defaults
[ -z "$YTR_PLAYER" ] && YTR_PLAYER="mpv"
[ -z "$YTR_TITLE_LEN" ] && YTR_TITLE_LEN=80
[ -z "$YTR_SINCE_DAYS" ] && YTR_SINCE_DAYS=30
[ -z "$YTR_COLS" ] && YTR_COLS="NaTD"
[ -z "$YTR_DATE_FMT" ] && YTR_DATE_FMT="%a %e %b %H:%M"

# URL prefixes
DOMAIN="https://www.youtube.com"
VIDEO_URL="$DOMAIN/watch?v="
FEED_URL_UC="$DOMAIN/feeds/videos.xml?channel_id="
FEED_URL_PL="$DOMAIN/feeds/videos.xml?playlist_id="
CHNL_URL="$DOMAIN/channel/"
USER_URL="$DOMAIN/user/"
SEARCH_URL="$DOMAIN/results?search_query="
# id regex
CHID_REGEX='UC[a-zA-Z0-9\_-]{22}'
LIST_REGEX='(PL[a-zA-Z0-9\_-]{32}|RD[a-zA-Z0-9\_-]{11})'
VIDID_REGEX='[a-zA-Z0-9\_-]{11}'
# user channels
CHID_FILE="$CFG_DIR/channel_ids"
# cache files
ENTRIES="$CCH_DIR/entries"
ENTRIES_SEARCH="$CCH_DIR/search"
LAST_COMMAND="$CCH_DIR/last"
# tmp postprocess columns
COL_ID="$RNT_DIR/col_id"
COL_URL="$RNT_DIR/col_url"
COL_AUTHOR="$RNT_DIR/col_author"
COL_TITLE="$RNT_DIR/col_title"
COL_TITLE_TR="$RNT_DIR/col_title_tr"
COL_DATE="$RNT_DIR/col_date_utc"
COL_DATE_FMT="$RNT_DIR/col_date_fmt"
COL_NUM="$RNT_DIR/col_num"
COL_NUM_ZERO="$RNT_DIR/col_num_zero"
COL_NUM_PAD="$RNT_DIR/col_num_pad"
COL_LENGTH="$RNT_DIR/col_length"
COL_VIEWS="$RNT_DIR/col_views"
COL_PUBLISHED="$RNT_DIR/col_published"

JQ_PARSE_SEARCH='
def get_videos: .contents.twoColumnSearchResultsRenderer
                .primaryContents.sectionListRenderer.contents[]
                .itemSectionRenderer | select(. != null) | .contents[]
                .videoRenderer | select(. != null);

def get_id: .videoId;
def get_author: .ownerText.runs[].text;
def get_title: .title.runs[].text;
def get_length: .lengthText.simpleText;
def get_views: .viewCountText.simpleText;
def get_published: .publishedTimeText.simpleText;

get_videos | [ get_id
             , get_author
             , get_title
             , get_length
             , get_views
             , get_published
             ] | @tsv'

USAGE="usage: ytr <command> [<args>]

commands:
    channel ch c  -- handle channels to follow
    sync       s  -- fetch list of recent videos from channels
    list    ls l  -- display cached list of videos
    search     S  -- search for videos
    play       p  -- play videos via external player
    help       h  -- show information about ytr and its commands"

DESC="description:
    ytr is a utility for keeping up with YouTube channels from the command
    line. It serves a similar purpose to YouTube subscriptions, but no YouTube
    account is required. A channel can be followed with 'ytr channel add
    <channel>'. This adds an entry to the CHID_FILE. 'ytr sync' then fetches
    RSS feeds from youtube.com which contain links to recent videos from each
    channel. Videos are then sorted by date of publish and displayed with 'ytr
    list'. 'ytr play' can be used to watch these videos immediately through an
    external video player or web browser."

DESC_ENV="environment variables:
    YTR_PLAYER [$YTR_PLAYER]
        command used to play videos, the play command will invoke the player
        with the video URL as the only argument
    YTR_TITLE_LEN [$YTR_TITLE_LEN]
        length titles will be truncated to this length in the T column for the
        list command
    YTR_SINCE_DAYS [$YTR_SINCE_DAYS]
        the list command will filter out videos older than this, unless
        overridden by the -d or -a flag
    YTR_COLS [$YTR_COLS]
        default column string for the list command, determining which columns
        are displayed
    YTR_DATE_FMT [$YTR_DATE_FMT]
        format passed to 'date' for the D column for the list command"

DESC_FILES="files:
    CHID_FILE [$CHID_FILE]
        Channel IDs for followed channels are stored in this file with the
        following format:
            <channel1 id> <channel1 name>
            <channel2 id> <channel2 name> # comment
                 :               :
    ENTRIES [$ENTRIES]
        ENTRIES stores the cache of video metadata obtained by the sync
        command. Each line lists the video ID, author, title and date of a
        single video in that order. The fields are separated by a tab
        character."

USAGE_SYNC="usage: ytr sync [-qvc]

Fetch RSS feeds containing recent videos from each channel specified in the
local channel list -- $CHID_FILE.
Parse and add these videos to the local cache.

options:
    -q  --  quiet, do not print anything
    -v  --  verbose, print status
    -c  --  clear cache before syncing"

USAGE_CHANNEL_ADD="usage: ytr channel add <url|username|id> [<name>]

Add channel to CHID_FILE. Channel ID and name of channel will be parsed if not
provided.

examples:
    add channel by URL:
        ytr add https://www.youtube.com/channel/UC-9-kyTW8ZkZNDHQJ6FgpwQ
    add channel by username:
        ytr add youTuber123
    add channel by id and choose name:
        ytr add UClgRkhTL3_hImCAmdLfDE4g movies"
USAGE_CHANNEL_REMOVE="usage: ytr channel remove <name>

Remove channel from CHID_FILE."
USAGE_CHANNEL="usage: ytr channel <command> [<args>]

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
    default listing: ytr list or ytr list $YTR_COLS
    list only full titles: ytr list t
    list videos published the last week in cache: ytr list -d 7
    sync cache and list videos from this week: ytr list -sd7"

USAGE_SEARCH="usage: ytr search [-p] <query>

Search for videos on YouTube.

options:
    -p -- play the first search result immediately
    -u -- print the url of the first search result immediately"

USAGE_PLAY="usage: ytr play [-u] <video_number|url|id...>

Launch a sequence of videos with given command. Each video will be run with
<command> <url>.

options:
    -u -- print video URLs instead of playing

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
            c) rm -rf "$CCH_DIR";;
            *) die "invalid flag\n\n%s" "$USAGE_SYNC"
        esac
    done
    shift $((OPTIND-1))

    [ -n "$1" ] && die 'excess arguments -- %s\n\n%s' "$*" "$USAGE_SYNC"
    [ ! -r "$CHID_FILE" ] && die "no file with channel IDs found at $CHID_FILE"
    [ "$quiet" = "true" ] && verbose=false

    mkdir -p "$CCH_DIR" || die "unable to create cache directory at $CCH_DIR"

    rm_comments "$CHID_FILE" > "$RNT_DIR/chids"
    # parse valid feed urls
    while read -r chid author; do
        if echo "$chid" | grep -q -E "^$CHID_REGEX$"; then
            url="$FEED_URL_UC$chid"
        elif echo "$chid" | grep -q -E "^$LIST_REGEX$"; then
            url="$FEED_URL_PL$chid"
        else warn 'invalid channel entry -- %s %s' "$chid" "$author"
        fi
        printf '%s -o %s ' "$url" "$RNT_DIR/$chid"
    done < "$RNT_DIR/chids" > "$RNT_DIR/urls"

    [ ! -s "$RNT_DIR/urls" ] && die "no channels or playlists in CHID file"

    # fetch rss feeds
    curl_args="-Z"
    [ "$verbose" = "false" ] && curl_args="$curl_args -s"
    curl $curl_args $(cat $RNT_DIR/urls)
    ec=$?
    [ "$ec" -ne 0 ] && die "fetch failed -- curl exit code $ec"

    if [ -r "$ENTRIES" ]
    then prev_count=$(wc -l < "$ENTRIES")
    else prev_count=0
    fi

    AWK_PARSE='BEGIN { RS="<"; FS=">" }
    $1 == "yt:videoId" { printf "%s\t", $2 }
    $1 == "title" { printf "%s\t%s\t", a, $2 }
    $1 == "published" { printf "%s\n", $2 }'

    # parse videos from channel feeds
    while read -r chid author; do
        [ "$verbose" = "true" ] && echo "Parsing videos from $author..."
        feed_file="$RNT_DIR/$chid"

        # remove header
        sed '1,/entry/d' "$feed_file" > "${feed_file}_entr"

        # parse video entries
        awk -v"a=$author" "$AWK_PARSE" "${feed_file}_entr" >> "$ENTRIES"
    done < "$RNT_DIR"/chids

    # sort, rm duplicates
    sort -t"$(printf '\t')" -r -k4 "$ENTRIES" |\
        sort -t"$(printf '\t')" -u -k 1,1 |\
        sort -t"$(printf '\t')" -r -k4 > "${ENTRIES}_sorted"
    mv "${ENTRIES}_sorted" "$ENTRIES"

    # replace html entities
    sed -i 's/&nbsp;/ /g;
            s/&amp;/\&/g;
            s/&lt;/\</g;
            s/&gt;/\>/g;
            s/&quot;/\"/g;
            s/&ldquo;/\"/g;
            s/&rdquo;/\"/g;' "$ENTRIES"

    if [ "$quiet" = "false" ]; then
        curr_count=$(wc -l < "$ENTRIES")
        diff_count=$((curr_count - prev_count))
        echo "$diff_count new video(s) found."
    fi

    echo "sync" > "$LAST_COMMAND"
}

channel_add_cmd() {
    channel=$1
    [ -z "$1" ] && die "no channel specified"
    shift
    name="$*"
    if echo "$channel" | grep -q -E "^$CHID_REGEX$"; then
        url="$CHNL_URL$channel"
        chid="$channel"
    elif echo "$channel" | grep -q "$CHNL_URL"; then
        url="$channel"
        chid=$(echo "$channel" | cut -d/ -f5)
    elif echo "$channel" | grep -q "$USER_URL"; then
        url="$channel"
    else
        url="$USER_URL$channel"
    fi

    if [ -z "$chid" ] || [ -z "$name" ]; then
        curl -s "$url" > "$RNT_DIR/channel"
        ec=$?
        [ $ec -ne 0 ] && die "channel fetch failed -- curl exit code $ec"
        if [ -z "$chid" ]; then
            chid=$(grep 'type="application/rss+xml"' "$RNT_DIR/channel" \
                | awk 'BEGIN { FS="="; RS="?" } $1 == "channel_id" { print $2 }' \
                | tr -d '">')
        fi
    fi;

    echo "$chid" | grep -q -E "^$CHID_REGEX$" || die "channel id parse failed"
    if [ -r "$CHID_FILE" ] && grep -q "^$chid" "$CHID_FILE"; then
        die "channel already in list -- $chid"
    fi

    [ -z "$name" ] && name=$(sed -n 's/<title>//p' "$RNT_DIR/channel" | xargs)

    if [ ! -r "$CHID_FILE" ]; then
        mkdir -p "$CFG_DIR" || die "unable to create config dir at $CFG_DIR"
        touch "$CHID_FILE" || die "unable to create CHID_FILE at $CHID_FILE"
    fi
    echo "$chid $name" >> "$CHID_FILE"
    printf '"%s" added, id=%s\n' "$name" "$chid"
}

channel_remove_cmd() {
    name="$*"
    [ -r "$CHID_FILE" ] || die "no CHID_FILE to modify exists"

    count_pre=$(wc -l < "$CHID_FILE")
    # inverse grep to keep all channels but the one removed
    rm_comments "$CHID_FILE" | grep -v -E "^$CHID_REGEX $name$" > "$RNT_DIR/new"
    mv "$RNT_DIR/new" "$CHID_FILE"
    count_post=$(wc -l < "$CHID_FILE")

    if [ "$count_post" -lt "$count_pre" ];
    then printf 'channel "%s" removed\n' "$name"
    else die 'channel "%s" not found' "$name"
    fi
}

channel_list_cmd() {
    [ -r "$CHID_FILE" ] && rm_comments "$CHID_FILE" | cut -f2- -d' ' | sort
}

channel_cmd() {
    command=$1
    [ -z "$command" ] && channel_list_cmd "$@" && return
    shift

    case $command in
        a|add) channel_add_cmd "$@";;
        rm|remove) channel_remove_cmd "$@";;
        ls|list) channel_list_cmd "$@";;
        *) die 'invalid command -- %s\n\n%s' "$command" "$USAGE_CHANNEL";;
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
            *) die "invalid flag\n\n%s" "$USAGE_LIST"
        esac
    done
    shift $((OPTIND-1))
    colstr=${1:-$YTR_COLS}
    [ -n "$2" ] && shift && die 'excess args -- %s\n\n%s' "$*" "$USAGE_LIST"
    [ "$days" -gt 0 ] 2>/dev/null || die "invalid day count -- $days"
    [ "$sync" = "true" ] && sync_cmd -q
    [ ! -r "$ENTRIES" ] && die "no cache found, use sync command"

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
            *) die "invalid column\n\n%s" "$USAGE_LIST"
        esac
    done

    # split cache into separate files
    cut -f 1 "$ENTRIES" > "$COL_ID"
    cut -f 2 "$ENTRIES" > "$COL_AUTHOR"
    cut -f 3 "$ENTRIES" > "$COL_TITLE"
    cut -f 4 "$ENTRIES" > "$COL_DATE"

    # filter old entries, determine video count
    if [ ! "$all" = "true" ]; then
        now=$(date +%s)
        since=$((now - (86400*days)))
        video_count="0"
        while read -r date_utc; do
            date=$(date_utc_fmt "$date_utc" "%s")
            if [ "$date" -lt "$since" ]
            then break
            else video_count=$(( video_count + 1))
            fi
        done < "$COL_DATE"
    else
        video_count=$(wc -l < "$ENTRIES")
    fi

    if contains "$COL_URL" "$cols"; then
        while read -r id; do
            echo "$VIDEO_URL$id"
        done < "$COL_ID" > "$COL_URL"
    fi
    if contains "$COL_TITLE_TR" "$cols"; then
        cut -c1-"$YTR_TITLE_LEN" "$COL_TITLE" > "$COL_TITLE_TR"
    fi
    if contains "$COL_NUM" "$cols"; then
        pad=$((${#video_count}))
        for num in $(seq "$video_count"); do
            printf '%d\n' "$num"
        done > "$COL_NUM"
        if contains "$COL_NUM_ZERO" "$cols"; then
            while read -r num; do
                printf '%0'${pad}'d\n' "$num"
            done < "$COL_NUM" > "$COL_NUM_ZERO"
        fi
        if contains "$COL_NUM_PAD" "$cols"; then
            while read -r num; do
                printf '[%'${pad}'s]\n' "$num"
            done < "$COL_NUM" > "$COL_NUM_PAD"
        fi
    fi
    if contains "$COL_DATE_FMT" "$cols"; then
        head -n "$video_count" "$COL_DATE" | while read -r date; do
            date_utc_fmt "$date" "$YTR_DATE_FMT"
        done > "$COL_DATE_FMT"
    fi

    # merge column files, grab only recent entries, reverse order of entries
    paste $cols | head -n "$video_count" | sed '1!G;h;$!d' > "$RNT_DIR/columns"

    if [ "$video_count" -gt 0 ]; then
        if [ "$table" = "true" ]
        then column -t -s"$(printf '\t')" "$RNT_DIR/columns"
        else cat "$RNT_DIR/columns"
        fi
    fi;
}

search_cmd() {
    play=""
    OPTIND=1
    while getopts pu flag; do
        case "$flag" in
            p|u) play="$flag";;
            *) die "invalid flag\n\n%s" "$USAGE_SEARCH"
        esac
    done
    shift $((OPTIND-1))

    [ -z "$*" ] && die 'no search query specified\n\n%s' "$USAGE_SEARCH"
    query="$(urlencode "$*")"

    curl_args="-m1 -s"
    curl $curl_args "$SEARCH_URL$query&gl=US" -o "$RNT_DIR/response_search"
    ec=$?
    [ "$ec" -ne 0 ] && die "fetch failed -- curl exit code $ec"

    echo "search" > "$LAST_COMMAND"

    prestr='ytInitialData = '
    grep "$prestr" "$RNT_DIR/response_search" \
        | sed 's/.*'"$prestr"'//;s,;</script>.*,,' \
        | jq -r "$JQ_PARSE_SEARCH" > "$ENTRIES_SEARCH"

    video_count="$(wc -l < "$ENTRIES_SEARCH")"

    if [ "$video_count" -gt 0 ]; then
        if [ -n "$play" ]; then
            play_cmd -"$play" 1
            return
        fi
    else
        echo "No results for '$*'"
    fi

    cut -f 1 "$ENTRIES_SEARCH" > "$COL_ID"
    cut -f 2 "$ENTRIES_SEARCH" > "$COL_AUTHOR"
    cut -f 3 "$ENTRIES_SEARCH" > "$COL_TITLE"
    cut -f 4 "$ENTRIES_SEARCH" > "$COL_LENGTH"
    cut -f 5 "$ENTRIES_SEARCH" > "$COL_VIEWS"
    cut -f 6 "$ENTRIES_SEARCH" > "$COL_PUBLISHED"

    pad=$((${#video_count} - 1))
    for num in $(seq "$video_count"); do
        printf '[%'${pad}'s]\n' "$num"
    done > "$COL_NUM_PAD"

    cols="$COL_NUM_PAD $COL_AUTHOR $COL_TITLE \
          $COL_LENGTH $COL_VIEWS $COL_PUBLISHED"
    paste $cols | sed '1!G;h;$!d' > "$RNT_DIR/columns"

    column -t -s"$(printf '\t')" "$RNT_DIR/columns"
}

play_cmd() {
    OPTIND=1
    while getopts pu flag; do
        case "$flag" in
            p) ;;
            u) YTR_PLAYER="echo";;
            *) die "invalid flag\n\n%s" "$USAGE_PLAY"
        esac
    done
    shift $((OPTIND-1))

    [ -z "$1" ] && die 'no video specifed\n\n%s' "$USAGE_PLAY"

    case "$(cat "$LAST_COMMAND")" in
        sync)   entries="$ENTRIES";;
        search) entries="$ENTRIES_SEARCH";;
        *) die "no cache found, use sync command";;
    esac

    cut -f 1 "$entries" > "$COL_ID"
    vid_count=$(wc -l < "$entries")

    for vid in "$@"; do
        if [ "1" -le "$vid" ] 2>/dev/null && [ "$vid" -le "$vid_count" ] 2>/dev/null; then
            video_id=$(sed "${vid}q;d" "$COL_ID") # pick out line $vid
            url="$VIDEO_URL$video_id"
        elif echo "$vid" | grep -q -E "^$VIDID_REGEX$"; then
            url="$VIDEO_URL$vid"
        else
            url="$vid"
        fi
        $YTR_PLAYER "$url"
    done
}

help_cmd() {
    topic=$1
    if [ -n "$topic" ]; then
        shift
        case "$topic" in
            channel) printf '%s\n\n%s\n\n%s\n' "$USAGE_CHANNEL" \
                "$USAGE_CHANNEL_ADD" "$USAGE_CHANNEL_REMOVE";;
            sync) echo "$USAGE_SYNC";;
            list) echo "$USAGE_LIST";;
            search) echo "$USAGE_SEARCH";;
            play) echo "$USAGE_PLAY";;
            help) echo "$USAGE_HELP";;
            *) warn 'invalid topic -- %s' "$topic"; help_cmd "help";;
        esac
    else
        echo "ytrecent -- YouTube channel tracker"
        printf '\n%s\n\n%s\n\n%s\n\n%s\n' \
            "$USAGE" "$DESC" "$DESC_FILES" "$DESC_ENV"
    fi
    [ -n "$1" ] && warn 'excess arguments -- %s' "$*"
}

mkdir -p "$RNT_DIR" || die "unable to create runtime directory at $RNT_DIR"

command=$1
[ -z "$command" ] && list_cmd && exit 0
shift

case $command in
    s|sync) sync_cmd "$@";;
    c|ch|channel) channel_cmd "$@";;
    l|ls|list) list_cmd "$@";;
    p|play) play_cmd "$@";;
    S|search) search_cmd "$@";;
    h|help) help_cmd "$@";;
    *) die 'invalid command -- %s\n\n%s' "$command" "$USAGE";;
esac

rm -rf "$RNT_DIR"

exit 0
