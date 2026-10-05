#!/bin/bash
# Usage: run-tests-watched.sh <idle-seconds> <output-file> <command> [args...]
# Runs Gate 4's `swift test` so a hung test cannot hold the CI runner for
# hours with an empty log: the output streams to stdout as it arrives and is
# kept in <output-file> for the summary. After <idle-seconds> without a new
# byte it prints the last started test, the process tree and a stack sample
# of every process of the run, kills them all and exits 124.
# `.timeLimit` does not abort a test that blocks its thread
# (Tests/CompanionIntegrationTests/DiagramTestKit.swift), so the guard lives
# outside the test process. Exit code is the command's otherwise. Bash 3.2.
set -u

usage() { echo "run-tests-watched: usage: <idle-seconds> <output-file> <command> [args...]"; exit 2; }
[ $# -ge 3 ] || usage
idle="$1"
out="$2"
shift 2
case "$idle" in ''|*[!0-9]*) usage ;; esac
[ "$idle" -gt 0 ] || usage
: > "$out" || { echo "run-tests-watched: cannot write $out"; exit 2; }

descendants() {
    local child
    for child in $(pgrep -P "$1"); do
        echo "$child"
        descendants "$child"
    done
}

printed=0
flush() {
    local size
    size=$(wc -c < "$out" | tr -d ' ')
    [ "$size" -gt "$printed" ] || return 1
    tail -c +$((printed + 1)) "$out" | head -c $((size - printed))
    printed=$size
}

# Every signal goes to the whole tree at once.
# The tree is collected again for each signal so a process spawned since the
# last look is not missed, and the earlier list is kept for those whose
# parent already died (reparented to launchd, out of reach of pgrep -P).
killed=""
kill_run() {
    killed="$killed $(descendants "$pid" | tr '\n' ' ') $pid"
    kill -"$1" $killed 2>/dev/null
}

# A child started with & ignores SIGINT in a non-interactive shell, so a
# Ctrl-C on gates.sh would leave swift test running without this.
trap 'kill_run TERM; sleep 1; kill_run KILL; exit 130' INT TERM

# `sample` can wedge on a wedged process; the watchdog itself must end.
capped() {
    local limit="$1" waited=0 cpid
    shift
    "$@" &
    cpid=$!
    while kill -0 "$cpid" 2>/dev/null; do
        if [ "$waited" -ge "$limit" ]; then
            kill -KILL "$cpid" 2>/dev/null
            break
        fi
        sleep 1
        waited=$((waited + 1))
    done
    wait "$cpid" 2>/dev/null
}

"$@" > "$out" 2>&1 &
pid=$!
last_output=$(date +%s)
hung=0
while kill -0 "$pid" 2>/dev/null; do
    sleep 1
    if flush; then
        last_output=$(date +%s)
    elif [ $(( $(date +%s) - last_output )) -ge "$idle" ] && kill -0 "$pid" 2>/dev/null; then
        hung=1
        break
    fi
done

if [ "$hung" -eq 0 ]; then
    wait "$pid"
    rc=$?
    flush
    exit "$rc"
fi

procs="$pid $(descendants "$pid" | tr '\n' ' ')"
echo
echo "FAIL  swift test colgado: ${idle}s sin salida nueva"
last_started=$(grep -E '^◇ Test .* started\.$' "$out" | grep -v '^◇ Test run started\.$' | tail -1)
echo "ultimo test empezado: ${last_started:-ninguno}"
echo
echo "-- arbol de procesos --"
ps -o pid,ppid,stat,etime,command -p "$(echo $procs | tr ' ' ',')"
for p in $procs; do
    echo
    echo "-- muestra de pila de $p --"
    sample_file=$(mktemp "${TMPDIR:-/tmp}/companion-sample.XXXXXX")
    capped 5 sample "$p" 1 -mayDie -file "$sample_file" > /dev/null 2>&1
    # The dylib list after the call graph runs to hundreds of lines and says
    # nothing about where the test is stuck.
    sed '/^Binary Images:/q' "$sample_file"
    rm -f "$sample_file"
done
kill_run TERM
sleep 2
kill_run KILL
wait "$pid" 2>/dev/null
exit 124
