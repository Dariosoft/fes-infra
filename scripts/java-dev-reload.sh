#!/bin/sh
set -eu
cd /workspace
src_stamp=$(mktemp)
pom_stamp=$(mktemp)
touch "$src_stamp" "$pom_stamp"

refresh_dependencies() {
  mvn -DskipTests dependency:go-offline
  touch "$pom_stamp"
}

start_app() {
  mvn -o -DskipTests spring-boot:run \
    -Dspring-boot.run.jvmArguments="-Dspring.devtools.restart.poll-interval=2s -Dspring.devtools.restart.quiet-period=1s" &
  app=$!
}

stop_app() {
  if kill -0 "$app" 2>/dev/null; then
    kill "$app"
    wait "$app" || true
  fi
}

refresh_dependencies
start_app

while kill -0 "$app" 2>/dev/null; do
  if find pom.xml -newer "$pom_stamp" -print -quit | grep -q .; then
    stop_app
    refresh_dependencies
    start_app
  elif find src/main -type f -newer "$src_stamp" -print -quit | grep -q .; then
    touch "$src_stamp"
    mvn -o -DskipTests compile || true
  fi
  sleep 2
done
wait "$app"
