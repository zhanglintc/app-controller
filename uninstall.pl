#!/usr/bin/env perl

use 5.010;
use Cwd qw/abs_path/;

say 'remove folder "~/.app-controller"';
system "rm -rf $ENV{HOME}/.app-controller";
say "done\n";

say 'remove soft link "/usr/local/bin/apc"';
system "sudo rm /usr/local/bin/apc";
say "done\n";

