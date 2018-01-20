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

chid_file=$HOME/.config/ytrecent/channel_ids

rm -f $entries_file

while read line; do
    chid=$(echo $line | cut -c1-$CHID_LEN)
    if [[ ! $chid =~ $CHID_REGEX ]]; then
        echo warning: invalid channel id -- $line
        continue
    fi

    curl -s ${FEED_URL}$chid > $feed_file
    entries=$(xml_grep entry $feed_file)
    author=$(xml_grep --nb_results 1 author /tmp/feed \
           | xml_grep name --text_only)
    rm -f $feed

    vids=( $(echo $entries | xml_grep yt:videoId --text_only) )
    dates=( $(echo $entries | xml_grep published --text_only) )
    echo $entries | xml_grep title --text_only > $title_file
    mapfile -t titles < $title_file
    rm -f $title_file

    for ((i = 0; i < ${#vids[@]}; ++i)); do
        date=$(date -d "${dates[$i]}" +"$DATE_FMT")
        title=${titles[$i]}
        if (( ${#titles[$i]} > MAX_TITLE_LEN )); then
            title=$(echo $title | cut -c1-$(expr $MAX_TITLE_LEN - 3))
            title=$title...
        fi

        echo "$author$SEP$title$SEP$date$SEP${vids[$i]}"\
            >> $entries_file
    done
done < $chid_file

cat $entries_file | sort -k 3 -t"$SEP" | column -t -s"$SEP"
rm -f $title_file
