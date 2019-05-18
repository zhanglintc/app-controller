#!/usr/bin/env perl

use 5.010;

use YAML;
use Cwd qw/abs_path/;
use File::Basename qw/dirname basename/;
use File::Spec::Functions qw/catfile/;

use Data::Dumper;

my $__abspath__ = abs_path __FILE__;
my $__dir__     = dirname $__abspath__;
my $__file__    = basename $__abspath__;

my $g_applist_yaml;

my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);

my $default_msg =<< "HEREDOC";
Try "apc help" for more options

Copyright 2019-@{[$year+1900]}, zhanglintc
HEREDOC

my $help_msg =<< "HEREDOC";
Usage:
  apc [command]

Commands:
  show  \tshow status of all your apps
  start \tstart all your apps
  stop  \tstop all your apps
  restart   \trestart all your apps
  list  \tshow "~/.app-controller/app-list.yml"
  add   \tadd an app to "~/.app-controller/app-list.yml"
  del   \tdel an app from "~/.app-controller/app-list.yml"
  help  \tshow this help
HEREDOC

my $unknown_msg =<< "HEREDOC";
apc: command unknown

@{[sub{chomp($_=$help_msg);$_}->()]}
HEREDOC

sub init {
    my $apc_home = catfile($ENV{"HOME"}, ".app-controller");

    if (-d $apc_home) {
        $g_applist_yaml = catfile($apc_home, "applist.yml");
    }
    else {
        $g_applist_yaml = catfile($__dir__, "applist.yml");
    }
}

sub load_yaml_config {
    open my $fr, "<", $g_applist_yaml;
    my @content = <$fr>;
    close $fr;

    my $app_list = YAML::Load join("", @content);
    return $app_list;
}

sub dump_yaml_config {
    my $app_list = shift;

    my $yml_string = YAML::Dump $app_list;
    open my $fw, ">", $g_applist_yaml;
    print $fw $yml_string;
    close $fw;
}

sub grep_app_name {
    my $name = shift;

    my @pids = `ps -ef | grep -v -w grep | grep $name | awk '{print \$2}'`;

    my @details;
    for my $pid (@pids) {
        chomp $pid;

        my $cwd = readlink "/proc/$pid/cwd";
        next unless defined $cwd;

        my $exe = readlink "/proc/$pid/exe";
        next unless defined $exe;

        my $cmdline = `cat /proc/$pid/cmdline`;
        my @cmdline_arr = split /\0/, $cmdline;
        my $app_name = $cmdline_arr[1];
        my $full_path = abs_path catfile($cwd, $app_name);

        my $port = `netstat -ntlp 2>/dev/null | grep ${pid} | awk '{print \$4}' | awk -F ':' '{print \$2}'`; chomp $port;
        $port = undef if not $port;

        my $detail = {
            pid => $pid,
            exe => $exe,
            cwd => $cwd,
            app => $app_name,
            port => $port,
            full_path => $full_path,
        };

        push @details, $detail;
    }

    return \@details;
}

sub active_or_down {
    my $expect_name = shift;
    my $name = shift;

    my $details = grep_app_name($name);

    return grep {$_->{full_path} eq $expect_name} @$details;
}

sub show_status {
    my $separator = "\t  ";

    say "Status:";
    say "-" x 30;
    say "Status${separator}Pid${separator}Port${separator}Applictaion";

    my $app_list = load_yaml_config();

    for (@$app_list) {
        my $dir = dirname $_;
        my $name = basename $_;

        my @items = active_or_down($_, $name);
        my $item = pop @items;

        my $status = $item ? 'Active' : 'Down';
        my $pid = $item->{pid} // "-";
        my $port = $item->{port} // "-";
        my $full_path = $item->{full_path} // $_;

        say "${status}${separator}${pid}${separator}${port}${separator}${full_path}";
    }

    say "-" x 30;
}

sub activate_all {
    say "Try to start all apps";

    my $app_list = load_yaml_config();

    for (@$app_list) {
        my $dir = dirname $_;
        my $name = basename $_;

        unless (active_or_down($_, $name)) {
            my $exec = "";
            $exec = "ruby" if grep {/\.rb/} $name;
            $exec = "python" if grep {/\.py/} $name;
            $exec = "perl" if grep {/\.pl/} $name;

            my $cmd = "cd $dir; $exec ./$name>/dev/null 2>&1 \&";

            say " - activate $_";
            system "$cmd";
        }
    }

    say "Start all apps done";
    say "";

    show_status();
}

sub stop_all {
    say "Try to stop all apps";

    my $app_list = load_yaml_config();

    for (@$app_list) {
        my $expect_name = $_;
        my $dir = dirname $_;
        my $name = basename $_;

        my $details = grep_app_name($name);
        my @matched_items = grep {$_->{full_path} eq $expect_name} @$details;

        for my $item (@matched_items) {
            my $pid = $item->{pid};
            `kill -9 $pid`;
        }
    }

    say "Stop all apps done";
    say "";

    show_status();
}

sub restart_all {
    say "Try to stop all apps";

    my $app_list = load_yaml_config();

    for (@$app_list) {
        my $expect_name = $_;
        my $dir = dirname $_;
        my $name = basename $_;

        my $details = grep_app_name($name);
        my @matched_items = grep {$_->{full_path} eq $expect_name} @$details;

        for my $item (@matched_items) {
            my $pid = $item->{pid};
            `kill -9 $pid`;

            unless (active_or_down($_, $name)) {
                my $exec = "";
                $exec = "ruby" if grep {/\.rb/} $name;
                $exec = "python" if grep {/\.py/} $name;
                $exec = "perl" if grep {/\.pl/} $name;

                my $cmd = "cd $dir; $exec ./$name>/dev/null 2>&1 \&";
                system "$cmd";
            }

            my $new_details = grep_app_name($name);
            my @new_matched_items = grep {$_->{full_path} eq $expect_name} @$new_details;
            for my $item (@new_matched_items) {
                my $new_pid = $item->{pid};
                say "- restart $_: $pid => $new_pid";
            }
        }
    }

    say "Restart all apps done";
    say "";

    show_status();
}

sub show_app_list {
    my $app_list = load_yaml_config();

    say "app-list.yml:";
    say "-" x 30;

    unless (@$app_list) {
        say "null";
    }

    for my $idx (0 .. $#{$app_list}) {
        say "$idx: ${$app_list}[$idx]";
    }

    say "-" x 30;
}

sub add_app {
    my $name = shift @ARGV;

    if (!defined $name) {
        say "Filename missing";
        say 'Please use "apc add [filename]"';
        exit;
    }

    my $app_list = load_yaml_config();
    my $full_path = abs_path $name;

    if (-d $full_path) {
        say qq/"$full_path" is a directory/;
        exit;
    }

    if (!-f $full_path) {
        say qq/"$full_path" is not an existing file/;
        exit;
    }

    if (grep {/$full_path/} @$app_list)
    {
        say qq/"$full_path" has already existed in app-list.yml\n/;
        show_app_list();
        exit;
    }

    push @$app_list, $full_path;
    dump_yaml_config($app_list);
    say "Add success, current list is:\n";
    show_app_list();
}

sub del_app {
    my $seq = shift @ARGV;

    if (!defined $seq or $seq =~ /[^\d]+/) {
        say "Parameter missing or not a number";
        say 'Please use "apc del [index]"';
        exit;
    }

    my $app_list = load_yaml_config();

    unless (@$app_list) {
        say "Delete cannot be done because app-list.yml is null\n";
        show_app_list();
        exit;
    }

    if ($seq > $#{$app_list}){
        say "Given index out of range. Available: 0 ~ $#{$app_list}\n";
        show_app_list();
        exit;
    }

    splice @$app_list, $seq, 1;
    dump_yaml_config($app_list);
    say "Delete success, current list is:\n";
    show_app_list();
}

sub main {
    init();

    my $command = shift @ARGV;

    if (!defined $command) {
        say $default_msg;
    }
    elsif ($command eq "show") {
        show_status();
    }
    elsif ($command eq "start") {
        activate_all();
    }
    elsif ($command eq "stop") {
        stop_all();
    }
    elsif ($command eq "restart") {
        restart_all();
    }
    elsif ($command eq "list") {
        show_app_list();
    }
    elsif ($command eq "add") {
        add_app();
    }
    elsif ($command eq "del") {
        del_app();
    }
    elsif ($command eq "help") {
        say $help_msg;
    }
    else {
        say $unknown_msg;
    }
}

main();

