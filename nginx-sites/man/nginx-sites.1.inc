[COMMANDS]
.TP
\fBlist\fR
List sites in format [\fIgroup\fR/]\fIsite\fR. Ungrouped sites can be
shown with group name '-' if \fB--prefixroot\fR is specified.
.TP
\fBstatus\fR
Show status of sites (enabled or disabled).
.TP
\fBenable\fR
Enable sites that are disabled.
.TP
\fBdisable\fR
Disable sites that are enabled.

[SITE SELECTION]
.TP
\fIall\fR
Select all available sites.
.TP
\fIsite\fR
Select only ungrouped site \fIsite\fR.
.TP
\fIgroup\fR or group \fIgroup\fR
Select all sites in group \fIgroup\fR.
Use group name '-' to reference ungrouped sites.
.TP
\fIgroup\fR/\fIsite\fR
Select only site \fIsite\fR in group \fIgroup\fR.
.TP
\fIgroup\fR/\fIpattern\fR
Select all sites in group \fIgroup\fR whose name matches shell pattern \fIpattern\fR.

[BACKGROUND]
This tool assumes that the nginx configuration files that define available servers
are kept together in a directory, typically named \fBsites-available\fR.
Individual sites are then enabled by creating a symbolic link to the configuration
file from within a second directory, typically named \fBsites-enabled\fR.
The main nginx configuration file then has an \fBinclude sites-enabled/*\fR directive.
This tool provides a simple way to manage the links in the \fBsites-enabled\fR
directory. Available sites can be grouped together by placing their configuration
files within a subdirectory of \fBsites-available\fR. Sites can be managed
individually, by group or using a shell pattern.

[CONFIGURATION DIRECTIVES]
Comment blocks in the main nginx configuration file are parsed for
\fInginx-sites-*\fR configuration options.
The default nginx configuration file path is /etc/nginx/nginx.conf.
This path can be changed using the \fB\-c\fR command line option.
<confdir> is the directory containing the nginx configuration file.
.TP
\fBnginx-sites-available-dir\fR
Directory of available sites;
defaults to <confdir>/sites-available
.TP
\fBnginx-sites-enabled-dir\fR
Directory of enabled sites;
defaults to <confdir>/sites-enabled

[EXIT STATUS]
.TP
\fB0\fR
Success; \fBstatus\fR command has other success status (see below).
.TP
\fB1\fR
Command line argument error.
.TP
\fB2\fR
General error.
.TP
\fB3\fR
No such site or group.
.TP
\fB4\fR
No sites are available or match selection.
.TP
\fB5\fR
Nginx restart, reload, or config test failed.
.TP
\fB10\fR
Selected sites are \fBenabled\fR; used only by \fBstatus\fR command.
.TP
\fB11\fR
Selected sites are \fBdisabled\fR; used only by \fBstatus\fR command.
