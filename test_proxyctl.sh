#!/bin/sh
# Test suite for proxyctl.
#
# Every case runs in a fresh `env -i` shell under each shell in $SHELLS (dash
# and bash by default). A case checks the return code, the stderr message, the
# six managed variables, that NO_PROXY/no_proxy are untouched, and that
# sourcing leaves no proxyctl_* variable or function behind.
#
# Usage: ./test_proxyctl.sh [dash|bash ...]

PROXYCTL_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$PROXYCTL_DIR" || exit 1

SHELLS=${*:-"dash bash"}
TOTAL=0
FAILED=0
FAILED_NAMES=''
SEED='HTTP_PROXY=old NO_PROXY=keep no_proxy=keep ALL_PROXY=oldall'

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

pass() {
    TOTAL=$((TOTAL + 1))
    printf 'PASS  %s\n' "$1"
}

fail() {
    TOTAL=$((TOTAL + 1))
    FAILED=$((FAILED + 1))
    FAILED_NAMES="$FAILED_NAMES
    $1"
    printf 'FAIL  %s\n' "$1"
    shift
    for _d in "$@"; do printf '        %s\n' "$_d"; done
}

# Print the value of a variable, or <unset> when it is not set.
value_of() {
    eval "_value=\${$1-<unset>}"
    printf '%s' "$_value"
}

# case_rc NAME EXPECT_RC EXPECT_ERR EXPECT_STATE
# EXPECT_STATE is a newline-separated list of VAR=value pairs describing the
# six managed variables, NO_PROXY and no_proxy afterwards.
case_rc() {
    _name=$1 _want_rc=$2 _want_err=$3 _want_state=$4
    shift 4

    for _sh in $SHELLS; do
        _tag="$_sh: $_name"
        _body="$WORK/case.sh"

        {
            printf 'set --'
            for _a in "$@"; do printf " '%s'" "$_a"; done
            printf '\n. ./proxyctl >/dev/null\n'
            printf 'printf "%%s\\n" "$?" > "$LEFTOVER_DIR/result.%s"\n' "$_sh"
            printf 'for _v in HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy NO_PROXY no_proxy; do\n'
            printf '  eval "_x=\\${$_v-<unset>}"; printf "%%s=%%s\\n" "$_v" "$_x" >> "$LEFTOVER_DIR/result.%s"\n' "$_sh"
            printf 'done\n'
            printf 'set | grep proxyctl > "$LEFTOVER_DIR/left_vars.%s" || :\n' "$_sh"
            printf 'command -v proxyctl_set proxyctl_validate_url > "$LEFTOVER_DIR/left_fns.%s" 2>/dev/null || :\n' "$_sh"
        } > "$_body"

        rm -f "$WORK/result.$_sh"
        env -i $SEED "LEFTOVER_DIR=$WORK" "$_sh" "$_body" >/dev/null 2>"$WORK/err"
        _result=$(cat "$WORK/result.$_sh" 2>/dev/null)
        _got_rc=$(printf '%s\n' "$_result" | sed -n 1p)
        _got_state=$(printf '%s\n' "$_result" | sed -n '2,9p')
        _got_err=$(cat "$WORK/err")

        _problem=''
        [ "$_got_rc" = "$_want_rc" ] || _problem="return code: got [$_got_rc] want [$_want_rc]"
        if [ -z "$_problem" ] && [ "$_got_err" != "$_want_err" ]; then
            _problem="stderr: got [$_got_err] want [$_want_err]"
        fi
        if [ -z "$_problem" ] && [ "$_got_state" != "$_want_state" ]; then
            _problem="state:
$(printf '%s' "$_got_state" | sed 's/^/          got  /')
$(printf '%s' "$_want_state" | sed 's/^/          want /')"
        fi
        if [ -z "$_problem" ] && [ -s "$WORK/left_vars.$_sh" ]; then
            _problem="leftover variables: $(tr '\n' ' ' < "$WORK/left_vars.$_sh")"
        fi
        if [ -z "$_problem" ] && [ -s "$WORK/left_fns.$_sh" ]; then
            _problem="leftover functions: $(tr '\n' ' ' < "$WORK/left_fns.$_sh")"
        fi

        if [ -z "$_problem" ]; then pass "$_tag"; else fail "$_tag" "$_problem"; fi
    done
}

# Shorthand for the two environment variables that must never move.
KEEP='NO_PROXY=keep
no_proxy=keep'

# norm VAR -- turn the "-" placeholder into the <unset> marker.
norm() {
    if [ "$1" = '-' ]; then printf '<unset>'; else printf '%s' "$1"; fi
}

# state6 HTTP HTTPS lower_http lower_https ALL lower_all
# A "-" in this table means the variable is not set; the generated script
# reports that as <unset>.
state6() {
    printf 'HTTP_PROXY=%s
HTTPS_PROXY=%s
http_proxy=%s
https_proxy=%s
ALL_PROXY=%s
all_proxy=%s' "$(norm "$1")" "$(norm "$2")" "$(norm "$3")" \
        "$(norm "$4")" "$(norm "$5")" "$(norm "$6")"
}

# state6 ... followed by the protected variables.
state() {
    state6 "$@" | { cat; printf '\n%s\n' "$KEEP"; }
}

URL='http://a.b:1'
URL2='http://c.d:2'
E='proxyctl: '

printf '=== proxyctl test suite ===\n'

for _sh in $SHELLS; do
    printf '\n--- %s ---\n' "$_sh"
    _url=$URL

    # ---- pre-existing behaviour that must not regress ----
    case_rc "set: all six from one URL" 0 '' \
        "$(state "$_url" "$_url" "$_url" "$_url" "$_url" "$_url")" \
        set "$_url"

    case_rc "set: --all-proxy overrides only ALL" 0 '' \
        "$(state "$_url" "$_url" "$_url" "$_url" "$URL2" "$URL2")" \
        set "$_url" --all-proxy "$URL2"

    case_rc "set: repeated --all-proxy last wins" 0 '' \
        "$(state "$_url" "$_url" "$_url" "$_url" "$URL2" "$URL2")" \
        set "$_url" --all-proxy http://first.d:3 --all-proxy "$URL2"

    case_rc "set: existing ALL_PROXY replaced" 0 '' \
        "$(state "$_url" "$_url" "$_url" "$_url" "$_url" "$_url")" \
        set "$_url"

    case_rc "set: unexpected argument" 2 "${E}unexpected argument: garbage" \
        "$(state old - - - oldall -)" set "$_url" garbage

    case_rc "set: missing --all-proxy value" 2 "${E}missing value for --all-proxy" \
        "$(state old - - - oldall -)" set "$_url" --all-proxy

    case_rc "set: --all-proxy before URL" 2 "${E}invalid proxy URL: --all-proxy" \
        "$(state old - - - oldall -)" set --all-proxy "$URL2" "$_url"

    case_rc "set: help" 0 '' \
        "$(state old - - - oldall -)" set --help

    case_rc "unset: --http-proxy" 0 '' \
        "$(state - - - - oldall -)" unset --http-proxy
    case_rc "unset: --https-proxy" 0 '' \
        "$(state old - - - oldall -)" unset --https-proxy
    case_rc "unset: --all-proxy" 0 '' \
        "$(state old - - - - -)" unset --all-proxy
    case_rc "unset: -a" 0 '' \
        "$(state - - - - - -)" unset -a
    case_rc "unset: -a first" 0 '' \
        "$(state - - - - - -)" unset -a --http-proxy
    case_rc "unset: -a last" 0 '' \
        "$(state - - - - - -)" unset --http-proxy -a
    case_rc "unset: unknown option" 2 "${E}unknown unset option: --bogus" \
        "$(state old - - - oldall -)" unset --bogus
    case_rc "unset: help" 0 '' \
        "$(state old - - - oldall -)" unset --help

    case_rc "status: reports proxy variables" 0 '' \
        "$(state old - - - oldall -)" status
    case_rc "status: unexpected argument" 2 "${E}unexpected argument: extra" \
        "$(state old - - - oldall -)" status extra

    case_rc "dispatch: unknown subcommand" 2 "${E}unknown subcommand: frobnicate" \
        "$(state old - - - oldall -)" frobnicate
    case_rc "dispatch: SET is not set" 2 "${E}unknown subcommand: SET" \
        "$(state old - - - oldall -)" SET
    case_rc "dispatch: Unset is not unset" 2 "${E}unknown subcommand: Unset" \
        "$(state old - - - oldall -)" Unset
    case_rc "dispatch: STATUS is not status" 2 "${E}unknown subcommand: STATUS" \
        "$(state old - - - oldall -)" STATUS
    case_rc "dispatch: HELP is not help" 2 "${E}unknown subcommand: HELP" \
        "$(state old - - - oldall -)" HELP
    case_rc "dispatch: --HTTP-PROXY is not an option" 2 "${E}unknown unset option: --HTTP-PROXY" \
        "$(state old - - - oldall -)" unset --HTTP-PROXY

    # ---- Issue 2: bare invocation in a shell whose '.' takes arguments ----
    case_rc "issue2: bare source shows the set -- hint" 2 \
        "${E}missing subcommand (if your shell's '.' ignores arguments, run: set -- ARGS; . ./proxyctl)" \
        "$(state old - - - oldall -)"

    # ---- Issue 3: port validation ----
    for _p in 1 8080 08080 65535; do
        case_rc "issue3: port $_p accepted" 0 '' \
            "$(state "http://a.b:$_p" "http://a.b:$_p" "http://a.b:$_p" "http://a.b:$_p" "http://a.b:$_p" "http://a.b:$_p")" \
            set "http://a.b:$_p"
    done
    for _p in 0 00 000 65536 099999 99999999999999999999 8o80; do
        case_rc "issue3: port $_p rejected" 2 "${E}invalid proxy URL: http://a.b:$_p" \
            "$(state old - - - oldall -)" set "http://a.b:$_p"
    done
    case_rc "issue3: empty port rejected" 2 "${E}invalid proxy URL: http://a.b:" \
        "$(state old - - - oldall -)" set 'http://a.b:'

    # ---- Issue 4: bracketed IPv6 ----
    for _h in '[::1]:8080' '[::1]' '[::]' '[2001:db8::1]:3128' '[fe80::1]' \
              '[1:2:3:4:5:6:7:8]' '[::ffff:192.0.2.1]'; do
        _u="http://$_h"
        case_rc "issue4: $_h accepted" 0 '' \
            "$(state "$_u" "$_u" "$_u" "$_u" "$_u" "$_u")" set "$_u"
    done
    for _h in '[a]' '[:]' '[1.2.3.4]' '[:::]' '[1::2::3]' '[12345::1]' \
              '[1:2:3:4:5:6:7]' '[:1]' '[1:]' '[g::1]' '[]' '[::1]]:80' \
              '[::1]:80]:90' '[::1]:8080]garbage' '[::1]x:80' '[::1'; do
        _u="http://$_h"
        case_rc "issue4: $_h rejected" 2 "${E}invalid proxy URL: $_u" \
            "$(state old - - - oldall -)" set "$_u"
    done

    # ---- Issue 5: DNS host and IPv4 ----
    for _h in proxy.example.com a host1 a-b.example.com xn--abc.example \
              my_proxy 192.168.1.10 0.0.0.0 255.255.255.255; do
        _u="http://$_h"
        case_rc "issue5: host $_h accepted" 0 '' \
            "$(state "$_u" "$_u" "$_u" "$_u" "$_u" "$_u")" set "$_u"
    done
    for _h in -foo.example.com foo-.example.com foo- foo.-bar.com foo.bar-.com - \
              999.999.999.999 1.2.3 1.2.3.4.5 12345 256.1.1.1 \
              .example.com a..b example.com.; do
        _u="http://$_h"
        case_rc "issue5: host $_h rejected" 2 "${E}invalid proxy URL: $_u" \
            "$(state old - - - oldall -)" set "$_u"
    done
    _l64=$(printf 'a%.0s' $(seq 64 2>/dev/null) || true)
    if [ -z "$_l64" ]; then _l64=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; fi
    case_rc "issue5: 64-character label rejected" 2 \
        "${E}invalid proxy URL: http://$_l64.com" \
        "$(state old - - - oldall -)" set "http://$_l64.com"
    _h253=$(printf 'a%.0s' $(seq 250 2>/dev/null) || true)
    if [ -z "$_h253" ]; then _h253=; fi
    case_rc "issue5: 254-character host rejected" 2 \
        "${E}invalid proxy URL: http://${_h253}.abc" \
        "$(state old - - - oldall -)" set "http://${_h253}.abc"

    # ---- Issue 6: --all-proxy with an empty value ----
    case_rc "issue6: --all-proxy '' rejected" 2 "${E}invalid --all-proxy URL: " \
        "$(state old - - - oldall -)" set "$_url" --all-proxy ''
    case_rc "issue6: good then empty rejected" 2 "${E}invalid --all-proxy URL: " \
        "$(state old - - - oldall -)" set "$_url" --all-proxy "$URL2" --all-proxy ''

    # ---- Issue 7: every --all-proxy occurrence is validated ----
    case_rc "issue7: bad then good rejected" 2 "${E}invalid --all-proxy URL: garbage" \
        "$(state old - - - oldall -)" set "$_url" --all-proxy garbage --all-proxy "$URL2"
    case_rc "issue7: two good values, last wins" 0 '' \
        "$(state "$_url" "$_url" "$_url" "$_url" "$URL2" "$URL2")" \
        set "$_url" --all-proxy http://first.d:3 --all-proxy "$URL2"

    # ---- Issue 8: bare set / unset ----
    case_rc "issue8: bare set says missing proxy URL" 2 "${E}missing proxy URL" \
        "$(state old - - - oldall -)" set
    case_rc "issue8: bare unset says requires an option" 2 \
        "${E}unset requires at least one option" \
        "$(state old - - - oldall -)" unset
done

# ==========================================================================
# Issue 1: a wrapper script that sources proxyctl must survive every path.
# These are the cases that used to kill the caller with exit.
# ==========================================================================
printf '\n--- wrapper survival (issue 1) ---\n'

wrapper_case() {
    _name=$1 _want_rc=$2 _want_err=$3 _want_line=$4
    shift 4

    for _sh in $SHELLS; do
        _tag="$_sh wrapper: $_name"
        _body="$WORK/wrap.sh"
        {
            printf 'set --'
            for _a in "$@"; do printf " '%s'" "$_a"; done
            printf '\n'
            # help and status write to stdout, so the wrapper's own bookkeeping
            # goes to a file instead of being mixed in with them.
            printf '. ./proxyctl\n'
            printf 'printf "rc=%%s\\n" "$?" >> "$LEFTOVER_DIR/wrap.%s"\n' "$_sh"
            printf 'printf "http=%%s all=%%s no=%%s\\n" "${HTTP_PROXY-}" "${ALL_PROXY-}" "${NO_PROXY-}" >> "$LEFTOVER_DIR/wrap.%s"\n' "$_sh"
            printf 'printf "still-here\\n" >> "$LEFTOVER_DIR/wrap.%s"\n' "$_sh"
        } > "$_body"

        rm -f "$WORK/wrap.$_sh"
        env -i $SEED "LEFTOVER_DIR=$WORK" "$_sh" "$_body" >/dev/null 2>"$WORK/err"
        _out=$(cat "$WORK/wrap.$_sh" 2>/dev/null)
        _got_rc=$(printf '%s\n' "$_out" | sed -n 1p)
        _got_rc=${_got_rc#rc=}
        _got_line=$(printf '%s\n' "$_out" | sed -n 2p)
        _got_err=$(cat "$WORK/err")
        _survived=$(printf '%s\n' "$_out" | grep -c '^still-here$')

        _problem=''
        [ "$_survived" = 1 ] || _problem="the wrapper was terminated before its last line"
        if [ -z "$_problem" ] && [ "$_got_rc" != "$_want_rc" ]; then
            _problem="return code: got [$_got_rc] want [$_want_rc]"
        fi
        if [ -z "$_problem" ] && [ "$_got_err" != "$_want_err" ]; then
            _problem="stderr: got [$_got_err] want [$_want_err]"
        fi
        if [ -z "$_problem" ] && [ "$_got_line" != "$_want_line" ]; then
            _problem="state: got [$_got_line] want [$_want_line]"
        fi
        if [ -z "$_problem" ]; then pass "$_tag"; else fail "$_tag" "$_problem"; fi
    done
}

wrapper_case "set: valid URL" 0 '' 'http=http://a.b:1 all=http://a.b:1 no=keep' \
    set 'http://a.b:1'
wrapper_case "set: invalid URL" 2 "${E}invalid proxy URL: garbage" 'http=old all=oldall no=keep' \
    set garbage
wrapper_case "set: bare" 2 "${E}missing proxy URL" 'http=old all=oldall no=keep' \
    set
wrapper_case "unset -a" 0 '' 'http= all= no=keep' \
    unset -a
wrapper_case "unset: bare" 2 "${E}unset requires at least one option" 'http=old all=oldall no=keep' \
    unset
wrapper_case "status" 0 '' 'http=old all=oldall no=keep' \
    status
wrapper_case "help" 0 '' 'http=old all=oldall no=keep' \
    help
wrapper_case "unknown subcommand" 2 "${E}unknown subcommand: frobnicate" 'http=old all=oldall no=keep' \
    frobnicate
wrapper_case "bare invocation" 2 \
    "${E}missing subcommand (if your shell's '.' ignores arguments, run: set -- ARGS; . ./proxyctl)" \
    'http=old all=oldall no=keep'

# ==========================================================================
# Issue 1: direct execution is refused for operational commands, allowed for
# help.
# ==========================================================================
printf '\n--- direct execution (issue 1) ---\n'

direct_case() {
    _name=$1 _want_rc=$2 _want_err=$3
    shift 3

    for _sh in $SHELLS; do
        _tag="$_sh direct: $_name"
        _out=$(env -i $SEED "$_sh" ./proxyctl "$@" 2>"$WORK/err" >/dev/null)
        _got_rc=$?
        _got_err=$(cat "$WORK/err")

        _problem=''
        [ "$_got_rc" = "$_want_rc" ] || _problem="return code: got [$_got_rc] want [$_want_rc]"
        if [ -z "$_problem" ] && [ "$_got_err" != "$_want_err" ]; then
            _problem="stderr: got [$_got_err] want [$_want_err]"
        fi
        if [ -z "$_problem" ]; then pass "$_tag"; else fail "$_tag" "$_problem"; fi
    done
}

direct_case "set is refused" 2 "${E}operation requires the script to be sourced" set 'http://a.b:1'
direct_case "unset is refused" 2 "${E}operation requires the script to be sourced" unset -a
direct_case "status is refused" 2 "${E}operation requires the script to be sourced" status
direct_case "help succeeds" 0 '' help
direct_case "--help succeeds" 0 '' --help
direct_case "-h succeeds" 0 '' -h

# ==========================================================================
# Syntax checks and a run under `set -u`.
# ==========================================================================
printf '\n--- syntax and set -u ---\n'

syntax_case() {
    _name=$1
    shift
    if "$@" >"$WORK/out" 2>"$WORK/err"; then
        pass "syntax: $_name"
    else
        fail "syntax: $_name" "$(cat "$WORK/err")"
    fi
}

syntax_case "sh -n proxyctl" sh -n proxyctl
syntax_case "bash -n proxyctl" bash -n proxyctl
syntax_case "dash -n proxyctl" dash -n proxyctl

if command -v shellcheck >/dev/null 2>&1; then
    printf 'shellcheck: '
    if shellcheck -s sh proxyctl >"$WORK/sc" 2>&1; then
        printf 'clean\n'
        pass "shellcheck reports no warnings"
    else
        cat "$WORK/sc"
        fail "shellcheck reports no warnings" "$(head -5 "$WORK/sc")"
    fi
else
    printf 'shellcheck: not installed, skipped\n'
fi

for _sh in $SHELLS; do
    _body="$WORK/nounset.sh"
    {
        printf 'set -u\n'
        printf "set -- set 'http://a.b:1' --all-proxy 'http://c.d:2'\n"
        printf '. ./proxyctl\n'
        printf 'printf "rc=%%s http=%%s all=%%s\\n" "$?" "$HTTP_PROXY" "$ALL_PROXY"\n'
        printf "set -- set garbage\n"
        printf '. ./proxyctl\n'
        printf 'printf "rc2=%%s\\n" "$?"\n'
        printf "set -- set 'http://a.b:1' --all-proxy ''\n"
        printf '. ./proxyctl\n'
        printf 'printf "rc3=%%s\\n" "$?"\n'
        printf "set -- frobnicate\n"
        printf '. ./proxyctl\n'
        printf 'printf "rc4=%%s\\n" "$?"\n'
    } > "$_body"

    _out=$(env -i $SEED "$_sh" "$_body" 2>"$WORK/err")
    _err=$(cat "$WORK/err")
    _want='rc=0 http=http://a.b:1 all=http://c.d:2
rc2=2
rc3=2
rc4=2'
    _want_err="proxyctl: invalid proxy URL: garbage
proxyctl: invalid --all-proxy URL: 
proxyctl: unknown subcommand: frobnicate"
    if [ "$_out" = "$_want" ] && [ "$_err" = "$_want_err" ]; then
        pass "$_sh: set -u run"
    else
        fail "$_sh: set -u run" "stdout:
$(printf '%s' "$_out" | sed 's/^/          /')
stderr: [$_err]
want:
$(printf '%s' "$_want" | sed 's/^/          /')"
    fi
done

# ==========================================================================
# Summary
# ==========================================================================
printf '\n=========================================\n'
printf 'total: %s   passed: %s   failed: %s\n' \
    "$TOTAL" "$((TOTAL - FAILED))" "$FAILED"
if [ "$FAILED" -ne 0 ]; then
    printf 'failing cases:%s\n' "$FAILED_NAMES"
    exit 1
fi
printf 'all cases passed\n'
exit 0
