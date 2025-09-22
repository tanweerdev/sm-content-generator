#!/bin/bash
nohup mix phx.server > phx.log 2>&1 &
echo $! > phx.pid
echo "Phoenix started with PID $(cat phx.pid)"
