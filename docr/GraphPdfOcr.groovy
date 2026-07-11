#!/usr/bin/env groovy

/**
 * GRAPH_PDF_OCR - Document Processing and OCR Chat Tool (Groovy Implementation)
 * =============================================================================
 * Author: Carlos Damken (Groovy implementation)
 * Created: 2025
 * Last Modified: 2025-06-03
 *
 * Description:
 *   Advanced document processing tool that combines OCR (Optical Character
 *   Recognition) with chat capabilities. Processes PDFs, images, and graphs,
 *   extracts text content, and enables intelligent conversation about the
 *   document contents.
 *
 * Features:
 *   - PDF processing and conversion
 *   - Image OCR with Tesseract
 *   - Multi-language support
 *   - Graph and chart processing
 *   - Automatic language detection
 *   - Integration with chat backends
 *
 * Usage:
 *   ./GraphPdfOcr.groovy file.pdf           # Process PDF
 *   ./GraphPdfOcr.groovy image.png          # Process image
 *   ./GraphPdfOcr.groovy -l eng file.jpg    # Specify language
 *   ./GraphPdfOcr.groovy -h                 # Show help
 *
 * Dependencies:
 *   - tesseract (brew install tesseract tesseract-lang)
 *   - imagemagick (brew install imagemagick)
 *   - ghostscript (for PDF processing)
 */

import java.nio.file.Files
import java.nio.file.Paths
import java.nio.file.Path
import groovy.io.FileType

class GraphPdfOcr {
    String defaultLanguage = "eng"
    String ocrOutputs
    String langFile = System.getProperty("user.home") + "/.tesseract.lang.list"
    String detectedScript = null
    
    // Constructor
    GraphPdfOcr() {
        // Check for required commands
        ["tesseract", "magick"].each { cmd ->
            def process = ["which", cmd].execute()
            process.waitFor()
            if (process.exitValue() != 0) {
                println "Error: Required command '${cmd}' not found."
                println "Please install:"
                println "  tesseract: brew install tesseract tesseract-lang"
                println "  magick: brew install imagemagick"
                System.exit(1)
            }
        }
    }
    
    // Process a single file (image or PDF)
    boolean processFile(String filePath, String currentLang, String outputDir) {
        File file = new File(filePath)
        if (!file.exists()) {
            println "Error: File not found: ${filePath}"
            return false
        }
        
        boolean isPdf = filePath.toLowerCase().endsWith(".pdf")
        String filename = file.name
        String filenameWithoutExt = filename.lastIndexOf('.').with { it != -1 ? filename[0..<it] : filename }
        
        if (isPdf) {
            println "Processing PDF file: ${filename}"
            
            // Create temporary directory for PDF pages
            Path tempDir = Files.createTempDirectory("pdf_pages_")
            
            // Convert PDF to images (one per page)
            def convertProcess = ["magick", "-density", "300", filePath, "${tempDir}/page-%04d.png"].execute()
            def convertOutput = new StringBuffer()
            def convertError = new StringBuffer()
            convertProcess.consumeProcessOutput(convertOutput, convertError)
            convertProcess.waitFor()
            
            if (convertProcess.exitValue() != 0) {
                println "Error: Failed to process PDF '${filePath}'"
                println convertError.toString()
                tempDir.toFile().deleteDir()
                return false
            }
            
            // Process each page
            int pageNum = 1
            tempDir.toFile().eachFileMatch(FileType.FILES, ~/page-.*\.png/) { page ->
                println "Processing page ${pageNum}..."
                processSingleImage(page.absolutePath, currentLang, outputDir, "${filenameWithoutExt}_page${pageNum}")
                pageNum++
            }
            
            // Clean up
            tempDir.toFile().deleteDir()
            
            // After processing all PDF pages, combine the outputs
            combinePdfOutputs(filenameWithoutExt, outputDir)
            return true
        } else {
            // Process regular image
            return processSingleImage(filePath, currentLang, outputDir, filenameWithoutExt)
        }
    }
    
    // Process a single image
    boolean processSingleImage(String filePath, String currentLang, String outputDir, String outputName) {
        File file = new File(filePath)
        
        // Create a temporary file with increased resolution
        File tempFile = File.createTempFile("ocr_", ".img")
        
        // Process the image
        def convertProcess = ["magick", filePath, "-density", "300", tempFile.absolutePath].execute()
        def convertOutput = new StringBuffer()
        def convertError = new StringBuffer()
        convertProcess.consumeProcessOutput(convertOutput, convertError)
        convertProcess.waitFor()
        
        if (convertProcess.exitValue() != 0) {
            println "Error: Failed to process '${filePath}'. Not a valid image?"
            tempFile.delete()
            return false
        }
        
        // Try to detect language if default language and none specified
        if (defaultLanguage == "eng" && (currentLang == null || currentLang.isEmpty())) {
            print "Analyzing '${file.name}' for language... "
            
            if (detectLanguage(tempFile.absolutePath)) {
                print "Detected script: ${detectedScript}. Try OCR with this script? [Y/n] "
                def reader = new BufferedReader(new InputStreamReader(System.in))
                String reply = reader.readLine()
                
                if (reply == null || !reply.toLowerCase().startsWith('n')) {
                    currentLang = "script/${detectedScript}"
                }
            } else {
                println "Could not detect script, using default (${defaultLanguage})"
                currentLang = defaultLanguage
            }
        } else if (currentLang == null || currentLang.isEmpty()) {
            currentLang = defaultLanguage
        }
        
        // Perform OCR using tesseract and save output
        def ocrProcess = ["tesseract", "-l", currentLang, "--psm", "6", 
                          tempFile.absolutePath, "${outputDir}/ocr_${outputName}"].execute()
        def ocrOutput = new StringBuffer()
        def ocrError = new StringBuffer()
        ocrProcess.consumeProcessOutput(ocrOutput, ocrError)
        ocrProcess.waitFor()
        
        // Remove the temporary file
        tempFile.delete()
        
        // Check if tesseract executed successfully
        if (ocrProcess.exitValue() == 0) {
            File outputFile = new File("${outputDir}/ocr_${outputName}.txt")
            if (outputFile.exists() && outputFile.length() > 0) {
                int lineCount = outputFile.text.count('\n') + 1
                println "✓ OCR output for '${file.name}' saved (${lineCount} lines)"
            } else {
                println "! OCR completed for '${file.name}' but no text was found"
            }
            return true
        } else {
            println "✗ Error: OCR failed to process '${file.name}'"
            println ocrError.toString()
            return false
        }
    }
    
    // Combine multi-page PDF outputs
    void combinePdfOutputs(String baseName, String outputDir) {
        File outputFile = new File("${outputDir}/ocr_${baseName}.txt")
        File tempFile = File.createTempFile("combined_", ".txt")
        
        // Find all pages for this PDF
        List<File> pages = []
        new File(outputDir).eachFileMatch(FileType.FILES, ~/ocr_${baseName}_page\d+\.txt/) { file ->
            pages.add(file)
        }
        
        // Check if we found any pages
        if (pages.isEmpty()) {
            println "No pages found for ${baseName}"
            tempFile.delete()
            return
        }
        
        // Sort pages by page number
        pages.sort { a, b ->
            def pageNumA = (a.name =~ /page(\d+)/)[0][1].toInteger()
            def pageNumB = (b.name =~ /page(\d+)/)[0][1].toInteger()
            return pageNumA <=> pageNumB
        }
        
        // Add page markers and combine
        pages.each { page ->
            def pageNum = (page.name =~ /page(\d+)/)[0][1]
            tempFile.append("\n=== Page ${pageNum} ===\n\n")
            tempFile.append(page.text)
            page.delete()  // Remove individual page file
        }
        
        // Move combined file to final location
        tempFile.renameTo(outputFile)
        println "✓ Combined output saved to ${outputFile.name}"
    }
    
    // Get language description
    String getLangDescription(String langCode) {
        File file = new File(langFile)
        if (file.exists()) {
            def matcher = file.text =~ /\d+\. \*\*${langCode}\*\* - (.*)/
            if (matcher) {
                return matcher[0][1]
            }
        }
        return null
    }
    
    // Detect script and language
    boolean detectLanguage(String imagePath) {
        def process = ["tesseract", imagePath, "stdout", "--psm", "0"].execute()
        def output = new StringBuffer()
        def error = new StringBuffer()
        process.consumeProcessOutput(output, error)
        process.waitFor()
        
        if (process.exitValue() != 0) {
            return false
        }
        
        def matcher = output.toString() =~ /Script: (\w+)/
        
        if (matcher) {
            detectedScript = matcher[0][1]
            
            // Check if the script is available
            File scriptFile = new File("/opt/homebrew/share/tessdata/script/${detectedScript}.traineddata")
            if (scriptFile.exists()) {
                String desc = getLangDescription("script/${detectedScript}")
                if (desc) {
                    println "Detected script: ${detectedScript} (${desc})"
                } else {
                    println "Detected script: ${detectedScript}"
                }
                return true
            }
        }
        
        return false
    }
    
    // Show language help
    void showLangHelp() {
        String scriptName = "GraphPdfOcr.groovy"
        
        println """
OCR (Optical Character Recognition) Tool

Basic Usage:
    ${scriptName} <path>                   Process all images/PDFs in directory
    ${scriptName} <file>                   Process single file
    ${scriptName} <path> -l <lang>         Use specific language
    ${scriptName} <path> -s <script>       Use specific script

Examples:
    ${scriptName} /home/documents/scans    Process all files in directory
    ${scriptName} document.pdf             Process single PDF
    ${scriptName} scan.jpg -l fra         Process image in French
    ${scriptName} /scans -s Latin         Process using Latin script

Output:
    - Creates 'OCR_OUTPUTS' folder in the same directory as input
    - One text file per processed file
    - PDFs generate one combined file with page markers

Supported Formats:
    Images: jpg, jpeg, png, tiff, bmp, gif, webp
    Documents: pdf (processed page by page)
"""
        
        File file = new File(langFile)
        if (file.exists()) {
            println "Common languages (from installed languages):"
            println "  eng: English (default)"
            
            // Show non-script languages (first 8)
            def nonScriptLangs = []
            file.eachLine { line ->
                def matcher = line =~ /\d+\. \*\*([^*]+)\*\* - (.+)/
                if (matcher && !matcher[0][1].startsWith("script/")) {
                    nonScriptLangs.add("  ${matcher[0][1]}: ${matcher[0][2]}")
                    if (nonScriptLangs.size() == 8) {
                        return
                    }
                }
            }
            nonScriptLangs[0..Math.min(7, nonScriptLangs.size()-1)].each { println it }
            
            println "\nCommon scripts:"
            
            // Show scripts (first 4)
            def scripts = []
            file.eachLine { line ->
                def matcher = line =~ /\d+\. \*\*script\/([^*]+)\*\* - (.+)/
                if (matcher) {
                    scripts.add("  ${matcher[0][1]}: ${matcher[0][2]}")
                    if (scripts.size() == 4) {
                        return
                    }
                }
            }
            scripts[0..Math.min(3, scripts.size()-1)].each { println it }
        } else {
            println """
Common languages:
  eng: English (default)
  spa: Spanish
  fra: French
  deu: German
  por: Portuguese

Scripts:
  Latin    - Latin alphabet
  Cyrillic - Cyrillic alphabet
"""
        }
    }
    
    // Show full language list
    void showFullList() {
        File file = new File(langFile)
        if (file.exists()) {
            println file.text
        } else {
            println "Error: Language list file not found"
            System.exit(1)
        }
    }
    
    // Show help
    void showHelp() {
        String scriptName = "GraphPdfOcr.groovy"
        println """
Usage: ${scriptName} [options] <file1> [file2 ...]

Process images and PDFs with OCR (Optical Character Recognition)

Options:
    -l, --lang <lang>     Specify OCR language (default: eng)
    -s, --script <script> Use specific script (e.g., Latin, Cyrillic)
    --list               Show available language codes
    --full-list         Show detailed language and script information
    -h, --help          Show this help message

Supported file types:
    Images: jpg, jpeg, png, tiff, bmp, gif, webp
    Documents: pdf (will process each page separately)

Examples:
    ${scriptName} image.jpg                    # Process single image with default language
    ${scriptName} -l fra document.pdf          # Process PDF in French
    ${scriptName} --script Latin *.jpg         # Process all JPGs with Latin script
    ${scriptName} --list                       # Show available languages
"""
    }
    
    // Process files based on input path and options
    void processFiles(String targetPath, String language) {
        File target = new File(targetPath)
        
        if (!target.exists()) {
            println "Error: '${targetPath}' does not exist"
            System.exit(1)
        }
        
        List<String> supportedExtensions = ["pdf", "jpg", "jpeg", "png", "tiff", "bmp", "gif", "webp"]
        List<File> filesToProcess = []
        
        // Set up output directory
        if (target.isDirectory()) {
            ocrOutputs = "${targetPath}/OCR_OUTPUTS"
            
            // Collect all supported files in the directory
            target.eachFile(FileType.FILES) { file ->
                String ext = file.name.lastIndexOf('.').with { it != -1 ? file.name.substring(it + 1).toLowerCase() : "" }
                if (supportedExtensions.contains(ext)) {
                    filesToProcess.add(file)
                }
            }
        } else {
            // If target is a file, create OCR_OUTPUTS in its directory
            ocrOutputs = "${target.parent}/OCR_OUTPUTS"
            
            // Check file extension
            String ext = target.name.lastIndexOf('.').with { it != -1 ? target.name.substring(it + 1).toLowerCase() : "" }
            if (supportedExtensions.contains(ext)) {
                filesToProcess.add(target)
            } else {
                println "Error: Unsupported file type for '${target.name}'"
                println "Supported extensions: ${supportedExtensions.join(', ')}"
                System.exit(1)
            }
        }
        
        // Create output directory
        new File(ocrOutputs).mkdirs()
        
        // Check if any files were found
        if (filesToProcess.isEmpty()) {
            println "Error: No supported files found in '${targetPath}'"
            println "Supported formats: ${supportedExtensions.join(', ')}"
            System.exit(1)
        }
        
        // Process each file
        filesToProcess.each { file ->
            processFile(file.absolutePath, language, ocrOutputs)
        }
        
        println "Done! OCR outputs saved in ${ocrOutputs}/"
    }
}

//-------------------------
// Main script execution
//-------------------------
def cli = new CliBuilder(usage: 'GraphPdfOcr.groovy [options] <file1> [file2 ...]',
                         header: 'Process images and PDFs with OCR')
cli.h(longOpt: 'help', 'Show this help message')
cli.l(longOpt: 'lang', args: 1, argName: 'lang', 'Specify OCR language (default: eng)')
cli.s(longOpt: 'script', args: 1, argName: 'script', 'Use specific script (e.g., Latin, Cyrillic)')
cli.'list'(longOpt: 'list', 'Show available language codes')
cli.'full-list'(longOpt: 'full-list', 'Show detailed language and script information')

def options = cli.parse(args)
if (!options) {
    return
}

// Create OCR processor instance
def ocrProcessor = new GraphPdfOcr()

// Handle options
if (options.h) {
    ocrProcessor.showHelp()
    return
}

if (options.list) {
    ocrProcessor.showLangHelp()
    return
}

if (options.'full-list') {
    ocrProcessor.showFullList()
    return
}

// Handle no arguments
if (options.arguments().size() == 0) {
    ocrProcessor.showLangHelp()
    return
}

// Get language settings
String language = "eng"
if (options.l) {
    language = options.l
} else if (options.s) {
    language = "script/${options.s}"
}

// Get target path (file or directory)
String targetPath = options.arguments()[0]

// Process the files
ocrProcessor.processFiles(targetPath, language)
