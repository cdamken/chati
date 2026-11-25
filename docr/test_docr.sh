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
echo "D1: combine_pdf_outputs orders pages numerically (10+ pages)"
#------------------------------------------------------------------------------
TMP="$(mktemp -d)"
for n in 1 2 9 10 11 12; do printf 'PAGE%d\n' "$n" > "$TMP/ocr_doc_page$(printf '%04d' "$n").txt"; done
combine_pdf_outputs "doc" "$TMP" >/dev/null 2>&1
combined="$TMP/ocr_doc.txt"
order="$(grep -o 'PAGE[0-9]*' "$combined" 2>/dev/null | sed 's/PAGE//' | tr '\n' ' ')"
if [[ "$order" == "1 2 9 10 11 12 " ]]; then ok "pages combined in numeric order"; else bad "pages combined in numeric order" "got: '$order'"; fi
# A set with no page files must FAIL, not look like one page (nullglob, D5).
if combine_pdf_outputs "nonexistent_base" "$TMP" >/dev/null 2>&1; then
    bad "empty page set returns non-zero" "returned 0 (literal-glob bug)"
else
    ok "empty page set returns non-zero (nullglob)"
fi
rm -rf "$TMP"

#------------------------------------------------------------------------------
echo "D2/D3/D4: AI side-queries and language detection"
#------------------------------------------------------------------------------
# D2: internal AI queries go through run_ai_side_query (sends the prompt TEXT and
# isolates the session), never a direct command-substitution call on $chat_cmd
# (which sent the model the temp-file PATH as the message).
if grep -q 'run_ai_side_query' "$DOCR" && ! grep -qF '$("$chat_cmd"' "$DOCR"; then
    ok "AI side-queries use run_ai_side_query (text, isolated session)"
else
    bad "AI side-queries use run_ai_side_query" "a direct \$(\$chat_cmd …) call remains"
fi
# D3: detection progress must go to stderr so the caller captures only the code.
if awk '/^detect_language_with_ai\(\)/{f=1} f' "$DOCR" | grep -q 'Analyzing text for language.*>&2'; then
    ok "detect_language_with_ai progress -> stderr"
else
    bad "detect_language_with_ai progress -> stderr"
fi
# D3: the detected language must actually drive the OCR run.
if grep -q 'CURRENT_LANG="\$DETECTED_LANGUAGE"' "$DOCR"; then
    ok "detected language applied to the OCR run"
else
    bad "detected language applied to the OCR run"
fi
# D4: the olmocr2 base64 image must go via --rawfile (argv-size-safe on Linux).
if grep -q 'rawfile img' "$DOCR" && ! grep -q -- '--arg img' "$DOCR"; then
    ok "olmocr2 image via --rawfile (not argv)"
else
    bad "olmocr2 image via --rawfile" "still uses --arg img (128KB argv limit)"
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
