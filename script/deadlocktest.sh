#!/bin/zsh
emulate -L zsh
if [ ! -z "$@" ]; then
  SPECS=$@
else
  SPECS=spec
fi

while true
do 
  echo "RUNNING at `date`"
  debug=true timelimit -t 300 -T 10 bundle exec rspec $SPECS
  echo "FINISHED AT `date`"
  echo
done
