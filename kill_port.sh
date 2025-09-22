#!/bin/bash
PORT=4090

PID=$(lsof -ti :$PORT)

if [ -n "$PID" ]; then
  echo "Killing process $PID running on port $PORT..."
  kill -9 $PID
  echo "Done."
else
  echo "No process found on port $PORT."
fi
