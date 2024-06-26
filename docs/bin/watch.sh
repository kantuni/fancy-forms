#!/bin/sh

# check whether user had supplied -h or --help . If yes display usage
if [[ ( $@ == "--help") ||  $@ == "-h" ]]
then 
  echo "Usage: $0"
  echo "Starts a watcher in the foreground that will recompile your"
  echo "Elm app as soon as any Elm file changes."
  echo ""
  echo "If you add a new file the watcher has to be restarted."
  echo "You need to reload your browser manually."
  echo "This script works on MacOS only and assumes you have fswatch"
  echo "installed (i.e. via Homebrew)"
  exit 0
fi 

dir=$(dirname $0)/..

$dir/bin/build.sh ../src/Main.elm 

fswatch -x --event Updated $dir/src/** | xargs -n1 -I{} $dir/bin/build.sh {}
