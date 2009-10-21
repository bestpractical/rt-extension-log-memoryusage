use 5.008003;
use strict;
use warnings;

package RT::Extension::Log::MemoryUsage;

our $VERSION = '0.01';

=head1 NAME

RT::Extension::Log::MemoryUsage - log information about memory used by RT processes

=head1 DESCRIPTION

RT is a big application with many modules, extensions and different ways
to run system. As well, there are tons of ways to screw up memory usage.
It's hard to detect memory leaks and not only them, but just places in code
that like to eat lots of memory.

Purpose of this extension is to help identify requests that cause a memory
usage spikes.

=cut

our @KEYS = (
    [qw(rssize rss rsz)],
    [qw(vsz vsize)],
    ['tsiz'],
    ['size'],
    ['%mem', 'pmem'],
);

{
# check if exists
    my $test = `ps`;
    die "Couldn't execute `ps`: $!"
        unless defined $test;

# check -p
    $test = `ps -p $$`;
    die "Couldn't execute `ps -p $$`: $!"
        unless defined $test;

# check which keywords are supported
    foreach my $list ( splice @KEYS ) {
        foreach my $key ( splice @$list ) {
            my $test = `ps -p $$ -o '$key' 2>&1 1>/dev/null`;
            next if !defined $test || $test =~ /\S/;

            push @$list, $key;
        }
        push @KEYS, $list if @$list;
    }
    die "Looks like no keywords, we need, are supported"
        unless @KEYS;

# check -o 'x,y,z'
    {
        my $cmd = "ps -p $$ -o '". join( ',', map @$_, @KEYS ) ."'";
        my $test = `$cmd`;
        die "Couldn't run `$cmd`: $!"
            unless defined $test;
    }
};

sub ComparePs {
    my $self = shift;
    my ($old, $new) = @_;

    my $res = '';
    foreach my $list ( @KEYS ) {
        foreach my $key ( @$list ) {
            next unless exists $new->{$key};

            my ($from, $to) = ($old->{$key}||0, $new->{$key}||0);
            s/,/./ for $from, $to;
            $res .= '; ' if $res;
            $res .= $key .': ';
            if ( $from ne $to ) {
                if ( $from =~ /[^0-9.-]/ || $to =~ /[^0-9.-]/ ) {
                    # not numbers
                    $res .= $from .' -> '. $to;
                } else {
                    # numbers
                    my $diff = $to-$from;
                    $diff = "+$diff" if $diff > 0;
                    $res .= $to ." ($diff)";
                }
            } else {
                # no change
                $res .= $to;
            }
        }
    }
    return $res;
}

{ my $cmd = '';
sub RunPs {
    my $self = shift;
    $cmd ||= "ps -p $$ -o '". join( ',', map @$_, @KEYS ) ."'";
    my $text = `$cmd`;
    unless ( defined $text ) {
        $RT::Logger->error( "Couldn't run `$cmd`: $!" );
        return {};
    }
    return $self->ParsePsOutput( $text );
} }

sub ParsePsOutput {
    my $self = shift;
    my $text = shift;

    my ($head, $values) = split /\r*\n/, $text;
    my @head = split /(?<=\S)(?=\s)/, $head;
    my @values = map substr($values, 0, length $_, ''), @head;

    do { s/^\s+//; s/\s+$// } foreach @head, @values;
    return { map { lc($_) => shift @values } @head };
}

=head1 AUTHOR

Ruslan Zakirov E<lt>ruz@bestpractical.comE<gt>

=head1 LICENSE

Under the same terms as perl itself.

=cut

package RT::Extension::Log::MemoryUsage::MPL;
use base qw(HTML::Mason::Plugin);

my $usage;
sub start_request_hook {
    my ($self, $context) = @_;

    if ( my $before = $usage ) {
        my $now = $usage = RT::Extension::Log::MemoryUsage->RunPs;
        my $diff = RT::Extension::Log::MemoryUsage->ComparePs(
            $before => $now
        );

        my $msg = "memory before '". $context->request->request_comp->path ."'"
            ." => pid: $$; $diff;";
        $RT::Logger->info($msg);

    } else {
        $usage = RT::Extension::Log::MemoryUsage->RunPs;
    }
}

sub end_request_hook {
    my ($self, $context) = @_;

    my $before = $usage;
    my $now = $usage = RT::Extension::Log::MemoryUsage->RunPs;
    my $diff = RT::Extension::Log::MemoryUsage->ComparePs(
        $before => $now
    );

    my $msg = "memory after '". $context->request->request_comp->path ."'"
        ." => pid: $$; $diff;";
    $RT::Logger->info($msg);
}

1;
