#! /bin/zsh

# Script to crop whitespace from a PDF file, and print the resulting label
# Usage: ./crop_pdf_and_print_label.sh <path_to_pdf_file>
# REQUIRES
# brew install ps2eps ghostscript xpdf
# If the file is roughly 4x6", automatically prints to Dymo LabelWriter 4XL

# ----- SETUP -----
target_w_inches=4 # Target width in inches
target_h_inches=6 # Target height in inches
# echo "Target label dimensions: ${target_w_inches} x ${target_h_inches}\"\n..."
# Convert inches to points (1 inch = 72 points)
target_width=$((target_w_inches * 72)) # Target width in points (4 inches)
target_height=$((target_h_inches * 72)) # Target height in points (6 inches
# echo "Target dimensions: ${target_width}x${target_height} points" # DEBUG
margin_of_error=0.10 # Margin of error in decimal percentage

# Check if the correct number of arguments is provided
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <path_to_pdf_file>"
    exit 1
fi

# Check if the provided file exists

FILE="$1"
if [[ -f "$FILE" ]]; then
    # echo "$FILE exists."
else
    echo "File $FILE does not exist."
    exit 1
fi

# ----- PROCESSING -----

# Edit given file path
name=$( basename "$FILE" .pdf) # name of file without path and without extension
# echo "Name of file: $name" # DEBUG
dir=$( dirname "$FILE" ) # name of directory of file
cd "$dir" # Make it the working directory
# pwd # DEBUG

# Add brew directories to PATH variable, since ps2eps is a Pearl script which uses Ghostscript
# Just providing the complete path to ps2eps is not sufficient
PATH=$PATH:/usr/local/bin:/opt/local/bin:/opt/homebrew/bin
# echo "PATH: $PATH" # DEBUG

# Convert to Postscript format, taking care of whitespaces
eval pdf2ps "'$name'.pdf"

# Trim all whitespace for ps2eps
name_nowhitespace="$(echo -e "${name}" | tr -d '[:space:]')"
mv "$name".ps "$name_nowhitespace".ps

# Calculate and set bounding box, --loose expands the original tight bounding box by one point in each direction
ps2eps --loose -q "$name_nowhitespace".ps

# Convert back to PDF using Ghostscript, important option is "-dEPSCrop"
gs -q -dNOPAUSE -dBATCH -dDOINTERPOLATE -dUseFlateCompression=true -sDEVICE=pdfwrite -r1200 -dEPSCrop -sOutputFile="$name"_cropped.pdf -f "$name_nowhitespace".eps

# Remove temporary files
rm "$name_nowhitespace".ps
rm "$name_nowhitespace".eps

# Check if the cropped PDF is the right size
# uses pdfinfo from xpdf
pdf_width=$(pdfinfo "$name"_cropped.pdf | grep "Page size" | awk '{print $3}')
pdf_height=$(pdfinfo "$name"_cropped.pdf | grep "Page size" | awk '{print $5}')
# echo "..."
# echo "Cropped PDF dimensions: $pdf_width x $pdf_height points" # DEBUG
# echo "Target dimensions: ${target_width}x${target_height} points" # DEBUG
size_valid=true
min_width=$(($target_width * (1 - $margin_of_error)))
max_width=$(($target_width * (1 + $margin_of_error)))
min_height=$(($target_height * (1 - $margin_of_error)))
max_height=$(($target_height * (1 + $margin_of_error)))
if [[ $pdf_width -lt $min_width || $pdf_width -gt $max_width ]]; then
    # echo "Cropped PDF width ($pdf_width) is out of bounds ($min_width to $max_width)."
    size_valid=false
fi
if [[ $pdf_height -lt $min_height || $pdf_height -gt $max_height ]]; then
    # echo "Cropped PDF height ($pdf_height) is out of bounds ($min_height to $max_height)."
    size_valid=false
fi

# echo "..."
# Print cropped label to Dymo, if the size is valid
if [[ $size_valid == true ]]; then
    # Change the `lpr` command to match your printer name
    echo "Cropped PDF size is within margin;\n>>> printing to Dymo LabelWriter 4XL."
    lpr -P DYMO_LabelWriter_4XL "${name}_cropped.pdf"
else
    # echo "Target label dimensions: ${target_w_inches} x ${target_h_inches}\"\n..."
    echo "${name}_cropped.pdf\n"
    echo "Please check size and print manually.\n\nOpening in Preview..."
    # Open the cropped PDF in Preview for manual inspection
    open -a Preview.app "${name}_cropped.pdf"
    exit 3
fi