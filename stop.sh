#!/bin/bash
if [ -f phx.pid ]; then
  kill -9 $(cat phx.pid) && echo "Phoenix stopped"
  rm phx.pid
else
  echo "No PID file found"
fi
