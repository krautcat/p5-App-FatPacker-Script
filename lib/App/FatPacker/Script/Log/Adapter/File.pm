package App::FatPacker::Script::Log::Adapter::File;
# ABSTRACT: File adapter for logging to files for Log::Any
use strict;
use warnings;
use 5.008001;

use Log::Any::Adapter::Util ();
use base qw/Log::Any::Adapter::Base/;

use Carp ();

use IO::File ();

sub new {
    my ($class, $file, @args) = @_;

    # Defaultize arguments
    my $log_level = (exists $args{log_level})
        ? $args{log_level}
        : 'warning';
    my $binmode = (exists $args{binmode})
        ? $args{binmode}
        : 'utf8';
    
    return $class->SUPER::new(
        file => $file,
        log_level => $log_level,
        binmode => $binmode,
        @args);
}

sub init {
    my $self = shift;

    my %open_modes_aliases = ();
    my %open_modes = ();
    foreach my $m (['<', 'r'], ['>', 'w', 'write'], ['>>', 'a', 'append'],
        ['+<', 'r+'], ['+>', 'w+'], ['+>>', 'a+']) {
        $open_modes{$m->[0]} = 1;
        @open_modes_aliases{@$m[1 .. $#m]} = ($m->[0]) x (scalar(@$m) - 1);
    }

    my %bin_modes = ();
    foreach my $l ('unix', 'stdio', 'crlf', 'perlio', 'utf8', 'bytes', 'raw') {
        @bin_modes{$l, ":$l"} = (1, 1);
    }

    my $log_level = Log::Any::Adapter::Util::numeric_level($self->{log_level});
    if (not defined $log_level) {
        Carp::carp( sprintf ('Invalid log level "%s".' .
                'Rollback to default "%s" level',
                $self->{log_level}, 'warning');
        $log_level = Log::Any::Adapter::Util::numeric_level('warning');
    }
    
    my $mode = exists $self->{mode} and $self->{mode} ne '' ? $self->{mode} : '>';
    if ($open_modes{$mode} and $mode ne '<') {
        $self->{mode} = $open_modes{$mode};
    } elsif (exists $open_modes_aliases{$mode} and $open_modes_aliases{$mode} ne '<') {
        $self->{mode} = $open_modes_aliases{$mode};
    } else {
        $self->{mode} = '>';
    }
    
    my $filename = $self->{file};
    $self->{file} = IO::File->new($filename, $mode);
    Carp::croak "Cannot open $filename for logging" unless defined $self->{file};
    
    my $binmode = exists $bin_modes{$self->{binmode}}
        ? substr($self->{binmode}, 0, 1) eq ':'
            ? $self->{binmode}
            : ":" . $self->{binmode}
        : ":utf8";
    $self->{file}->binmode($binmode);
    $self->{file}->autoflush(1);

    # File locking possibility
    $self->{__has_flock} = $Config{d_flock} || $Config{d_fcntl_can_lock} || $Config{d_lockf};
}

# Used from Log::Any::Adapter::File
foreach my $method ( Log::Any::Adapter::Util::logging_methods() ) {
    no strict 'refs';
    my $method_level = Log::Any::Adapter::Util::numeric_level( $method );
    *{$method} = sub {
        my ( $self, $text ) = @_;
        return if $method_level > $self->{log_level};
        my $msg = sprintf( "[%s] %s\n", scalar(localtime), $text );
        flock($self->{fh}, LOCK_EX) if $self->{__has_flock};
        $self->{fh}->print($msg);
        flock($self->{fh}, LOCK_UN) if $self->{__has_flock};
      }
}

foreach my $method ( Log::Any::Adapter::Util::detection_methods() ) {
    no strict 'refs';
    my $base = substr($method,3);
    my $method_level = Log::Any::Adapter::Util::numeric_level( $base );
    *{$method} = sub {
        return !!(  $method_level <= $_[0]->{log_level} );
    };
}

