#!/usr/bin/env wish

################################################################################
## File:         hermes.tcl
## Description:  Main file for the dear lover Hermes app
## Author:       Ruben Philipp
## Created:      2025-02-22
## $$ Last modified:  23:11:59 Sun Feb 23 2025 CET
################################################################################

package require Tk

################################################################################

namespace eval hermes {
    ########################################
    # CONFIG VARS
    # set these via ~/.hermesrc.tcl
    ########################################
    variable from
    variable to
    variable datetime
    set vidfile ""
    set posterfile ""
    set outdir ""
    set comment ""
    # a shell program (via exec) to generate a uuid
    set uuidcmd "uuidgen"
    # default letter-yaml filename
    set letterfile "letter.yaml"
    ########################################
    # SFTP variables
    # if not set via ~/.hermesrc.tcl,
    # the letter will not be uploaded
    # automatically
    ########################################
    # path to the rsh-key file
    set sshkey ""
    # server url
    set sshserver ""
    # ssh username
    set sshuser ""
    # absolute path on the server to a
    # directory where the letter dir should
    # be uploaded to (no trailing slash)
    set uploaddir ""
}

# load config file
if { [file exists "$::env(HOME)/.hermesrc.tcl"] } {
    source "$::env(HOME)/.hermesrc.tcl"
} else {
    # set values to defaults
    set ::hermes::from = "greta"
    set ::hermes::to = "ruben"
}

################################################################################

# Main Window
wm title . "Hermes"
# the standard input width
set stdWidth 40
# set ::hermes::vidfile ""
# set ::hermes::posterfile ""
# set ::hermes::outdir ""


# grid
grid [ttk::frame .main -padding "3 3 12 12"] -column 0 -row 0 -sticky nwes
grid columnconfigure . 0 -weight 1; grid rowconfigure . 0 -weight 1

set row 1

# video
grid [ttk::label .main.vidlabel -text "Video: "] -column 0 -row $row -sticky we
grid [ttk::entry .main.vidfile -width "$stdWidth" -textvariable ::hermes::vidfile] -column 1 -columnspan 2 -row $row -sticky we
grid [ttk::button .main.vidselect -text "Select" -command {selectFile ::hermes::vidfile}] -column 3 -row $row -sticky we

incr row

# poster
grid [ttk::label .main.posterlabel -text "Poster Image (optional): "] -column 0 -row $row -sticky we
grid [ttk::entry .main.posterfile -width "$stdWidth" -textvariable ::hermes::posterfile] -column 1 -columnspan 2 -row $row -sticky we
grid [ttk::button .main.posterselect -text "Select" -command {selectFile ::hermes::posterfile {{"Images" {*.jpg *.jpeg *.png *.gif}} {"All files" {*}}}}] -column 3 -row $row -sticky we

incr row

# output directory
grid [ttk::label .main.outdirlabel -text "Output Directory: "] -column 0 -row $row -sticky we
grid [ttk::entry .main.outdir -width "$stdWidth" -textvariable ::hermes::outdir] -column 1 -columnspan 2 -row $row -sticky we
grid [ttk::button .main.outdirselect -text "Select" -command {selectDir ::hermes::outdir}] -column 3 -row $row -sticky we

incr row

# date
grid [ttk::label .main.datelabel -text "Date (YYYY-MM-DD HH-MM): "] -column 0 -row $row -sticky we
grid [ttk::entry .main.datetime -width "$stdWidth" -textvariable ::hermes::datetime] -column 1 -row $row -sticky we
grid [ttk::button .main.datetimenow -text "now" -command {set ::hermes::datetime [currentDate]; validateDateTimeWidget "$::hermes::datetime" .main.datetime}] -column 3 -row $row -sticky we

bind .main.datetime <FocusOut> {validateDateTimeWidget "$::hermes::datetime" .main.datetime}

incr row

# from/to
grid [ttk::label .main.fromlabel -text "From: "] -column 0 -row $row -sticky we
grid [ttk::entry .main.from -textvariable ::hermes::from] -column 1 -row $row -sticky we

incr row

grid [ttk::label .main.tolabel -text "To: "] -column 0 -row $row -sticky we
grid [ttk::entry .main.to -textvariable ::hermes::to] -column 1 -row $row -sticky we

incr row

# comment
grid [ttk::label .main.commentslabel -text "Comment (optional): "] -column 0 -row $row -sticky nwe
grid [text .main.comment -height 10 -width "$stdWidth" -wrap word] -column 1 -row $row -sticky we

incr row

grid [ttk::button .main.process -text "Done" -command {processLetter}] -column 1 -row $row -sticky we

incr row

# Also open selection dialog when clicking on entry
# bind .main.vidfile <ButtonPress-1> {selectFile "vidfile"}

################################################################################
################################################################################

# date functions

proc currentDate {} {
    return [clock format [clock seconds] -format "%Y-%m-%d %H:%M"]
}

proc validateDateTime {datetime} {
    if {[regexp {^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$} $datetime]} {
        return 1  ;# Valid format
    } else {
        return 0  ;# Invalid format
    }
}

proc validateDateTimeWidget {value widget} {
    if {[validateDateTime "$value"] == 1} {
        "$widget" configure -foreground black
        return 1
    } else {
        "$widget" configure -foreground red
        return 0
    }
}


## Select a file and write it to the variable 'textvar'
proc selectFile {textvar {types {{"Videos" {*.mp4 *.mov}} {"All files" {*}}}}} {
    set res [tk_getOpenFile -filetypes "$types"]
    set "::$textvar" "$res"
}

## Select a directory and write it to the variable 'textvar'
proc selectDir {textvar} {
    set res [tk_chooseDirectory]
    set "::$textvar" "$res"
}

## This is the main function.
proc processLetter {} {
    ## is data valid?
    set checkpass 1
    puts "Validating data..."
    ## check if all data is valid...
    if { [file exists "$::hermes::vidfile"] != 1 } {
        set checkpass 0
        puts "Error: The video file does not exist."
    }
    if { "$::hermes::posterfile" != "" && [ file exists "$::hermes::posterfile" ] != 1 } {
        set checkpass 0
        puts "Error: The poster image does not exist."
    }
    if { [validateDateTimeWidget "$::hermes::datetime" .main.datetime] != 1 } {
        set checkpass 0
        puts "Error: The date and time are not formatted properly or missing."
    }
    if { "$::hermes::from" == "" || "$::hermes::to" == "" } {
        set checkpass 0
        puts "Error: Sender and/or recipient are not set."
    }
    # test if outdir exists
    if { [file isdirectory "$::hermes::outdir"] != 1 } {
        set checkpass 0
        puts "Error: The output directory does not exist."
    }
    
    if { "$checkpass" == 0 } {
        tk_messageBox -message "It seems as if there's something wrong with your input. Please have a look at the data." -icon "error" -type "ok"
        # QUIT
        return 0;
    }
    puts "All good! Continuing..."

    ####################
    ## Continue...
    ####################

    # add a trailing slash to the outdir
    if { !( [string index "$::hermes::outdir" end] eq "/" ) } {
        set ::hermes::outdir "$::hermes::outdir/"
    }

    set newUuid [exec "$::hermes::uuidcmd"]
    set letterdir "$::hermes::outdir$newUuid/"
    file mkdir "$letterdir"
    puts "Created directory $letterdir" 
    ## copy files
    file copy "$::hermes::vidfile" "$letterdir[file tail $::hermes::vidfile]"
    puts "Copied video to $letterdir"
    ## copy poster if exists
    set hasPoster 0
    if { [ file exists "$::hermes::posterfile" ] } {
        file copy "$::hermes::posterfile" "$letterdir[file tail $::hermes::posterfile]"
        puts "Copied poster to $letterdir"
        set hasPoster 1
    }

    ####################
    ## now, create the
    ## YAML-file.
    ####################

    set yamlfile [open "$letterdir$::hermes::letterfile" w]
    puts $yamlfile "file: [file tail $::hermes::vidfile]"
    if { "$hasPoster" == 1} {
        puts $yamlfile "poster: [file tail $::hermes::posterfile]"
    }
    puts $yamlfile "date: $::hermes::datetime"
    puts $yamlfile "from: $::hermes::from"
    puts $yamlfile "to: $::hermes::to"
    set commentContent [.main.comment get 1.0 end]
    if { "$commentContent" != "" } {
        puts $yamlfile "comment: |"
        foreach line [split "$commentContent" "\n"] {
            puts $yamlfile "   $line"
        }
    }
    close $yamlfile
    puts "Created letter file $::hermes::letterfile"
    # puts "DONE."

    ########################################
    ## UPLOAD (if ssh data is given)
    ########################################

    if { $::hermes::sshkey != "" && $::hermes::sshserver != "" && $::hermes::sshuser != "" && $::hermes::uploaddir != "" } {
        ########################################
        ## create new window with waiting info
        ########################################
        toplevel .uploadWindow
        wm title .uploadWindow "Upload in progress..."
        grid [ttk::frame .uploadWindow.main -padding "3 3 12 12"] -column 0 -row 0 -sticky nwes
        grid columnconfigure .uploadWindow 0 -weight 1; grid rowconfigure . 0 -weight 1
        grid [ttk::progressbar .uploadWindow.main.bar -mode indeterminate] -column 0 -row 1 -sticky we
        .uploadWindow.main.bar start
        grid [ttk::label .uploadWindow.main.infotext -text "Wait for upload (this could take a while)..."] -column 0 -row 2 -sticky we

        # wait until window creation...
        tkwait visibility .uploadWindow.main.infotext
        

        ########################################
        ## UPLOAD...
        set rsyncRes [catch {exec rsync -Pav -e "ssh -i $::hermes::sshkey" "$::hermes::outdir$newUuid" "$::hermes::sshuser@$hermes::sshserver:$::hermes::uploaddir"}]
        if { $rsyncRes == 0 } {
            set deletep [tk_messageBox -message "UPLOAD SUCCEEDED! Should I delete the generated letter directory from this computer?" -icon "info" -type "yesno"]
            if { $deletep == "yes" } {
                # delete the letterdir
                file delete -force "$letterdir"
            }
            tk_messageBox -message "Done. The letter has been uploaded to the server." -icon "info" -type "ok"
        } else {
            tk_messageBox -message "ERROR! The upload did not succeed. You can still manually upload the letter from $letterdir." -icon "error" -type "ok"
        }
        # close upload progress window
        destroy .uploadWindow
        
    } else {
    
        tk_messageBox -message "Done. Now, upload the directory $letterdir to the server." -icon "info" -type "ok"
    }

    ########################################
    ## QUIT THE PROGRAM
    exit
}

################################################################################
################################################################################

# set date to current date
set ::hermes::datetime [currentDate]

################################################################################

vwait forever

################################################################################
## EOF hermes.tcl
