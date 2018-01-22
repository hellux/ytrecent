#!/bin/bash

# length and regex to channel ids
CHID_LEN=24
CHID_REGEX=^[a-zA-Z0-9\_-]{$CHID_LEN}$

# url to rss feed with 15 most recent videos
FEED_URL=https://www.youtube.com/feeds/videos.xml?channel_id=

# separator used between fields, choose one that is rarely used in titles
SEP=\~
DATE_FMT="%F %H:%M"
MAX_TITLE_LEN=40

# tmp files
feed_file=/tmp/feed
title_file=/tmp/titles
entries_file=/tmp/entries
parse_file=/tmp/parse

# channel id file format:
# <channel_id> <channel_name>
chid_file=$HOME/.config/ytrecent/channel_ids

# make sure list of entries is empty from start
rm -f $entries_file

while read line; do
    chid=$(echo $line | cut -c1-$CHID_LEN)
    author=$(echo $line | cut -c$(($CHID_LEN+2))-)
    if [[ ! $chid =~ $CHID_REGEX ]]; then
        echo warning: invalid channel id -- $line
        continue
    fi

    curl -s ${FEED_URL}$chid > $feed_file

    grep "Error 404" $feed_file > /dev/null
    if [[ $? == 0 ]]; then
        echo warning: could not find feed for channel id -- $line
        continue
    fi

    echo Retrieving videos from channel "$author"...

    xml_grep --cond yt:videoId --cond title --cond published \
             --text_only $feed_file > $parse_file
    mapfile -t items < $parse_file

    item_count=${#items[@]}
    for ((i = 2; i < $item_count; i+=3)); do
        vid=${items[$i]}
        title=${items[$(($i+1))]}
        date=$(date -d "${items[$(($i+2))]}" +"$DATE_FMT")
        if (( ${#title} > $MAX_TITLE_LEN )); then
            title=$(echo $title | cut -c1-$(($MAX_TITLE_LEN-3)))...
        fi

        echo "$author$SEP$title$SEP$date$SEP$vid"\
            >> $entries_file
    done
done < $chid_file

cat $entries_file | sort -k 3 -t"$SEP" | column -t -s"$SEP"
#rm -f $entries_file
