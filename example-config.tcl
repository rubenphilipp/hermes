## This is the config file for Hermes.
## It should be placed in the home directory, e.g. here:
## `~/.hermesrc.tcl

set ::hermes::from "ruben"
set ::hermes::to "greta"
set ::hermes::outdir "$::env(HOME)/Downloads/"
set ::hermes::uuidcmd "uuidgen"

## SSH settings (if not set, the upload will be skipped)
set ::hermes::sshkey "~/.ssh/id_rsa"
set ::hermes::sshserver "server.host.net"
set ::hermes::sshuser "sshuser"
set ::hermes::uploaddir "/home/sites/site100040628/web/dearlover/letters"
