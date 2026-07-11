# DOCR - Document OCR Processing Tools

This directory contains tools for document processing and OCR (Optical Character Recognition).

## Main Tools

- **`docr`** - Main document OCR tool with multi-language support and automatic quality profile detection
- **`GraphPdfOcr.groovy`** - Groovy-based OCR processor (reference implementation)

## Usage

```bash
# Process a document
./docr document.pdf

# Process with specific language
./docr -l spa documento.pdf
```

## Language Support

The `.tesseract.lang.list` file contains all supported languages. Use `./docr --list` to see available options.

## Output

OCR results are saved in `OCR_OUTPUTS/` directory in the same location as the input files.
