#!/usr/bin/env wish

################################################################################
## File:         hermes.tcl
## Description:  Main file for the dear lover Hermes app
## Author:       Ruben Philipp
## Created:      2025-02-22
## $$ Last modified:  23:47:56 Sat Nov 15 2025 CET
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
    set location ""
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

# Location
grid [ttk::label .main.locationlabel -text "Location: "] -column 0 -row $row -sticky we
grid [ttk::entry .main.location -textvariable ::hermes::location] -column 1 -row $row -sticky we

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

################################################################################
## Creates a single HLS variant
## - $level:    The name of the level (e.g., "720p")
## - $width:    Target width (e.g., 1280)
## - $height:   Target height (e.g., 720)
## - $bitrate:  Target video bitrate (e.g., "2800k")
## - $maxrate:  Max video bitrate (e.g., "2996k")
## - $bufsize:  Buffer size (e.g., "4200k")
##
## Returns: The text line to be added to the master playlist
################################################################################
proc createHLSVariant {level width height bitrate maxrate bufsize} {
    # Get variables from the main process
    upvar ::hermes::vidfile vidfile
    upvar ::hermes::letterdir letterdir

    puts "Processing $level..."

    # 1. Create the subdirectory for this level
    set variantDir "$letterdir/stream/$level"
    file mkdir "$variantDir"

    # 2. Build the SIMPLE ffmpeg command
    set FFMPEG_CMD [list ffmpeg -i "$vidfile"]
    
    # Video settings
    lappend FFMPEG_CMD -c:v "libx264" -profile:v "main" -crf "20" -g "48" -keyint_min "48" -sc_threshold "0"
    lappend FFMPEG_CMD -vf "scale=w=${width}:h=${height}:force_original_aspect_ratio=decrease,pad=w=${width}:h=${height}:x=(ow-iw)/2:y=(oh-ih)/2"
    lappend FFMPEG_CMD -b:v "$bitrate" -maxrate "$maxrate" -bufsize "$bufsize"
    
    # Audio settings
    lappend FFMPEG_CMD -c:a "aac" -b:a "128k" -ar "48000"
    
    # HLS output settings
    lappend FFMPEG_CMD -f "hls" -hls_time "10" -hls_list_size "0"
    lappend FFMPEG_CMD -hls_segment_filename "$variantDir/segment%03d.ts"
    lappend FFMPEG_CMD -hls_playlist_type "vod"
    lappend FFMPEG_CMD "$variantDir/index.m3u8"
    
    # 3. Execute the command
    set convertRes [catch { exec {*}$FFMPEG_CMD >@ stdout 2>@1 } ffmpeg_output]
    
    if { $convertRes != 0 } {
        # This will be caught by the main process
        error "FFmpeg failed for $level:\n$ffmpeg_output"
    }

    # 4. Return the line for the master playlist
    set bandwidth [string map {"k" "000"} $bitrate]
    return "#EXT-X-STREAM-INF:BANDWIDTH=$bandwidth,RESOLUTION=${width}x${height}\n$level/index.m3u8"
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

    ####################
    ## Test if file
    ## size is >80MB
    ####################

    if { [file size "$::hermes::vidfile"] > 80000000 } {
        puts "Warning: The file is larger than 80MB."
        set doBigFile [ tk_messageBox \
                            -title "Proceed with big file?" \
                            -message "The video file is larger than 80MB. Do you want to proceed?" \
                            -type yesno \
                            -icon question ]
        if { $doBigFile eq "yes" } {
            puts "Proceeding with big file..."
        } else {
            puts "Transmission stopped."
            return 0;
        }
    }

    ####################
    
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
    set ::hermes::letterdir $letterdir ;# Share with helper proc
    puts "Created directory $letterdir"

    ####################
    ## Process Video (NEW HLS METHOD)
    ####################

    puts "Starting HLS conversion..."

    # 1. Show a "processing" window
    toplevel .convertWindow
    wm title .convertWindow "Converting Video..."
    grid [ttk::frame .convertWindow.main -padding "3 3 12 12"] -column 0 -row 0 -sticky nwes
    grid columnconfigure .convertWindow 0 -weight 1; grid rowconfigure . 0 -weight 1
    grid [ttk::progressbar .convertWindow.main.bar -mode indeterminate] -column 0 -row 1 -sticky we
    .convertWindow.main.bar start
    grid [ttk::label .convertWindow.main.infotext -text "Converting video to HLS, this will take a long time..."] -column 0 -row 2 -sticky we
    tkwait visibility .convertWindow.main.infotext

    # 2. Get source video dimensions with ffprobe
    if {[catch {exec ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of default=nw=1:nk=1 "$::hermes::vidfile"} GEO]} {
        puts "Error: ffprobe failed. Check if it's installed and in your PATH."
        tk_messageBox -message "Error: ffprobe failed. Could not get video dimensions. Aborting conversion." -icon "error"
        destroy .convertWindow
        return 0
    }
    set SOURCE_WIDTH [lindex $GEO 0]
    set SOURCE_HEIGHT [lindex $GEO 1]
    puts "Source video dimensions detected: $SOURCE_WIDTH x $SOURCE_HEIGHT"

    # 3. Create HLS output directory
    set HLS_OUTPUT_DIR "$letterdir/stream"
    file mkdir "$HLS_OUTPUT_DIR"
    
    set masterPlaylistLines [list]
    set errorOccurred 0
    set errorMsg ""
    
    # 4. Run the "smart" conversion, one command at a time
    # We use 'catch' to ensure the window is always closed
    if {[catch {
        # --- 1080p ---
        if { ($SOURCE_WIDTH > 1920) || ($SOURCE_HEIGHT > 1080) } {
            lappend masterPlaylistLines [createHLSVariant "1080p" 1920 1080 "5000k" "5350k" "7500k"]
        }
        # --- 720p ---
        if { ($SOURCE_WIDTH > 1280) || ($SOURCE_HEIGHT > 720) } {
            lappend masterPlaylistLines [createHLSVariant "720p" 1280 720 "2800k" "2996k" "4200k"]
        }
        # --- 480p ---
        if { ($SOURCE_WIDTH > 854) || ($SOURCE_HEIGHT > 480) } {
            lappend masterPlaylistLines [createHLSVariant "480p" 854 480 "1400k" "1498k" "2100k"]
        }
        # --- 360p (Baseline) ---
        # (Always add this *unless* the source is tiny and we already added others)
        if { [llength $masterPlaylistLines] == 0 || ($SOURCE_WIDTH > 640) || ($SOURCE_HEIGHT > 360) } {
             lappend masterPlaylistLines [createHLSVariant "360p" 640 360 "800k" "856k" "1200k"]
        }
        
    } errorMsg]} {
        set errorOccurred 1
    }
    
    # 5. Close processing window
    destroy .convertWindow
    
    # 6. Handle errors
    if { $errorOccurred } {
        puts "Error: FFmpeg conversion failed."
        puts "--- FFMPEG OUTPUT ---"
        puts $errorMsg
        puts "---------------------"
        tk_messageBox -message "ERROR! The FFmpeg conversion failed. Check the console for details. The letter was not processed." -icon "error"
        file delete -force "$letterdir"
        return 0
    }
    
    # 7. Write the Master Playlist file
    puts "Writing master playlist..."
    set f [open "$HLS_OUTPUT_DIR/master.m3u8" w]
    puts $f "#EXTM3U"
    puts $f "#EXT-X-VERSION:3"
    foreach line $masterPlaylistLines {
        puts $f $line
    }
    close $f
    
    puts "FFmpeg conversion successful."
    variable ::hermes::videofile_yaml "stream/master.m3u8"
    
    ## copy original files
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
    # puts $yamlfile "file: [file tail $::hermes::vidfile]"
    puts $yamlfile "file: $::hermes::videofile_yaml"
    
    if { "$hasPoster" == 1} {
        puts $yamlfile "poster: [file tail $::hermes::posterfile]"
    }
    ## add the location data to file if exists
    ## RP  Mon Mar 31 19:44:42 2025
    if { $::hermes::location != "" } {
        puts $yamlfile "location: $::hermes::location"
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

    puts "DEBUG: stop before upload"
    return 0; # stop before uploading TODO debug

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

        puts "UPLOADING via rsync. This might take a while..."

        ########################################
        ## UPLOAD...
        set rsyncRes [catch { exec rsync -Pav -e "ssh -i $::hermes::sshkey" "$::hermes::outdir$newUuid" "$::hermes::sshuser@$hermes::sshserver:$::hermes::uploaddir" >@ stdout }]
        if { $rsyncRes == 0 } {
            set deletep [tk_messageBox -message "UPLOAD SUCCEEDED! Should I delete the generated letter directory from this computer?" -icon "info" -type "yesno"]
            if { $deletep == "yes" } {
                # delete the letterdir
                file delete -force "$letterdir"
            }
            puts "DONE. The upload succeeded."
            tk_messageBox -message "Done. The letter has been uploaded to the server." -icon "info" -type "ok"
        } else {
            puts "ERROR. The upload did not succeed. You can still manually upload the letter from $letterdir."
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
