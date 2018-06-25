#!/bin/sh
set -u

# length and regex to channel ids
CHID_LEN=24
CHID_REGEX="^[a-zA-Z0-9\_-]{$CHID_LEN}$"

# start of urls to rss feeds with recent videos
FEED_URL="https://www.youtube.com/feeds/videos.xml?channel_id="

CFG_DIR="$HOME/.config/ytrecent"
# channel id file format:
# <channel1_id> <channel1_name>
# <channel2_id> <channel2_name>
#      :               :
CHID_FILE="$CFG_DIR/channel_ids"
CFG_FILE="$CFG_DIR/config.sh"

# set default settings
# separator used between fields, choose one that is rarely used in titles
SEP="~"
# format of date output, will be used for sorting
DATE_FMT="%F"
# column order for output table
COL_ORDER="author,title,date,id"

# load user settings
if [ -r $CFG_FILE ]; then
    source $CFG_FILE
fi

column_args="$column_args --table --separator "$SEP" \
             --table-columns id,author,title,date --table-order $COL_ORDER"

# temporary files
tmp_dir="/tmp/ytr"
feeds_dir="$tmp_dir/feeds"
entries_file="$tmp_dir/entries"

# make sure dirs exist
mkdir -p $tmp_dir || exit
mkdir -p $feeds_dir || exit
# empty entries file
rm -f $entries_file || exit

# rm comments from CHID_FILE
sed 's:#.*$::g;/^\-*$/d' $CHID_FILE > $tmp_dir/chid_strip
# rm invalid chids
while read chid author; do
    if echo $chid | grep -q -E $CHID_REGEX;
    then echo "$chid $author"
    else echo "warning: invalid channel id -- $chid" 1>&2
    fi
done < $tmp_dir/chid_strip > $tmp_dir/chid

# fetch rss feeds
curl -s $(while read chid author; do
    printf '%s%s -o %s/%s ' "$FEED_URL" "$chid" "$feeds_dir" "$chid"
done < $tmp_dir/chid)

# parse channels
while read chid author; do
    feed_file=$feeds_dir/$chid

    # parse videos from channel
    ifs_prev=$IFS
    IFS=\>
    while read -d \< tag content; do
        if [ "$tag" = "yt:videoId" ]; then
            printf "%s%s" "$content" "$SEP"
        elif [ "$tag" = "title" ]; then
            output="$author$SEP$content$SEP"
            if [ -x "$(command -v recode)" ]; then
                output=$(echo $output | recode -q html..ascii)
            fi
            printf "%s" "$output"
        elif [ "$tag" = "published" ]; then
            printf "%s\n" "$(date -d "$content" +"$DATE_FMT")"
        fi
    done < $feed_file | tail -n +2 >> $entries_file
    IFS=$ifs_prev
done < $tmp_dir/chid

# sort by date and align columns
cat $entries_file | sort -k 4 -t"$SEP" | column $column_args
