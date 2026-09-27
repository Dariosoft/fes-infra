#!/bin/sh
set -eu
cd /workspace
stamp=$(mktemp)
touch "$stamp"
mvn -o -DskipTests spring-boot:run \
  -Dspring-boot.run.jvmArguments="-Dspring.devtools.restart.poll-interval=2s -Dspring.devtools.restart.quiet-period=1s" &
app=$!
while kill -0 "$app" 2>/dev/null; do
  if find src/main -type f -newer "$stamp" -print -quit | grep -q .; then
    touch "$stamp"
    mvn -o -DskipTests compile || true
  fi
  sleep 2
done
wait "$app"
