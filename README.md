# ytrecent
Command line utility for keeping up with YouTube channels.

## Purpose
ytrecent is meant to keep track of channels, like YouTube subscriptions, but
without the need of a YouTube channel or navigating the website with a web
browser.

## Requirements
* POSIX shell and utilities
* GNU or BSD date
* external player, for playing videos (web browser or player such as mpv)

## Usage
    usage: ytr <command> [<args>]

    commands:
        channel ch c  -- handle channels to follow
        sync       s  -- fetch list of recent videos from channels
        list    ls l  -- display cached list of videos
        play       p  -- play videos via external player
        help       h  -- show information about ytr and its commands

## Preview
Add some channels to "subscriptions".

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

    $ ytr list
    [3]  3Blue1Brown  3b1b featured creators #1                             Ср 27 июн 18:29
    [2]  Mathologer   Epicycles, complex Fourier and Homer Simpson's orbit  Пт  6 июл 23:10
    [1]  Ben Eater    Error detection: Parity checking                      Сб 14 июл 16:37


Play videos in order of release.

    ytr play 3 2 1
