#!/usr/bin/env perl

use 5.010;
use Cwd qw/abs_path/;

say 'make folder "~/.app-controller"';
system "mkdir $ENV{HOME}/.app-controller";
say "done\n";

say 'make a soft link "/usr/local/bin/apc" to "app-controller.pl"';
system "sudo ln -s @{[abs_path '.']}/app-controller.pl /usr/local/bin/apc";
say "done\n";

