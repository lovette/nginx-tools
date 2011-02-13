# nginx-sites

Simple tool to manage nginx sites.


## Overview

A common way to manage nginx sites is to group configuration files that define
available servers in a directory, typically named `sites-available`.
Individual sites are then enabled by creating a symbolic link to the configuration
file from within a second directory, typically named `sites-enabled`.
The main nginx configuration file then has an `include sites-enabled/*` directive.
This tool provides a simple way to manage the links in the `sites-enabled`
directory.


## Features

* Sites can be grouped into directories underneath `sites-available`.
* Multiple sites can be enabled and disabled at once through patterns.


## Usage

	nginx-sites [--help|-h] [--version|-V]
	nginx-sites [OPTION]... list [--prefixroot] [group <group>]... [enabled|disabled]
	nginx-sites [OPTION]... status [<site>...]
	nginx-sites [OPTION]... enable <site>...
	nginx-sites [OPTION]... disable <site>...

Run the command with `--help` argument or see nginx-sites(1) for available OPTIONS.


## Commands

* `list` - List sites in format `[group/]site`.
* `status` - Show status of sites (enabled or disabled).
* `enable` - Enable sites that are disabled.
* `disable` - Disable sites that are enabled.


## Site selection

* `all` - Select all available sites.
* `site` - Select only ungrouped site `site`.
* `group` - Select all sites in group `group`. Use group name `-` to reference ungrouped sites.
* `group/site` - Select only site `site` in group `group`.
* `group/pattern` - Select all sites in group `group` whose name matches shell pattern `pattern`.


## Options

* `-c FILE` - Override default configuration file
* `-h`, `--help` - Show command line help and exit
* `-n` - Dry run; do not change configuration
* `-q` - Quiet; do not write anything to standard output; implies `-y`
* `-r` - Reload nginx if status changes are made
* `-R` - Restart nginx if status changes are made
* `-s` - Show simple status; do not show server names or ports
* `-t` - Test nginx configuration after status changes are made
* `-T` - Text only, no color
* `-v` - Increase verbosity (can specify more than once)
* `-V`, `--version` - Print version and exit
* `-y` - Answer yes for all questions


## Configuration file

Comment blocks in the main nginx configuration file are parsed for `nginx-sites-*` configuration options.
The default nginx configuration file path is `/etc/nginx/nginx.conf`. This path can be changed
using the -c command line option. `<confdir>` is the directory containing the nginx configuration file.

* `nginx-sites-available-dir` - Directory of available sites; defaults to `<confdir>/sites-available`
* `nginx-sites-enabled-dir` - Directory of enabled sites; defaults to `<confdir>/sites-enabled`


## Exit status

* 0 - Success; status command has other success status (see below).
* 1 - Command line argument error.
* 2 - General error.
* 3 - No such site or group.
* 4 - No sites are available or match selection.
* 5 - Nginx restart, reload, or config test failed.
* 10 - Selected sites are enabled; used only by status command.
* 11 - Selected sites are disabled; used only by status command.


## Command completion

If your shell supports BASH-style command word completion, the script
`bash_completion.sh` will enable completion to show sites and groups
applicable to each command.
