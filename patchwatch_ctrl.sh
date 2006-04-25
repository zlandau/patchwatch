#!/bin/sh

USERNAME=test
PASSWORD=test
HOST="http://localhost:3301/patchwatch/remote"

ALTID=$1
shift
QUERY="username=$USERNAME;password=$PASSWORD;altid=$ALTID"

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

echo curl $HOST -d "$QUERY"
curl $HOST -d "$QUERY"
