#!/bin/sh
# check_links.sh — assembles every source the Mac app and the iPhone app use, and lists any
# symbol one of them calls that none of their own files defines: the link errors, found in
# seconds and without Xcode (a Mac-only file called from a shared one, say). System
# libraries' symbols are left out by name. Runs on a Mac or on Linux with clang and llvm-nm.
# Usage: sh tools/check_links.sh   (exit 1 if anything is missing)
cd "$(dirname "$0")/.." || exit 1
out="${TMPDIR:-/tmp}/asmmesh-links"
rm -rf "$out"; mkdir -p "$out/mac" "$out/ios"
NM=$(command -v llvm-nm || command -v nm)
# what the system gives: libc, libz, the frameworks, the Objective-C and Swift runtimes
SYS='^_(objc_|OBJC_|kCF|CF|NS|kSec|Sec|dispatch_|_|CB|CC|AV|SF|kAudio|Audio|IO|kIO|class_|sel_|object_|ios_|inflate|deflate|compress|uncompress|access|accept|alphasort|arc4random|atof|atoi|atol|bind|bzero|calloc|clock_gettime|close|cos|dladdr|dup|exit|fclose|fcntl|fopen|fprintf|free|freeaddrinfo|freeifaddrs|fstat|getaddrinfo|getenv|gethostname|getifaddrs|inet_|kill|listen|localtime_r|log10|lseek|malloc|mem|mkdir|mkdtemp|nanosleep|open|pipe|posix_spawn|pow|printf|pthread_|read|recvfrom|rmdir|scandir|sendto|setenv|setsockopt|sigaction|siglongjmp|sigsetjmp|sin|snprintf|socket|socketpair|stat|str|time|unlink|usleep|waitpid|write)'
missing=0
check() {   # name, target, object dir, sources...
    name=$1; target=$2; dir=$3; shift 3
    for f in "$@"; do
        clang -target "$target" -c "$f" -I src -o "$dir/$(basename "$f" .s).o" || { echo "$name: $f doesn't assemble"; missing=1; }
    done
    "$NM" -U "$dir"/*.o 2>/dev/null | awk 'NF==3{print $3}' | sort -u > "$dir/defined"
    "$NM" -u "$dir"/*.o 2>/dev/null | awk '{print $NF}' | grep '^_' | sort -u > "$dir/used"
    gone=$(comm -23 "$dir/used" "$dir/defined" | grep -vE "$SYS")
    if [ -n "$gone" ]; then echo "$name: called but not defined:"; echo "$gone" | sed 's/^/    /'; missing=1
    else echo "$name: every symbol found"; fi
}
check Mac arm64-apple-macos12 "$out/mac" $(sed -n '/^SRCS/,/^OBJS/p' Makefile | grep -oE '[a-z_0-9]+[.]s' | sed 's|^|src/|')
core=$(python3 -c "import re;s=open('ios/make_project.py').read();print(' '.join('src/%s.s' % w for w in re.search(r'CORE = \"\"\"(.*?)\"\"\"', s, re.S).group(1).split()))")
check iPhone arm64-apple-ios15 "$out/ios" $core ios/asm/ios_ui.s
exit $missing
