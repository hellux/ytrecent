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
DATE_FMT="%F %H:%M"
# column order for output table
COL_ORDER="author,title,date,id"
# translate html encodings to ascii (eg. &amp; -> &)
RECODE=true
# directory for temporary files
TMP_DIR="/tmp/ytr"

# load user settings
if [ -r $CFG_FILE ]; then
    source $CFG_FILE
fi

column_args="$column_args --table --separator "$SEP" \
             --table-columns title,id,author,date_utc,date \
             --table-hide date_utc \
             --table-order $COL_ORDER"

# temporary files
feeds_dir="$TMP_DIR/feeds"
entries_file="$TMP_DIR/entries"
chids_file="$TMP_DIR/chids"

# make sure dirs exist
mkdir -p $TMP_DIR || exit
mkdir -p $feeds_dir || exit
# empty entries file
rm -f $entries_file || exit

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
            printf "%s" "$content$SEP"
        elif [ "$tag" = "title" ]; then
            title=$content
            printf "%s" "$author$SEP$title$SEP"
        elif [ "$tag" = "published" ]; then
            date_utc=$content
            date=$(date -d "$date_utc" +"$DATE_FMT")
            printf "%s\n" "$date_utc$SEP$date"
        fi
    done < $feed_file | tail -n +2 >> $entries_file
    IFS=$ifs_prev
done < $chids_file

cut -d$SEP -f 3 $entries_file > $TMP_DIR/titles
cut -d$SEP -f 1,2,4,5 $entries_file > $TMP_DIR/rest
paste -d$SEP $TMP_DIR/titles $TMP_DIR/rest > $entries_file
if [ "$RECODE" = "true" ]; then
    if [ -x "$(command -v recode)" ]; then
        recode -q html..ascii $TMP_DIR/titles
    else
        echo "warning: 'recode' not installed, HTML encodings will remain" 1>&2
    fi
fi
rm $TMP_DIR/titles $TMP_DIR/rest

# sort by date_utc and align columns
sort -k 4 -t"$SEP" $entries_file | column $column_args

# clean up
rm $entries_file
rm $chids_file
rm -r $feeds_dir
if [ -z "$(ls -A $TMP_DIR)" ]; then
    rmdir $TMP_DIR
fi
