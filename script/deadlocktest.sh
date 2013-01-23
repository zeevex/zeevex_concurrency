#!/bin/zsh
emulate -L zsh
if [ $# -eq 0 ]; then
  SPECS=spec
fi

while true
do 
  echo "RUNNING at `date`"
  debug=true timelimit -t 300 -T 10 bundle exec rspec ${SPECS:-$@}
  echo "FINISHED AT `date`"
  echo
done
