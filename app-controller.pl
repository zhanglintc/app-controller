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
Please use: apc [command]
Try "apc help" for more options

Copyright 2019-@{[$year+1900]}, zhanglintc
HEREDOC

my $help_msg =<< "HEREDOC";
Usage:
  apc [command]

Commands:
  view  \tview detail of one given pid
  show  \tshow status of all your apps
  start \tstart all your apps
  stop  \tstop all your apps
  restart   \trestart all your apps
  list  \tshow "~/.app-controller/app-list.yml"
  edit  \tedit "~/.app-controller/app-list.yml"
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

sub data_dump {
    my $data = shift;
    local $Data::Dumper::Indent = 2;
    local $Data::Dumper::Terse = 1;
    local $Data::Dumper::Useqq = 1;
    local $Data::Dumper::Pair = ': ';
    local $Data::Dumper::Trailingcomma = 1;
    local $Data::Dumper::Sortkeys = 1;
    return Dumper $data;
}

sub data_stringify {
    my $data = shift;
    local $Data::Dumper::Indent = 0;
    local $Data::Dumper::Terse = 1;
    local $Data::Dumper::Useqq = 1;
    local $Data::Dumper::Pair = ': ';
    return Dumper $data;
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

sub obtain_detail_of_pid {
    my $pid = shift;

    chomp $pid;

    my $cwd = readlink "/proc/$pid/cwd";
    return undef unless defined $cwd;

    my $exe = readlink "/proc/$pid/exe";
    return undef unless defined $exe;

    my $cmdline = `cat /proc/$pid/cmdline`;
    my @cmdline_arr = split /\0/, $cmdline;
    my $app_name = $cmdline_arr[1];
    my $full_path = abs_path catfile($cwd, $app_name);

    my $netstat_port = `netstat -ntlp 2>/dev/null | grep ${pid} | awk '{print \$4}' | awk -F ':' '{print \$2}'`; chomp $netstat_port;
    my @ports = split /\n/, $netstat_port;

    my $detail = {
        pid => $pid,
        exe => $exe,
        cwd => $cwd,
        app => $app_name,
        port => sub{
            $_ = data_stringify(\@ports);
            s/[\[\]]//g;  # remove left`[` and right `]`
            $_ || undef;
        }->(),
        full_path => $full_path,
    };

    return $detail;
}

sub grep_app_name {
    my $name = shift;

    my @pids = `ps -ef | grep -v -w grep | grep $name | awk '{print \$2}'`;

    my @details;
    for my $pid (@pids) {
        my $detail = obtain_detail_of_pid($pid);
        next unless $detail;
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

sub view_one_pid {
    my $pid = shift @ARGV;

    if (!defined $pid) {
        say STDERR "PID missing";
        say STDERR 'Please use "apc view [PID]"';
        exit 1;
    }

    my $detail = obtain_detail_of_pid($pid);

    if ($detail) {
        say "Detail of PID '$pid':";
        say data_dump($detail);
    } else {
        say "No result for PID '$pid'";
        say "PID '$pid' is not exist or try to use `sudo apc view $pid`";
    }
}

sub show_status {
    my $separator = "\t";

    say "Status:";
    say "-" x 30;
    say "No${separator}Status${separator}Pid${separator}Port${separator}Applictaion";

    my $app_list = load_yaml_config();

    my $idx = 0;
    for (@$app_list) {
        my $dir = dirname $_;
        my $name = basename $_;

        my @items = active_or_down($_, $name);
        my $item = pop @items;

        my $status = $item ? 'Active' : 'Down';
        my $pid = $item->{pid} // "-";
        my $port = $item->{port} // "-";
        my $full_path = $item->{full_path} // $_;

        say "@{[$idx++]}${separator}${status}${separator}${pid}${separator}${port}${separator}${full_path}";
    }

    say "-" x 30;
}
sub edit_app_list {
    chomp (my $vim_code = `type vim > /dev/null 2>&1; echo \$?`);
    chomp (my $vi_code = `type vi > /dev/null 2>&1; echo \$?`);
    chomp (my $nano_code = `type nano > /dev/null 2>&1; echo \$?`);

    if ($vim_code eq 0) {
        system "vim $g_applist_yaml";
        exit 0;
    }
    elsif ($vi_code eq 0) {
        system "vi $g_applist_yaml";
        exit 0;
    }
    elsif ($nano_code eq 0) {
        system "nano $g_applist_yaml";
        exit 0;
    }
    else {
        say STDERR "No appropertie editor(vim/vi/nano) exist";
        exit 1;
    }
}

sub start_all {
    my $idx = shift;
    my $quiet = shift;

    my $result_hash = {};

    my $app_list = load_yaml_config();

    $idx = $idx // shift @ARGV;
    if (defined $idx) {
        if ($idx =~ /^[0-9]$/ and grep {/$idx/} 0..$#{$app_list}) {
            say "Try to start app No.$idx: $$app_list[$idx]" unless $quiet;
            $app_list = [$$app_list[$idx]];
        }
        else {
            say STDERR "Given index out of range. Available: 0 ~ $#{$app_list}\n" unless $quiet;
            show_app_list();
            exit 1;
        }
    }
    else {
        say "Try to start all apps" unless $quiet;
    }

    for (@$app_list) {
        my $expect_name = $_;
        my $dir = dirname $_;
        my $name = basename $_;
        my $abs_path = catfile($dir, $name);

        unless (active_or_down($_, $name)) {
            my $exec = "";

            chomp(my $shebang = `head -n1 $abs_path`);
            if ($shebang =~ s/^#!//) {
                $exec = $shebang;
            }
            else {
                $exec = "ruby" if grep {/\.rb/} $name;
                $exec = "python" if grep {/\.py/} $name;
                $exec = "perl" if grep {/\.pl/} $name;
            }

            my $cmd = "cd $dir; $exec ./$name>/dev/null 2>&1 \&";

            say " - activate $_" unless $quiet;
            system "$cmd";

            my $details = grep_app_name($name);
            my @matched_items = grep {$_->{full_path} eq $expect_name} @$details;
            for my $item (@matched_items) {
                my $pid = $item->{pid};
                $result_hash->{$_} = $pid;
            }
        }
    }

    say "Start done" unless $quiet;
    say "" unless $quiet;

    show_status() unless $quiet;
    return $result_hash;
}

sub stop_all {
    my $idx = shift;
    my $quiet = shift;

    my $result_hash = {};

    my $app_list = load_yaml_config();

    my $idx = $idx // shift @ARGV;
    if (defined $idx) {
        if ($idx =~ /^[0-9]$/ and grep {/$idx/} 0..$#{$app_list}) {
            say "Try to stop app No.$idx: $$app_list[$idx]" unless $quiet;
            $app_list = [$$app_list[$idx]];
        }
        else {
            say STDERR "Given index out of range. Available: 0 ~ $#{$app_list}\n";
            show_app_list();
            exit 1;
        }
    }
    else {
        say "Try to stop all apps" unless $quiet;
    }

    for (@$app_list) {
        my $expect_name = $_;
        my $dir = dirname $_;
        my $name = basename $_;

        my $details = grep_app_name($name);
        my @matched_items = grep {$_->{full_path} eq $expect_name} @$details;

        for my $item (@matched_items) {
            my $pid = $item->{pid};
            system "kill -9 $pid";
            say " - stop $_" unless $quiet;
            $result_hash->{$_} = $pid;
        }
    }

    say "Stop done" unless $quiet;
    say "" unless $quiet;

    show_status() unless $quiet;
    return $result_hash;
}

sub restart_all {
    my $app_list = load_yaml_config();

    my $idx = shift @ARGV;
    if (defined $idx) {
        if ($idx =~ /^[0-9]$/ and grep {/$idx/} 0..$#{$app_list}) {
            say "Try to restart app No.$idx: $$app_list[$idx]" unless $quiet;
            $app_list = [$$app_list[$idx]];
        }
        else {
            say STDERR "Given index out of range. Available: 0 ~ $#{$app_list}\n";
            show_app_list();
            exit 1;
        }
    }
    else {
        say "Try to restart all apps";
    }

    my $stop_result = stop_all($idx, 1);
    my $start_result = start_all($idx, 1);

    foreach (keys %$stop_result)
    {
        my $old_pid = $stop_result->{$_};
        my $new_pid = $start_result->{$_};

        say " - restart $_: $old_pid => $new_pid";
    }

    say "Restart done";
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
        say STDERR "Filename missing";
        say STDERR 'Please use "apc add [filename]"';
        exit 1;
    }

    my $app_list = load_yaml_config();
    my $full_path = abs_path $name;

    if (-d $full_path) {
        say STDERR qq/"$full_path" is a directory/;
        exit 1;
    }

    if (!-f $full_path) {
        say STDERR qq/"$full_path" is not an existing file/;
        exit 1;
    }

    if (grep {/$full_path/} @$app_list)
    {
        say STDERR qq/"$full_path" has already existed in app-list.yml\n/;
        show_app_list();
        exit 1;
    }

    push @$app_list, $full_path;
    dump_yaml_config($app_list);
    say "Add success, current list is:\n";
    show_app_list();
}

sub del_app {
    my $seq = shift @ARGV;

    if (!defined $seq or $seq =~ /[^\d]+/) {
        say STDERR "Parameter missing or not a number";
        say STDERR 'Please use "apc del [index]"';
        exit 1;
    }

    my $app_list = load_yaml_config();

    unless (@$app_list) {
        say STDERR "Delete cannot be done because app-list.yml is null\n";
        show_app_list();
        exit 1;
    }

    if ($seq > $#{$app_list}){
        say STDERR "Given index out of range. Available: 0 ~ $#{$app_list}\n";
        show_app_list();
        exit 1;
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
        say STDERR $default_msg;
        exit 1;
    }
    elsif ($command eq "view") {
        view_one_pid();
    }
    elsif ($command eq "show") {
        show_status();
    }
    elsif ($command eq "start") {
        start_all();
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
    elsif ($command eq "edit") {
        edit_app_list();
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
        say STDERR $unknown_msg;
        exit 1;
    }
}

main();

