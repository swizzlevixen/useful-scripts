# Crop and Print 4×6" labels

These macOS-based scripts take a PDF that has a 4×6" shipping label somewhere on the page, find the label, crop the PDF down to just the label, and print it on a 4×6 label printer.

This works great for PDF labels from Poshmark, for which this was originally designed, and for USPS return labels that come with instructions and a receipt stub on the same page. It should work for most 4×6" shipping and return labels you get from online stores. Let me know how it goes!

## How the crop works

The page is rasterized at a low resolution and split into blocks along blank gutters (runs of white rows and columns), recursively. The outermost block that measures roughly 4×6" (in either orientation, within 10%) is taken to be the label, and the PDF is cropped to that block using Ghostscript, so the label keeps its original vector/image quality. Sideways labels are rotated so the printer gets a portrait page. Multi-page PDFs are scanned page by page and the first page with a label wins.

If no 4×6" block is found, the script falls back to trimming the white space from the whole page and, instead of printing, opens that result in Preview.app for you to deal with by hand.

## Dependencies

Ghostscript, from Homebrew:

```
brew install ghostscript
```

The label detection is a small Python program embedded in the shell script. It uses only the standard library and runs with Apple's `/usr/bin/python3`, which is installed with the Xcode Command Line Tools (`xcode-select --install`).

## Shell script

I am printing to a Dymo LabelWriter 4XL. If your printer has a different name (see `lpstat -p`), change the `printer=` line near the top of the script, or set the `LABEL_PRINTER` environment variable.

Usage:

```shell
./crop_pdf_and_print_label.sh [-n] [-p printer] <path_to_pdf_file>
```

- `-n` is a dry run: crop and report, but do not print or open Preview. Handy for testing.
- `-p printer` prints to a different CUPS printer.

The cropped PDF is written next to the original as `<name>_cropped.pdf`. Exit codes: 0 printed, 1 usage/file error, 2 missing dependency, 3 no label found (opened in Preview).

I recommend making sure this works from the command line (try `-n` first) before installing the AppleScript. It only works with one file at a time.

## Mail AppleScript

The AppleScript `Crop and Print 4x6 PDF label attachment.scpt` (source in the `.applescript` file alongside it) assumes the shell script is installed in `~/Applications/`; otherwise change the `shellScript` property at the top:

```AppleScript
property shellScript : "~/Applications/crop_pdf_and_print_label.sh"
```

The same compiled script works two ways.

### From the Script Menu

Install it in `~/Library/Scripts/Applications/Mail/` so that it appears in the Script Menu when using the Mail app. (If you don't see the Script Menu in your menu bar, [check out these instructions](https://support.apple.com/guide/script-editor/access-scripts-using-the-script-menu-scpedt27975/mac).)

Select the Mail message(s) with PDF attachments that you wish to process, and select **Crop and Print 4x6 PDF label attachment** from the Script Menu. It runs the shell script in the background and shows a summary dialog when done.

### As a Mail rule action

Also install it in `~/Library/Application Scripts/com.apple.mail/`. Then in **Mail > Settings > Rules**, make a rule with whatever conditions identify the label emails (for example, *From contains* the sender's address) and the action **Run AppleScript**, choosing this script.

Notes from setting this up:

- A rule script must have an `on perform mail action with messages … for rule …` handler; that is what Mail calls. This script has one (and an `on run` handler for the Script Menu), so one file serves both.
- Mail reports results from the rule with notifications rather than dialogs, so a stuck dialog can't block Mail. Messages with no PDF attachment are ignored silently, so the rule's conditions don't need to be precise about the subject.
- Rules only run on messages as they arrive in the Inbox on this Mac while Mail is running. **Message > Apply Rules** is not a reliable way to test a script rule: on my Mac it reports "criterion not satisfied" for conditions that plainly match (you can watch this with `log stream --predicate 'subsystem == "com.apple.email" AND category == "MFMessageRouter"'`).
- Mail runs rule scripts with the real home folder, so `~` in the shell script path works.
- Attachments are saved to `~/Library/Application Support/Mail/Crop and Print 4x6 Label/` (the cropped PDF lands next to each one). Mail's temporary folder is inside its sandbox container, and when a rule runs, the shell script and Ghostscript get "Operation not permitted" reading there. Mail's sandbox is allowed to write under `~/Library/Application Support/Mail/`, and every other process can read it.
- In rule mode, each run is logged to `~/Library/Logs/Crop and Print 4x6 Label.log`, including the full error text when something fails, since a notification only shows one line.

## Finder Quick Action

The file `Crop and Print 4x6 PDF Label.workflow` (zipped here) should be installed in `~/Library/Services/`. I _think_ you can just double-click it to open it with Automator Installer and install it, but don't quote me on that.

It loops over the PDFs selected in the Finder, when you right-click them and choose **Quick Actions > 🖨️ Crop and Print 4x6 PDF Label** from the context menu. This menu selection will only appear if you have only PDF(s) selected. The Quick Action calls the installed shell script in `~/Applications/`, so there is only one copy of the logic to maintain; it shows a notification per printed label and a dialog if something needs attention.

The trick with this is, it will fail with a permissions error unless you grant Full Disk Access to the Finder, which… on its face seems dumb. Finder is the thing you access all of the disks with! But that is how modern macOS security permissions work. 🤷 To do this:

1. Open ** > System Settings…**
2. Go to **Privacy & Security > Full Disk Access** and click **+**
3. Select `/System/Library/CoreServices/Finder.app`
4. After adding it, select **Quit Now** and wait for Finder to restart
5. The Quick Action should now work
