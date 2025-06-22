# ytrecent

Command line utility for keeping up with YouTube channels.

## Purpose

`ytrecent` is meant to keep track of channels, like YouTube subscriptions, but
without the need of a Google account or navigating the website with a web
browser.

## Installation

Download the `ytr.sh` file, and make it executable `chmod u+x ytr.sh`. Copy
the script into your PATH, e.g. `cp ytr.sh /usr/local/bin/ytr`.

## Function

Subscriptions are kept track of by keeping a list of channels in a local file.
The script checks each listed channel for recent videos and stores their
metadata to a local cache. These videos can then be listed in order of release
date - similar to YouTube's subscription page. The script can also invoke an
external player in order to watch the videos.

Videos can also be found by using the search function and then played by
invoking a video player.

## Requirements

- POSIX shell and utilities
- GNU or BSD `date`
- `column` utility
- external downloader/player, for getting and playing videos (web browser or
  e.g. `mpv` with `youtube-dl`)

## Usage

    usage: ytr <command> [<args>]

    commands:
        channel ch c  -- handle channels to follow
        sync       s  -- fetch list of recent videos from channels
        list    ls l  -- display cached list of videos
        search     S  -- search for videos
        play       p  -- play videos via external player
        help       h  -- show information about ytr and its commands

## Preview

Add some channels to "subscriptions".

    $ ytr channel add https://www.youtube.com/@mikaliden9967
    "mikaliden9967" added, id=UCgYVXKpeB1y-aoFEn0wJ5PA
    $ ytr channel add eaterbc
    "Ben Eater" added, id=UCS0N5baNlQWJCUrhCEo8WlA
    $ ytr channel add https://www.youtube.com/channel/UC1_uAIS3r8Vu6JjXWvastJg
    "Mathologer" added, id=UC1_uAIS3r8Vu6JjXWvastJg
    $ ytr channel add UCYO_jab_esuFRV4b17AJtAw
    "3Blue1Brown" added, id=UCYO_jab_esuFRV4b17AJtAw
    $ ytr channel list
    3Blue1Brown
    Ben Eater
    Mathologer

Synchronize the local cache with the subscribed channels' recent videos.

    $ ytr sync
    45 new video(s) found.

List all videos released in the last month.

    $ ytr list -d 30
    [3]  3Blue1Brown  3b1b featured creators #1                             Wed 27 Jun 18:29
    [2]  Mathologer   Epicycles, complex Fourier and Homer Simpson's orbit  Fri  6 Jul 23:10
    [1]  Ben Eater    Error detection: Parity checking                      Sat 14 Jul 16:37

Play these three videos in order of release.

    $ ytr play 3 2 1

Search for videos.

    $ ytr search ben eater
     :        :                          :                                :           :             :
    [5]   Ben Eater     Making logic gates from transistors             13:02  836 090 views    5 years ago
    [4]   Ben Eater     How do CPUs read machine code? — 6502 part 2    49:13  642 794 views    11 months ago
    [3]   Ben Eater     The world's worst video card?                   32:47  2 940 458 views  1 year ago
    [2]   Ben Eater     “Hello, world” from scratch on a 6502 — Part 1  27:25  1 793 898 views  1 year ago
    [1]   Khan Academy  Interview with Ben Eater                        13:30  88 770 views     5 years ago

Play the first result.

    $ ytr play 1
