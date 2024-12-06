#!/usr/bin/env perl

use 5.010;

use FindBin qw/$RealBin/;
use lib $RealBin;

use YAML;
use Cwd qw/abs_path/;
use File::Basename qw/dirname basename/;
use File::Spec::Functions qw/catfile/;

use Data::Dumper;

my $__abspath__ = abs_path __FILE__;
my $__dir__     = dirname $__abspath__;
my $__file__    = basename $__abspath__;

my $g_applist_yaml;
my $g_wx_notify_yaml;

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
  log   \ttail one given log
  show  \tshow status of all your apps
  start \tstart all your apps
  stop  \tstop all your apps
  restart   \trestart all your apps
  list  \tshow "~/.app-controller/app-list.yml"
  edit  \tedit "~/.app-controller/app-list.yml"
  add   \tadd an app to "~/.app-controller/app-list.yml"
  del   \tdel an app from "~/.app-controller/app-list.yml"
  notify    \tsend msg to WX
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
        $g_wx_notify_yaml = catfile($apc_home, "wxnotify.yml");
    }
    else {
        $g_applist_yaml = catfile($__dir__, "applist.yml");
        $g_wx_notify_yaml = catfile($__dir__, "wxnotify.yml");
    }
}

sub _unique {
    my $raw_array = shift;

    my @uniq_array = ();
    my $seen = {};
    for $it (@$raw_array) {
        unless ($seen->{$it}) {
            $seen->{$it} = 1;
            push @uniq_array, $it;
        }
    }
    return wantarray ? @uniq_array : \@uniq_array;
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
    my $yaml_file = shift // $g_applist_yaml;

    open my $fr, "<", $yaml_file;
    my @content = <$fr>;
    close $fr;

    my $yaml_config = YAML::Load join("", @content);
    return $yaml_config;
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
    my $app_name = $cmdline_arr[1] ne "-jar" ? $cmdline_arr[1] : $cmdline_arr[2];
    my $full_path = (abs_path catfile($cwd, $app_name)) // $app_name;  # abs_path(XXX) can be undef

    # port: ipv4 => \$2, ipv6 => \$4
    my $netstat_port = `netstat -ntlp 2>/dev/null | grep ${pid} | awk '{print \$4}' | awk -F ':' '{print \$2 ? \$2 : \$4}'`; chomp $netstat_port;
    my @ports = split /\n/, $netstat_port;
    if (!@ports) {
        # if no ports for current process, search all sub processes
        my $children = `cat /proc/$pid/task/$pid/children`;
        my @child_pids = split / /, $children;
        foreach my $child_pid (@child_pids) {
            my $child_netstat_port = `netstat -ntlp 2>/dev/null | grep ${child_pid} | awk '{print \$4}' | awk -F ':' '{print \$2 ? \$2 : \$4}'`; chomp $child_netstat_port;
            my @child_ports = split /\n/, $child_netstat_port;
            push @ports, $_ foreach @child_ports;
        }
    }

    my $owner = `stat -c "%U" $full_path`; chomp $owner;

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
        owner => $owner,
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

sub tail_one_log {
    my $index = shift @ARGV;

    my $app_list = load_yaml_config();

    if ($index =~ /^[0-9]$/ and grep {/$index_str/} 0..$#{$app_list}) {
        my $apc_home = catfile($ENV{"HOME"}, ".app-controller");
        my $nohup_name = qq/@{[basename $$app_list[$idx]]}.nohup/;
        my $nohup_path = qq!$apc_home/nohups/$nohup_name!;
        say qq/Try to tail app No.$index nohup log: $$app_list[$idx]\n/;
        my $command = qq/tail @ARGV $nohup_path/;
        say $command; system $command;
    } else {
        say STDERR "Given index out of range. Available: 0 ~ $#{$app_list}\n";
        show_app_list();
        exit 1;
    }
}

sub show_status {
    my $separator = "\t";

    # Refer: https://blog.csdn.net/zhangpchina/article/details/131639515
    chomp(my $cpu_num = `grep -c processor /proc/cpuinfo`);
    chomp(my $cpu_usage = `top -b -n 1 | grep "Cpu(s)" | awk '{print \$2+\$4}'`);
    my $cpu_load_avg = $cpu_usage / $cpu_num;

    say "Status:";
    say qq!Mem used: @{[`free -m | sed -n '2p' | awk '{printf("%05.2f%%", \$3/\$2*100)}'`]}!;
    say qq!CPU used: @{[sprintf("%05.2f%%", $cpu_load_avg)]}!;
    say "-" x 30;
    say "No${separator}Status${separator}Pid${separator}Port${separator}Applictaion";

    my $app_list = load_yaml_config();

    my $idx = 0;
    for my $app (@$app_list) {
        my $dir = dirname $app;
        my $app_name = basename $app;

        my @items = active_or_down($app, $app_name);
        my $item = pop @items;

        my $status = $item ? 'Active' : 'Down';
        my $pid = $item->{pid} // "-";
        my $port = $item->{port} // "-";
        my $full_path = $item->{full_path} // $app;

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
    my $index_str = shift;
    my $quiet = shift;

    my $result_hash = {};

    my $app_list = load_yaml_config();

    $index_str = $index_str // shift @ARGV;
    if (defined $index_str) {
        if ($index_str =~ /^[0-9]$/ and grep {/$index_str/} 0..$#{$app_list}) {
            # apc start 5
            my $idx = $index_str;
            say "Try to start app No.$idx: $$app_list[$idx]" unless $quiet;
            $app_list = [$$app_list[$idx]];
        }
        elsif ($index_str =~ /^(\d)-(\d)$/ and sub {
            my @idxes = ($1 .. $2);
            for my $idx (@idxes) {
                return 0 unless (grep {/$idx/} 0..$#{$app_list});
            }
            return 1;
        }->()) {
            # apc start 0-5
            my $tmp_list = [];
            $index_str =~ /^(\d)-(\d)$/;
            my @idxes = ($1 .. $2);
            for my $idx (@idxes) {
                say "Try to start app No.$idx: $$app_list[$idx]" unless $quiet;
                push @$tmp_list, $$app_list[$idx]
            }
            $app_list = $tmp_list;
        }
        elsif ($index_str =~ /,/ and sub {
            my @idxes = split /,/, $index_str, -1;
            for my $idx (@idxes) {
                return 0 if $idx eq "";
                return 0 unless ($idx =~ /^[0-9]$/);
                return 0 unless (grep {/$idx/} 0..$#{$app_list});
            }
            return 1;
        }->()) {
            # apc start 0,1,2,3,4,5
            my $tmp_list = [];
            my @idxes = split /,/, $index_str, -1;
            @idxes = sort(_unique(\@idxes));
            for my $idx (@idxes) {
                say "Try to start app No.$idx: $$app_list[$idx]" unless $quiet;
                push @$tmp_list, $$app_list[$idx]
            }
            $app_list = $tmp_list;
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

    for my $app (@$app_list) {
        my $expect_name = $app;
        my $dir = dirname $app;
        my $app_name = basename $app;
        my $abs_path = catfile($dir, $app_name);

        unless (active_or_down($app, $app_name)) {
            my $exec = "";

            chomp(my $shebang = `head -n1 $abs_path 2>/dev/null`);
            if ($shebang =~ s/^#!//) {
                $exec = $shebang;
            }
            else {
                $exec = "bash" if grep {/\.sh/} $app_name;
                $exec = "ruby" if grep {/\.rb/} $app_name;
                $exec = "python" if grep {/\.py/} $app_name;
                $exec = "perl" if grep {/\.pl/} $app_name;
                $exec = "java -jar" if grep {/\.jar/} $app_name;
            }

            my $apc_home = catfile($ENV{"HOME"}, ".app-controller");
            my $output_device;
            if (-d $apc_home) {
                `mkdir -p $apc_home/nohups 2>/dev/null`;
                $output_device = "$apc_home/nohups/$app_name.nohup";
            }
            else {
                $output_device = "/dev/null";
            }

            my $start_cmd = "cd $dir 2>/dev/null; $exec ./$app_name >$output_device 2>&1 \&";

            say " - activate $app_name" unless $quiet;
            system "$start_cmd";

            my $details = grep_app_name($app_name);
            my @matched_items = grep {$_->{full_path} eq $expect_name} @$details;
            for my $item (@matched_items) {
                my $pid = $item->{pid};
                $result_hash->{$app_name} = $pid;
            }
        }
    }

    say "Start done" unless $quiet;
    say "" unless $quiet;

    show_status() unless $quiet;
    return $result_hash;
}

sub stop_all {
    my $index_str = shift;
    my $quiet = shift;

    my $result_list = [];

    my $app_list = load_yaml_config();

    my $index_str = $index_str // shift @ARGV;
    if (defined $index_str) {
        if ($index_str =~ /^[0-9]$/ and grep {/$index_str/} 0..$#{$app_list}) {
            # apc stop 5
            my $idx = $index_str;
            say "Try to stop app No.$idx: $$app_list[$idx]" unless $quiet;
            $app_list = [$$app_list[$idx]];
        }
        elsif ($index_str =~ /^(\d)-(\d)$/ and sub {
            my @idxes = ($1 .. $2);
            for my $idx (@idxes) {
                return 0 unless (grep {/$idx/} 0..$#{$app_list});
            }
            return 1;
        }->()) {
            # apc stop 0-5
            my $tmp_list = [];
            $index_str =~ /^(\d)-(\d)$/;
            my @idxes = ($1 .. $2);
            for my $idx (@idxes) {
                say "Try to stop app No.$idx: $$app_list[$idx]" unless $quiet;
                push @$tmp_list, $$app_list[$idx]
            }
            $app_list = $tmp_list;
        }
        elsif ($index_str =~ /,/ and sub {
            my @idxes = split /,/, $index_str, -1;
            for my $idx (@idxes) {
                return 0 if $idx eq "";
                return 0 unless ($idx =~ /^[0-9]$/);
                return 0 unless (grep {/$idx/} 0..$#{$app_list});
            }
            return 1;
        }->()) {
            # apc stop 0,1,2,3,4,5
            my $tmp_list = [];
            my @idxes = split /,/, $index_str, -1;
            @idxes = sort(_unique(\@idxes));
            for my $idx (@idxes) {
                say "Try to stop app No.$idx: $$app_list[$idx]" unless $quiet;
                push @$tmp_list, $$app_list[$idx]
            }
            $app_list = $tmp_list;
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

    for my $app (@$app_list) {
        my $expect_name = $app;
        my $dir = dirname $app;
        my $app_name = basename $app;

        my $details = grep_app_name($app_name);
        my @matched_items = grep {$_->{full_path} eq $expect_name} @$details;

        for my $item (@matched_items) {
            my $pid = $item->{pid};
            system "pkill -P $pid; kill -9 $pid";
            say " - stop $app_name" unless $quiet;
            push @$result_list, {
                app_name => $app_name,
                pid => $pid,
            };
        }
    }

    say "Stop done" unless $quiet;
    say "" unless $quiet;

    show_status() unless $quiet;
    return $result_list;
}

sub restart_all {
    my $app_list = load_yaml_config();

    my $index_str = shift @ARGV;
    if (defined $index_str) {
        if ($index_str =~ /^[0-9]$/ and grep {/$index_str/} 0..$#{$app_list}) {
            # apc restart 5
            my $idx = $index_str;
            say "Try to restart app No.$idx: $$app_list[$idx]" unless $quiet;
        }
        elsif ($index_str =~ /^(\d)-(\d)$/ and sub {
            my @idxes = ($1 .. $2);
            for my $idx (@idxes) {
                return 0 unless (grep {/$idx/} 0..$#{$app_list});
            }
            return 1;
        }->()) {
            # apc restart 0-5
            $index_str =~ /^(\d)-(\d)$/;
            my @idxes = ($1 .. $2);
            for my $idx (@idxes) {
                say "Try to restart app No.$idx: $$app_list[$idx]" unless $quiet;
            }
        }
        elsif ($index_str =~ /,/ and sub {
            my @idxes = split /,/, $index_str, -1;
            for my $idx (@idxes) {
                return 0 if $idx eq "";
                return 0 unless ($idx =~ /^[0-9]$/);
                return 0 unless (grep {/$idx/} 0..$#{$app_list});
            }
            return 1;
        }->()) {
            # apc restart 0,1,2,3,4,5
            my @idxes = split /,/, $index_str, -1;
            @idxes = sort(_unique(\@idxes));
            for my $idx (@idxes) {
                say "Try to restart app No.$idx: $$app_list[$idx]" unless $quiet;
            }
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

    my $stop_result = stop_all($index_str, 1);
    my $start_result = start_all($index_str, 1);

    foreach my $it (@$stop_result)
    {
        my $app_name = $it->{app_name};
        my $old_pid = $it->{pid};
        my $new_pid = $start_result->{$app_name};

        say " - restart $app_name: $old_pid => $new_pid";
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

sub wx_notify {
    my $text = shift @ARGV;
    chomp $text;

    if (!$text) {
        say "apc: argument missing, need a text string";
        return;
    }

    if (!-f $g_wx_notify_yaml) {
        say "apc: YAML file: '$g_wx_notify_yaml' not exist";
        return;
    }

    my $yaml_config = load_yaml_config($g_wx_notify_yaml);
    if (!$yaml_config->{username}) {
        say "apc: 'username' not in $g_wx_notify_yaml";
        return;
    }
    if (!$yaml_config->{password}) {
        say "apc: 'password' not in $g_wx_notify_yaml";
        return;
    }

    my $username = $yaml_config->{username} // "";
    my $password = $yaml_config->{password} // "";

    my $params = [
        "username=$username",
        "password=$password",
        "text=$text",
    ];
    @$params = map { qq/--data-urlencode "$_"/ } @$params;

    my $data_urlencode_str = join ' ', @$params;
    say "apc: " . `curl -s --get ${data_urlencode_str} wx.zhanglintc.co/send`;
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
    elsif ($command eq "log") {
        tail_one_log();
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
    elsif ($command eq "notify") {
        wx_notify();
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

