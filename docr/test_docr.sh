#!/bin/bash
#==============================================================================
# test_docr.sh — tests for docr's engine selection and output routing
#==============================================================================
# Default run is offline and deterministic: it sources docr (the source guard
# keeps the CLI from executing) to unit-test the pure helpers, and exercises the
# tesseract engine + -o routing on a locally generated image (no network).
#
# Live engine tests (Apple Vision, olmocr2) are opt-in because they need the
# ocrvision binary / a running Ollama. Enable with:  DOCR_LIVE_TESTS=1 ./test_docr.sh
#==============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCR="$SCRIPT_DIR/docr"
PASS=0
FAIL=0

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [[ -n "${2:-}" ]] && printf '       %s\n' "$2"; }

# Source docr to get its helper functions. The source guard prevents the CLI
# from running. ENGINE must be set by hand since docr_main didn't initialize it.
# shellcheck disable=SC1090
source "$DOCR"

#------------------------------------------------------------------------------
echo "tess_to_bcp47 mapping"
#------------------------------------------------------------------------------
[[ "$(tess_to_bcp47 eng)" == "en-US" ]] && ok "eng -> en-US" || bad "eng -> en-US" "got $(tess_to_bcp47 eng)"
[[ "$(tess_to_bcp47 deu)" == "de-DE" ]] && ok "deu -> de-DE" || bad "deu -> de-DE" "got $(tess_to_bcp47 deu)"
[[ "$(tess_to_bcp47 spa)" == "es-ES" ]] && ok "spa -> es-ES" || bad "spa -> es-ES" "got $(tess_to_bcp47 spa)"
[[ "$(tess_to_bcp47 fra)" == "fr-FR" ]] && ok "fra -> fr-FR" || bad "fra -> fr-FR" "got $(tess_to_bcp47 fra)"
[[ -z "$(tess_to_bcp47 xyz)" ]] && ok "unknown -> empty (Vision auto)" || bad "unknown -> empty" "got $(tess_to_bcp47 xyz)"

#------------------------------------------------------------------------------
echo "run_ocr_engine dispatch guard"
#------------------------------------------------------------------------------
ENGINE="bogus"
if run_ocr_engine /dev/null eng 6 /tmp/none 2>/dev/null; then
    bad "unknown engine rejected" "returned 0"
else
    ok "unknown engine rejected (non-zero)"
fi

#------------------------------------------------------------------------------
echo "CLI argument validation"
#------------------------------------------------------------------------------
# Invalid engine must exit non-zero with a clear message, before any processing.
out="$("$DOCR" -e nope /tmp/whatever.pdf 2>&1)"; rc=$?
if [[ $rc -ne 0 && "$out" == *"Unknown engine"* ]]; then
    ok "docr -e nope -> error exit"
else
    bad "docr -e nope -> error exit" "rc=$rc out=$out"
fi

# Missing output dir value must error.
out="$("$DOCR" -o 2>&1)"; rc=$?
if [[ $rc -ne 0 && "$out" == *"Output directory required"* ]]; then
    ok "docr -o (no value) -> error exit"
else
    bad "docr -o (no value) -> error exit" "rc=$rc"
fi

#------------------------------------------------------------------------------
echo "tesseract engine + -o output routing (offline)"
#------------------------------------------------------------------------------
if command -v magick >/dev/null 2>&1 && command -v tesseract >/dev/null 2>&1; then
    TMP="$(mktemp -d)"
    FONT="$(ls /System/Library/Fonts/Supplemental/Arial.ttf /System/Library/Fonts/Helvetica.ttc 2>/dev/null | head -1)"
    IMG="$TMP/in.png"
    if [[ -n "$FONT" ]]; then
        magick -size 700x160 xc:white -gravity northwest -font "$FONT" -pointsize 30 -fill black \
            -annotate +20+60 "HELLO DOCR ENGINE TEST" "$IMG" 2>/dev/null
    else
        magick -size 700x160 xc:white -gravity northwest -pointsize 30 -fill black \
            -annotate +20+60 "HELLO DOCR ENGINE TEST" "$IMG" 2>/dev/null
    fi
    OUTDIR="$TMP/out"
    "$DOCR" -e tesseract -l eng -o "$OUTDIR" "$IMG" >/dev/null 2>&1
    produced="$(ls "$OUTDIR"/ocr_*.txt 2>/dev/null | head -1)"
    if [[ -n "$produced" && -s "$produced" ]]; then
        ok "tesseract wrote output into -o dir"
    else
        bad "tesseract wrote output into -o dir" "no non-empty file in $OUTDIR"
    fi
    # And it must NOT have created an OCR_OUTPUTS next to the input.
    if [[ ! -d "$TMP/OCR_OUTPUTS" ]]; then
        ok "-o suppressed the next-to-input OCR_OUTPUTS folder"
    else
        bad "-o suppressed the next-to-input OCR_OUTPUTS folder" "found $TMP/OCR_OUTPUTS"
    fi
    rm -rf "$TMP"
else
    echo "  skip (magick/tesseract not available)"
fi

#------------------------------------------------------------------------------
# Opt-in live engine tests
#------------------------------------------------------------------------------
if [[ "${DOCR_LIVE_TESTS:-0}" == "1" ]]; then
    echo "LIVE: Apple Vision engine"
    if [[ -x "$SCRIPT_DIR/ocrvision" ]]; then
        TMP="$(mktemp -d)"; FONT="$(ls /System/Library/Fonts/Helvetica.ttc 2>/dev/null | head -1)"
        magick -size 700x160 xc:white -gravity northwest -font "$FONT" -pointsize 30 -fill black \
            -annotate +20+60 "VISION LIVE TEST 42" "$TMP/in.png" 2>/dev/null
        "$DOCR" -e vision -l eng -o "$TMP/out" "$TMP/in.png" >/dev/null 2>&1
        f="$(ls "$TMP/out"/ocr_*.txt 2>/dev/null | head -1)"
        if [[ -n "$f" ]] && grep -q "VISION" "$f" 2>/dev/null; then ok "vision transcribed text"; else bad "vision transcribed text"; fi
        rm -rf "$TMP"
    else
        echo "  skip (ocrvision not built)"
    fi

    echo "LIVE: olmocr2 engine"
    if command -v ollama >/dev/null 2>&1 && ollama list 2>/dev/null | grep -qi olmocr; then
        TMP="$(mktemp -d)"; FONT="$(ls /System/Library/Fonts/Helvetica.ttc 2>/dev/null | head -1)"
        magick -size 700x160 xc:white -gravity northwest -font "$FONT" -pointsize 30 -fill black \
            -annotate +20+60 "OLMOCR LIVE 7" "$TMP/in.png" 2>/dev/null
        "$DOCR" -e olmocr2 -l eng -o "$TMP/out" "$TMP/in.png" >/dev/null 2>&1
        f="$(ls "$TMP/out"/ocr_*.txt 2>/dev/null | head -1)"
        if [[ -n "$f" && -s "$f" ]]; then ok "olmocr2 returned text"; else bad "olmocr2 returned text"; fi
        rm -rf "$TMP"
    else
        echo "  skip (ollama/olmocr2 not available)"
    fi
fi

echo
echo "docr tests: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
