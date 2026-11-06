#! /bin/zsh

# Find the 4x6" shipping label on a PDF page, crop to it, and print it
# Usage: crop_pdf_and_print_label.sh [-n] [-p printer] <path_to_pdf_file>
#   -n          dry run: crop and report, but do not print or open Preview
#   -p printer  CUPS printer name (default: DYMO_LabelWriter_4XL, or $LABEL_PRINTER)
#
# REQUIRES
#   brew install ghostscript
#   /usr/bin/python3 (comes with the Xcode Command Line Tools: xcode-select --install)
#
# HOW IT WORKS
#   The page is rasterized at low resolution and split into blocks along blank
#   gutters (rows and columns of white space). The outermost block whose size is
#   roughly 4x6" (either orientation) is taken to be the label, and the PDF is
#   cropped to that block, keeping it as vector/original quality. That means a
#   page with instructions or a receipt next to the label still crops correctly.
#   If no such block is found, the crop falls back to trimming the white space
#   from the whole page (the old behaviour) and the result opens in Preview.
#
# EXIT CODES
#   0  label found and printed (or dry run complete)
#   1  usage or file error
#   2  missing dependency
#   3  no 4x6" label found; cropped PDF opened in Preview for manual handling

# ----- SETUP -----
target_w_inches=4       # Target label width in inches
target_h_inches=6       # Target label height in inches
margin_of_error=0.10    # Allowed deviation from target size, as a fraction
printer="${LABEL_PRINTER:-DYMO_LabelWriter_4XL}"  # CUPS printer name (see: lpstat -p)
dry_run=false

# Add brew directories to PATH, since Mail/Automator give us a minimal PATH
PATH=$PATH:/usr/local/bin:/opt/local/bin:/opt/homebrew/bin

# ----- ARGUMENTS -----
while getopts "np:" opt; do
    case $opt in
        n) dry_run=true ;;
        p) printer=$OPTARG ;;
        *) echo "Usage: $0 [-n] [-p printer] <path_to_pdf_file>"; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 [-n] [-p printer] <path_to_pdf_file>"
    exit 1
fi

FILE="$1"
if [[ ! -f "$FILE" ]]; then
    echo "File $FILE does not exist."
    exit 1
fi

for dep in gs /usr/bin/python3; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        echo "Missing dependency: $dep"
        exit 2
    fi
done

# ----- PROCESSING -----
name=$( basename "$FILE" .pdf )  # name of file without path and without extension
dir=$( dirname "$FILE" )         # directory of file
cd "$dir" || exit 1
input="$name.pdf"
output="${name}_cropped.pdf"

# Find the label. Prints one line:  <status> <page> <x0> <y0> <x1> <y1> <rotate>
# where status is FOUND or FALLBACK, coordinates are PDF points with the origin
# at the bottom-left of the page, and rotate is 0 or 90.
result=$( /usr/bin/python3 - "$input" "$target_w_inches" "$target_h_inches" "$margin_of_error" <<'PY'
import subprocess, sys

pdf, target_w, target_h, tolerance = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])
DPI = 36                      # low resolution is plenty for finding gutters
GAP = max(2, round(0.12 * DPI))  # a gutter must be at least this wide (about 1/8")
INK = 200                     # gray levels below this count as ink (0 = black)
PAD = 2                       # points of breathing room around the crop


def gs(args):
    """Run Ghostscript and return its stdout; on failure, report its stderr."""
    proc = subprocess.run(["gs"] + args, capture_output=True)
    if proc.returncode != 0:
        # Ghostscript reports PostScript errors on stdout, so include both streams
        sys.stderr.write("Ghostscript failed (exit %d): gs %s\n%s\n%s\n"
                         % (proc.returncode, " ".join(args),
                            proc.stdout.decode(errors="replace").strip(),
                            proc.stderr.decode(errors="replace").strip()))
        sys.exit(1)
    return proc.stdout


def numbers(output, count):
    """Pull the numeric tokens out of Ghostscript output; anything else means it choked on the PDF."""
    found = []
    for tok in output.decode(errors="replace").split():
        try:
            found.append(float(tok))
        except ValueError:
            pass
    if len(found) < count:
        sys.stderr.write("Ghostscript could not read the PDF:\n%s\n" % output.decode(errors="replace").strip())
        sys.exit(1)
    return found[-count:]


def page_size(pdf, page):
    """Rendered page size in points (MediaBox, swapped if the page is rotated 90/270)."""
    ps = (f"({pdf}) (r) file runpdfbegin {page} pdfgetpage dup "
          "/MediaBox pget {aload pop /y1 exch def /x1 exch def /y0 exch def /x0 exch def "
          "x1 x0 sub = y1 y0 sub =} if "
          "/Rotate pget {=} {0 =} ifelse quit")
    out = numbers(gs(["-q", "-dNODISPLAY", "-dNOSAFER", "-c", ps]), 3)
    w, h, rot = out[0], out[1], int(out[2]) % 360
    return ((h, w) if rot in (90, 270) else (w, h)) + (rot,)


def page_count(pdf):
    ps = f"({pdf}) (r) file runpdfbegin pdfpagecount = quit"
    return int(numbers(gs(["-q", "-dNODISPLAY", "-dNOSAFER", "-c", ps]), 1)[0])


def render(pdf, page):
    """Rasterize one page to a list of rows of booleans (True = ink)."""
    data = gs(["-q", "-dNOPAUSE", "-dBATCH", "-dSAFER", "-sDEVICE=pgmraw", f"-r{DPI}",
               f"-dFirstPage={page}", f"-dLastPage={page}", "-sOutputFile=-", pdf])
    # Parse the binary PGM header: P5 <width> <height> <maxval>
    tokens, i = [], 0
    while len(tokens) < 4:
        while data[i:i + 1].isspace():
            i += 1
        if data[i:i + 1] == b"#":
            while data[i:i + 1] not in (b"\n", b""):
                i += 1
            continue
        j = i
        while not data[j:j + 1].isspace():
            j += 1
        tokens.append(data[i:j])
        i = j
    i += 1
    w, h = int(tokens[1]), int(tokens[2])
    px = data[i:i + w * h]
    return w, h, [[px[y * w + x] < INK for x in range(w)] for y in range(h)]


def ink_bbox(rows, x0, y0, x1, y1):
    xs = [x for y in range(y0, y1) for x in range(x0, x1) if rows[y][x]]
    if not xs:
        return None
    ys = [y for y in range(y0, y1) if any(rows[y][x0:x1])]
    return min(xs), min(ys), max(xs) + 1, max(ys) + 1


def gutters(blank):
    """Runs of blank lines at least GAP long, not touching the edges."""
    runs, start = [], None
    for i, v in enumerate(blank + [False]):
        if v and start is None:
            start = i
        if not v and start is not None:
            if i - start >= GAP and start > 0:
                runs.append((start, i))
            start = None
    return runs


def segment(rows, x0, y0, x1, y1, depth, out):
    """Recursive X-Y cut: split on blank rows, else blank columns; collect every block."""
    box = ink_bbox(rows, x0, y0, x1, y1)
    if not box:
        return
    x0, y0, x1, y1 = box
    out.append((depth, box))
    cuts = gutters([not any(rows[y][x0:x1]) for y in range(y0, y1)])
    vertical = False
    if not cuts:
        cuts = gutters([not any(rows[y][x] for y in range(y0, y1)) for x in range(x0, x1)])
        vertical = True
    if not cuts:
        return
    edges = [0] + [c for run in cuts for c in run] + [(x1 - x0) if vertical else (y1 - y0)]
    for a, b in zip(edges[0::2], edges[1::2]):
        if vertical:
            segment(rows, x0 + a, y0, x0 + b, y1, depth + 1, out)
        else:
            segment(rows, x0, y0 + a, x1, y0 + b, depth + 1, out)


def label_like(w_in, h_in):
    """Return 0 for an upright 4x6, 90 for a sideways one, None otherwise."""
    def near(v, t):
        return abs(v - t) <= t * tolerance
    if near(w_in, target_w) and near(h_in, target_h):
        return 0
    if near(w_in, target_h) and near(h_in, target_w):
        return 90
    return None


fallback = None
for page in range(1, page_count(pdf) + 1):
    w, h, rows = render(pdf, page)
    page_w, page_h, page_rot = page_size(pdf, page)
    sx, sy = page_w / w, page_h / h  # points per pixel
    blocks = []
    segment(rows, 0, 0, w, h, 0, blocks)
    if not blocks:
        continue
    candidates = []
    for depth, (bx0, by0, bx1, by1) in blocks:
        rotate = label_like((bx1 - bx0) / DPI, (by1 - by0) / DPI)
        if rotate is not None:
            area = (bx1 - bx0) * (by1 - by0)
            candidates.append((depth, -area, (bx0, by0, bx1, by1), rotate))
    if candidates:
        candidates.sort()  # outermost first, then largest
        _, _, (bx0, by0, bx1, by1), rotate = candidates[0]
        if rotate and page_rot in (90, 270):
            rotate = 360 - page_rot  # undo the page's own rotation so text stays upright
        found = "FOUND"
    elif fallback is None:
        _, (bx0, by0, bx1, by1) = blocks[0]  # whole-page ink box
        rotate = 0
        fallback = (page, bx0, by0, bx1, by1)
        continue
    else:
        continue
    # Convert pixel box (origin top-left) to PDF points (origin bottom-left)
    x0 = max(0.0, bx0 * sx - PAD)
    x1 = min(page_w, bx1 * sx + PAD)
    y0 = max(0.0, page_h - by1 * sy - PAD)
    y1 = min(page_h, page_h - by0 * sy + PAD)
    print(f"{found} {page} {x0:.2f} {y0:.2f} {x1:.2f} {y1:.2f} {rotate}")
    break
else:
    if fallback:
        page, bx0, by0, bx1, by1 = fallback
        page_w, page_h, _ = page_size(pdf, page)
        w, h, _ = render(pdf, page)
        sx, sy = page_w / w, page_h / h
        print(f"FALLBACK {page} {max(0.0, bx0 * sx - PAD):.2f} {max(0.0, page_h - by1 * sy - PAD):.2f} "
              f"{min(page_w, bx1 * sx + PAD):.2f} {min(page_h, page_h - by0 * sy + PAD):.2f} 0")
    else:
        print("EMPTY 1 0 0 0 0 0")
PY
)
if [[ $? -ne 0 || -z "$result" ]]; then
    echo "Could not analyze $input (in $PWD; gs=$(command -v gs); user=$(id -un); HOME=$HOME; TMPDIR=${TMPDIR:-unset})"
    ls -la "$input" 2>&1
    head -c 8 "$input" 2>&1 | od -c | head -1
    echo "parent: $(ps -o comm= -p $PPID 2>/dev/null) <- $(ps -o comm= -p $(ps -o ppid= -p $PPID 2>/dev/null) 2>/dev/null)"
    /usr/bin/python3 -c 'import ctypes,os; l=ctypes.CDLL("/usr/lib/system/libsystem_sandbox.dylib"); print("sandboxed:", bool(l.sandbox_check(os.getpid(), None, 0)))' 2>&1
    exit 1
fi
read -r found page x0 y0 x1 y1 rotate <<< "$result"
if [[ $found == "EMPTY" ]]; then
    echo "$input appears to be blank."
    exit 3
fi

# Crop with Ghostscript, keeping the original vector/image content:
# set the output page to the label's size and shift the content so the label
# sits at the origin. Rotate sideways labels so the printer gets a portrait page.
crop_w=$(( x1 - x0 ))
crop_h=$(( y1 - y0 ))
pdfmark=""
if [[ $rotate -ne 0 ]]; then
    pdfmark="[/Rotate $rotate /PAGES pdfmark"
fi
gs -q -dNOPAUSE -dBATCH -dSAFER -sDEVICE=pdfwrite -dAutoRotatePages=/None \
   -dFirstPage="$page" -dLastPage="$page" \
   -dFIXEDMEDIA -dDEVICEWIDTHPOINTS="$crop_w" -dDEVICEHEIGHTPOINTS="$crop_h" \
   -sOutputFile="$output" \
   -c "<</PageOffset [-$x0 -$y0]>> setpagedevice" \
   -c "$pdfmark" \
   -f "$input"
if [[ $? -ne 0 || ! -s "$output" ]]; then
    echo "Ghostscript failed to crop $input"
    exit 1
fi

printf "Crop: %.2f x %.2f\" from page %s%s\n" $(( crop_w / 72.0 )) $(( crop_h / 72.0 )) "$page" \
    "$( [[ $rotate -ne 0 ]] && echo " (rotated $rotate°)" )"

# ----- OUTPUT -----
if [[ $found == "FOUND" ]]; then
    if [[ $dry_run == true ]]; then
        echo "Dry run: would print $output to $printer."
    else
        echo "Label found;\n>>> printing to $printer."
        lpr -P "$printer" "$output"
    fi
else
    echo "$output\n"
    echo "No ${target_w_inches}x${target_h_inches}\" label found; cropped to the page content instead."
    if [[ $dry_run == true ]]; then
        echo "Dry run: would open in Preview."
    else
        echo "Please check size and print manually.\n\nOpening in Preview..."
        open -a Preview.app "$output"
    fi
    exit 3
fi
