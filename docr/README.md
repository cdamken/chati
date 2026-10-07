# DOCR - Document OCR Processing Tools

This directory contains tools for document processing and OCR (Optical Character Recognition).

## Main Tools

- **`docr`** - Main document OCR tool with multi-language support and automatic quality profile detection
- **`GraphPdfOcr.groovy`** - Groovy-based OCR processor (reference implementation)

## Usage

```bash
# Process a document (tesseract engine, auto quality/language)
./docr document.pdf

# Process with specific language
./docr -l spa documento.pdf

# Apple Vision engine (accents, photos, reads PDF/HEIC directly)
./docr -e vision scan.heic

# olmocr2 vision-LLM for tables/structure, into a chosen output dir
./docr -e olmocr2 -o /tmp/out tablas.pdf
```

## Engines (`-e, --engine`)

| engine | strengths | needs |
|---|---|---|
| `tesseract` (default) | fast, offline, clean prose; multi-profile DPI tuning | `tesseract`, `magick` |
| `vision` | best character accuracy on accents/photos; reads PDF/HEIC natively | the `ocrvision` binary (`swiftc -O ocr_vision.swift -o ocrvision`), macOS |
| `olmocr2` | reconstructs tables/structure as text; best for dosage tables and layout-heavy scans (slower) | Ollama + `richardyoung/olmocr2:7b-q8`, `curl`, `jq` |

The multi-profile DPI search runs for `tesseract` only; `vision`/`olmocr2` rasterize
at a fixed DPI and skip the probing passes. olmocr2 settings are overridable via
`DOCR_OLMOCR_MODEL`, `DOCR_OLMOCR_NUM_CTX`, `DOCR_OLMOCR_HOST`, `DOCR_OLMOCR_PROMPT`.

## Language Support

The `.tesseract.lang.list` file contains all supported languages. Use `./docr --list` to see available options.

## Output

By default OCR results are saved in an `OCR_OUTPUTS/` folder next to the input
files. Pass `-o <dir>` to write them somewhere else — use this to keep OCR
artifacts **out of an indexed corpus tree**, where stray `.txt` files would get
picked up by a RAG index.

## Tests

```bash
bash test_docr.sh                 # offline, deterministic (helpers + tesseract + -o)
DOCR_LIVE_TESTS=1 bash test_docr.sh   # also exercises vision + olmocr2 engines
```
