# Crop and Print 4×6" labels

These macOS-based scripts take an existing PDF with too much white space, and try to crop it to the smallest amount of space, checking that the result should be a roughly 4×6" shipping label. If the cropped label is the correct size, it will then automatically print it on a 4×6 label printer.

This works great for PDF labels from Poshmark, for which this was originally designed. It might also work well for other 4×6" shipping and return labels that you might get from various online stores. Let me know how it goes!

The script is not smart about the crop at all; just stripping out all of the white space around the label. If there is stuff other than the label in the PDF (text instructions, etc.), it will fail to crop properly, and instead of printing, it will open the attempted crop PDF in Preview.app for further manual intervention.

## Dependencies

You will need to install some command line tool dependencies with Homebrew:

```
brew install ps2eps ghostscript xpdf
```

Getting these installed properly is a bit of a pain in the ass, and I won't be covering that here.

## Shell script

I am printing to a Dymo LabelWriter 4XL. You will likely need to change line ~92 to use your correct printer name:

```shell
lpr -P DYMO_LabelWriter_4XL "${name}_cropped.pdf"
```

You can use the shell script on its own, like so:

```shell
./crop_pdf_and_print_label.sh <path_to_pdf_file>
```

I recommend making sure this works from the command line before installing the AppleScript. It only works with one file at a time.

## Mail AppleScript

The AppleScript `Crop and Print 4x6 PDF label attachment.scpt` assumes the shell script is installed in `~/Applications/`; otherwise you will need to change this line to reference where you put the script:

```AppleScript
do shell script "~/Applications/crop_pdf_and_print_label.sh " & thePath
```

Install this AppleScript in `~/Library/Scripts/Applications/Mail/` so that the script appears in the Script Menu when using the Mail app. (If you don't see the Script Menu in your menu bar, [check out these instructions](https://support.apple.com/guide/script-editor/access-scripts-using-the-script-menu-scpedt27975/mac).)

Select the Mail message(s) with PDF attachments that you wish to process, and select **Crop and Print 4x6 PDF label attachment** from the Script Menu. It runs the shell script in the background, and provides a nice interface for any errors.

## Finder Quick Action

The file `Crop and Print 4x6 PDF Label.workflow` should be installed in `~/Library/Services/`. I _think_ you can just double-click it to open it with Automator Installer and install it, but don't quote me on that.

This does basically same thing, but looping through a selection in the Finder, that you right-click on, and choose **Quick Actions > 🖨️ Crop and Print 4x6 PDF Label** from the context menu. This menu selection will only appear if you have only PDF(s) selected.

The trick with this is, it will fail with a permissions error unless you grant Full Disk Access to the Finder, which… on its face seems dumb. Finder is the thing you access all of the disks with! But that is how modern macOS security permissions work. 🤷 To do this:

1. Open ** > System Settings…**
2. Go to **Privacy & Security > Full Disk Access** and click **+**
3. Select `/System/Library/CoreServices/Finder.app`
4. After adding it, select **Quit Now** and wait for Finder to restart
5. The Quick Action should now work

As in the Shell Script section above, you may need to edit the embedded shell script in this Quick Action in Automator, if you need to change anything for your system, like the name of your printer.
