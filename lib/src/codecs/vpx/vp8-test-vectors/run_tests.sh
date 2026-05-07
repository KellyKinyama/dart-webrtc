#!/bin/bash
self=$0
self_basename=${self##*/}
EOL=$'\n'
set -e

show_help() {
    cat <<EOF
Usage: ${self_basename} <path_to_dir_containing_tests>

This script decodes all .ivf files in the given directory, taking an md5sum of
each frame, and comparing the md5sums to known good values in the corresponding
.ivf.md5 file.

Options:
    --help                      Print this message
    --codec=<name>              Codec to pass to example [vp8]
    --exec=<name>               Name of executable to run [./vpxdec]
    --show-fail                 Identifies which frames fail the test
    --threads=<num>             Choose the number of threads to use
EOF
    exit 1
}

die() {
    echo "${self_basename}: $@"
    exit 1
}

die_unknown(){
    echo "Unknown option \"$1\"."
    echo "See ${self_basename} --help for available options."
    exit 1
}

# Process command line
for opt in "$@"; do
    optval="${opt#*=}"
    case "$opt" in
    --help|-h) show_help
    ;;
    --codec=*) codec="--codec=$optval"
    ;;
    --exec=*) executable="$optval"
    ;;
    --show-fail) show_fails=true
    ;;
    --threads=*) threads="-t $optval"
    ;;
    --exit-early) exit_early=true
    ;;
    -*) die_unknown $opt
    ;;
    *) dir="$opt"
    esac
done
[ -n "$dir" ] || show_help
[ -d "$dir" ] || die "Not a directory: $dir"
ext=${codec##--codec=}
ext=${ext:-ivf}
result=0
for f in `ls "$dir"/*.${ext}`; do
    base_name=${f##*/}
    test_name=${base_name%%.*}

    executable=${executable:-./vpxdec}
    case "$executable" in
        *ivfdec)
            ${executable} ${codec} --md5 ${threads} \
                -q -p ${test_name} $f > /tmp/$$.md5
            ;;
        *)
            ${executable} ${codec} --md5 ${threads} \
                -o ${test_name}-%wx%h-%4.i420 --i420 $f > /tmp/$$.md5
    esac

    if diff -ub /tmp/$$.md5 $f.md5 > /tmp/$$.md5.diff; then
        echo $f - pass
    else
        result=1
        fail=`grep ^+ /tmp/$$.md5.diff | wc -l`
        (( fail = fail - 1 ))
        echo $f - FAILED $fail / `wc -l < $f.md5`
        if ${show_fails:-false}; then
            grep ^+ /tmp/$$.md5.diff | awk '{print $2}'
        fi
        if ${exit_early:-false}; then
            rm -f /tmp/$$.md5{,.diff}
            exit 1
        fi
    fi
    rm -f /tmp/$$.md5{,.diff}
done
exit $result
