# nginx-minify-conf

Creates a minified version of a nginx configuration file by expanding includes
and optionally removing blank lines and comments.
The result is reformatted by default to improve readability.


## Why

Using liberal comments and modular include files in your nginx configuration are crucial.
But sometimes you just want to see the entire configuration all at once, be it for
review, or sharing, and sometimes it's just easier to digest a configuration if it's
more compact.


## Usage

	nginx-minify-conf [OPTION]... [CONFFILE]

Run the command with `--help` argument or see nginx-minify-conf(1) for available OPTIONS.


## Options

* `-1` - Expand includes
* `-2` - Expand includes, remove blank lines
* `-3` - Expand includes, remove blank lines and comments (default)
* `-h`, `--help` - Show command line help and exit
* `-i` - Demarcate begin and end of included files (if comments are preserved)
* `-I DEPTH` - Limit include file expansion to `DEPTH` (0=none; default is all)
* `-o FILE` - Write output to `FILE`
* `-u` - Do not reformat
* `-V`, `--version` - Print version and exit
