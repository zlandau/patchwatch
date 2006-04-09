#!/bin/sh

USERNAME=test
PASSWORD=test
HOST="http://butter.homeunix.net:3301/patchwatch/remote"

MSGID=`egrep '^Message-Id: (<[^>]*>)' | cut -f2 -d' '`

QUERY="username=$USERNAME;password=$PASSWORD;msgid=$MSGID"

while [ $1 ]; do
    case "$1" in
        state)
            shift
            QUERY="$QUERY;state=$1"
        ;;
        branches)
            shift
            QUERY="$QUERY;branches=$1"
        ;;
        *)
            echo "Invalid command: $1"
            exit 1
        ;;
    esac
    shift
done

curl $HOST -d "$QUERY"
