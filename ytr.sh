#!/bin/sh

# length and regex to channel ids
CHID_LEN=24
CHID_REGEX="^[a-zA-Z0-9\_-]{$CHID_LEN}$"

# channel id file format:
# <channel1_id> <channel1_name>
# <channel2_id> <channel2_name>
#      :               :
CHID_FILE="$HOME/.config/ytrecent/channel_ids"

# start of urls to rss feeds with recent videos
FEED_URL="https://www.youtube.com/feeds/videos.xml?channel_id="

# separator used between fields, choose one that is rarely used in titles
SEP="~"
# format of date output, will be used for sorting
DATE_FMT="%F %H:%M"
# maximum length of title output, longer titles will be truncated
TITLE_LEN=60

# temporary files
tmp_dir="/tmp/ytr"
feed_file="$tmp_dir/feed"
title_file="$tmp_dir/titles"
entries_file="$tmp_dir/entries"
parse_file="$tmp_dir/parse"

# make sure tmp dir exists
mkdir -p $tmp_dir
# empty entries file
rm -f $entries_file

# fetch and parse channels
while read chid author; do
    # validate chid
    if ! echo $chid | grep -q -E $CHID_REGEX; then
        echo warning: invalid channel id -- $chid
        continue
    fi

    echo Retrieving videos from channel "$author"...

    # fetch rss feed
    curl -s ${FEED_URL}$chid > $feed_file
    if grep -q "Error 404" $feed_file; then
        echo warning: could not find feed for channel id -- $chid
        continue
    fi

    # parse videos from xml file
    ifs_prev=$IFS
    IFS=\>
    while read -d \< tag content; do
        if [ "$tag" = "yt:videoId" ]; then
            printf "%s%s" "$content" "$SEP"
        elif [ "$tag" = "title" ]; then
            if [ "$(expr length $content)" -gt $TITLE_LEN ];
            then title=$(echo $content | cut -c1-$(expr $TITLE_LEN - 3))..
            else title=$content
            fi
            if [ -x "$(command -v recode)" ]; then
                printf "%s%s%s%s" "$author" "$SEP" "$title" "$SEP" \
                    | recode -q html..ascii
            else
                printf "%s%s%s%s" "$author" "$SEP" "$title" "$SEP"
            fi
        elif [ "$tag" = "published" ]; then
            date=$(date -d "$content" +"$DATE_FMT")
            printf "%s\n" "$date"
        fi
    done < $feed_file | tail -n +2 >> $entries_file
    IFS=$ifs_prev
done < $CHID_FILE

# sort by date and align columns
cat $entries_file | sort -k 4 -t"$SEP" | column -t -s"$SEP"
