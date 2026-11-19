#!/bin/sh
# Publishes the documentation as plain Markdown for language models and tools,
# next to the landing page (GitHub Pages serves docs/):
#
#   docs/articles/<Name>.md   each DocC article, copied as-is
#   docs/llms-full.txt        docs/llms.txt, the README and every article in one file
#
# docs/llms.txt itself is written by hand. Run this after editing an article,
# the README or llms.txt. With --check it changes nothing and fails if the
# published copies are out of date, which is what CI runs.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
docc="$root/Sources/Kadr/Kadr.docc"

# Getting Started and the Cookbook first, then the rest alphabetically. The
# documentation home (Kadr.md) is a symbol index, not prose, so it is left out.
articles() {
    echo GettingStarted
    echo Cookbook
    for article in "$docc"/*.md; do
        name=$(basename "$article" .md)
        case $name in GettingStarted|Cookbook|Kadr) ;; *) echo "$name" ;; esac
    done
}

full() {
    cat "$root/docs/llms.txt"
    printf '\n---\n\n<!-- README.md -->\n\n'
    cat "$root/README.md"
    for name in $(articles); do
        printf '\n---\n\n<!-- Sources/Kadr/Kadr.docc/%s.md -->\n\n' "$name"
        cat "$docc/$name.md"
    done
}

generate() {
    out=$1
    mkdir -p "$out/articles"
    for name in $(articles); do
        cp "$docc/$name.md" "$out/articles/$name.md"
    done
    full > "$out/llms-full.txt"
}

if [ "${1:-}" = "--check" ]; then
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    generate "$tmp"
    if ! diff -ru "$root/docs/articles" "$tmp/articles" ||
       ! diff -u "$root/docs/llms-full.txt" "$tmp/llms-full.txt" >/dev/null; then
        echo "docs/articles or docs/llms-full.txt is out of date. Run Tools/llms-docs.sh." >&2
        exit 1
    fi
else
    rm -rf "$root/docs/articles"
    generate "$root/docs"
fi
