#!/usr/bin/env bash
set -u

# length and regex to channel ids
CHID_LEN=24
CHID_REGEX="^[a-zA-Z0-9\_-]{$CHID_LEN}$"

# start of urls to rss feeds with recent videos
FEED_URL="https://www.youtube.com/feeds/videos.xml?channel_id="

TMP_DIR="/tmp/ytr"
CFG_DIR="$HOME/.config/ytrecent"
# channel id file format:
# <channel1_id> <channel1_name>
# <channel2_id> <channel2_name>
#      :               :
CHID_FILE="$CFG_DIR/channel_ids"
CFG_FILE="$CFG_DIR/config.sh"

# temporary files
feeds_dir="$TMP_DIR/feeds"
entries_file="$TMP_DIR/entries"
chids_file="$TMP_DIR/chids"
col_chid=$TMP_DIR/col_chids
col_author=$TMP_DIR/col_author
col_title=$TMP_DIR/col_title
col_date=$TMP_DIR/col_date

# set default settings
# format of date output, will be used for sorting
DATE_FMT="%F %H:%M"
# translate html encodings to ascii, eg. &amp; -> & (requires recode)
RECODE=true
# order of columns in output table
COLS="$col_author $col_title $col_date $col_chid"
# truncate titles longer than below
TITLE_LEN=70

# load user settings
[ -r $CFG_FILE ] && source $CFG_FILE

if [ ! -r $CHID_FILE ]; then
    echo "error: no file with channel IDs found at $CHID_FILE"
    exit 1;
fi

if [ "$RECODE" = "true" -a ! -x "$(command -v recode)" ]; then
    echo "warning: 'recode' not installed, HTML encodings will remain" 1>&2
    RECODE=false
fi

if date -v 1d > /dev/null 2>&1;
then BSD_DATE=true
else BSD_DATE=false
fi

# make sure dirs exist
mkdir -p $TMP_DIR || exit 1
mkdir -p $feeds_dir || exit 1
# empty entries file
rm -f $entries_file || exit 1

# rm comments from CHID_FILE
sed 's:#.*$::g;/^\-*$/d' $CHID_FILE > ${chids_file}_stripped
# rm invalid chids
while read chid author; do
    if echo $chid | grep -q -E $CHID_REGEX;
    then echo "$chid $author"
    else echo "warning: invalid channel id -- $chid" 1>&2
    fi
done < ${chids_file}_stripped > $chids_file
rm ${chids_file}_stripped

# fetch rss feeds
curl -s $(while read chid author; do
    printf '%s%s -o %s/%s ' "$FEED_URL" "$chid" "$feeds_dir" "$chid"
done < $chids_file)

# parse channels
while read chid author; do
    feed_file=$feeds_dir/$chid

    # parse videos from channel
    ifs_prev=$IFS
    IFS=\>
    while read -d \< tag content; do
        if [ "$tag" = "yt:videoId" ]; then
            printf "%s\t" "$content"
        elif [ "$tag" = "title" ]; then
            title=$content
            printf "%s\t%s\t" "$author" "$title"
        elif [ "$tag" = "published" ]; then
            date_utc=$content
            if [ "$BSD_DATE" = "true" ]; then
                date=$(date -jf "%FT%T+00:00 %Z" "$date_utc UTC" "+$DATE_FMT")
            else 
                date=$(date -d "$date_utc" +"$DATE_FMT")
			fi
            printf "%s\t%s\n" "$date_utc" "$date"
        fi
    done < $feed_file | tail -n +2 >> $entries_file
    IFS=$ifs_prev
done < $chids_file
rm $chids_file
rm -r $feeds_dir

sort -t $'\t' -k 4 $entries_file -o $entries_file
cut -f 1 $entries_file > $col_chid
cut -f 2 $entries_file > $col_author
cut -f 3 $entries_file > $col_title
cut -f 5 $entries_file > $col_date

[ "$RECODE" = "true" ] && recode -f -q html..ascii $col_title
cut -c1-$TITLE_LEN $col_title > ${col_title}_tr
mv ${col_title}_tr $col_title

paste $COLS > $entries_file

column -t -s $'\t' $entries_file
rm -f $entries_file
