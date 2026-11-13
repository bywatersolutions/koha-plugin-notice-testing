package Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Validator;

# This file is part of the Koha notice editor plugin, and of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <https://www.gnu.org/licenses>.

use Modern::Perl;

use Module::Load::Conditional qw( can_load );
use Template::Parser;
use Template::Stash;

use Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::TableConfig;
use Koha::Database;
use Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables;

# Template Toolkit virtual methods of hashes, used when the hash has no such key:
# those of hashes, and those of lists, which hashes get as lists of one hash
my %HASH_VMETHODS =
    map { $_ => 1 } keys %$Template::Stash::HASH_OPS, keys %$Template::Stash::LIST_OPS;

# What the compiled code of a variable used as a filter starts with
my $FILTER_CALL = '$context->filter(';

=head1 NAME

Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Validator - Check the Template Toolkit markup of notice templates

=head1 SYNOPSIS

    my $validator = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Validator->new(
        { module => 'patron_slip', code => 'MYSLIP' } );
    my $problems = $validator->check_variables($content);

=head1 DESCRIPTION

A copy of Koha::Notice::Template::Validator (Koha bug 43395), for Koha versions
without it. Keep them in sync.

Finds the variables a notice template uses that the notice will not receive
when it is generated, by compiling the template with L<Template::Parser> and
reading the variable lookups from the generated code.

Variables are followed through the objects the notice receives: for
I<checkout.item.biblio.title> the validator checks that I<item> is a field or
method of L<Koha::Checkout>, then that I<biblio> is one of L<Koha::Item> and so
on, for as long as it can tell which class each step returns. Steps it cannot
follow (method results, hashes, plain values) are trusted.

=head1 API

=head2 Class methods

=head3 new

    my $validator = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Validator->new( { module => $module, code => $code } );

=cut

sub new {
    my ( $class, $params ) = @_;
    my $self = {
        module => $params->{module} // q{},
        code   => $params->{code}   // q{},
    };
    $self->{variables} =
        Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables->for_notice( $self->{module}, $self->{code} );

    # The content added by plugins, under the namespace of each
    $self->{plugin_content} = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables->plugin_content_type(
        $self->{module},
        $self->{code}
    );
    return bless $self, $class;
}

=head3 knows_variables

Returns true if the variables passed to this notice are known, so they can be
checked.

=cut

sub knows_variables {
    my ($self) = @_;
    return defined $self->{variables};
}

=head3 check_variables

    my $problems = $validator->check_variables($content);

Returns an arrayref of problems found in I<$content>, each a hashref with a
I<type>, a I<severity> ('error' if the notice will fail to generate, else
'warning') and the I<lines> of I<$content> where the problem is. Types are:

=over

=item unknown_variable

I<variable> is not passed to this notice nor defined in the template.
I<available> lists the variables that are passed to it, and I<suggestion>
names one holding the same kind of object, if any (e.g. 'borrower' for 'patron').

=item unknown_method

I<variable> (the path up to the problem, e.g. 'borrower.firstnme') is not a
field or method of I<class>.

=item missing_plugin

I<plugin> is a Template Toolkit plugin the template uses without loading it
with [% USE I<plugin> %]. It is an error when the plugin is used as a filter
(e.g. | $Price), as Template Toolkit then fails.

=item unknown_key

I<variable> (the path up to the problem, e.g. 'branch.nmae') uses a key that
does not exist in the hash; I<keys> lists the keys it has. Only hashes the
registry lists the keys of are checked (e.g. SR_SLIP's branch). Template Toolkit
prints nothing for it.

=item unknown_block

The template processes the block I<block>, which it does not define.

=back

Templates that cannot be compiled give no problems. For notices whose
variables are not known, only plugins and blocks are checked.

=cut

sub check_variables {
    my ( $self, $content ) = @_;

    return [] unless defined $content && $content =~ /\[%/;

    my $parsed = Template::Parser->new->parse($content);
    return [] unless $parsed;

    my $code = join "\n", $parsed->{BLOCK}, values %{ $parsed->{DEFBLOCKS} || {} };

    # Types of the variables the template can use
    my %types = (
        %{ $self->{variables} || {} },
        map { $_ => { kind => 'unknown' } } Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables->globals,
    );

    $types{plugin_content} = $self->{plugin_content};

    # A variable has one type for the whole template: one assigned values of
    # different types (or values of another type than the notice passes) is
    # not checked, as which one it has depends on where it is used
    my $assign = sub {
        my ( $name, $type ) = @_;
        $types{$name} =
            !exists $types{$name}
            || Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables::_same_type( $types{$name}, $type )
            ? $type
            : { kind => 'unknown' };
    };

    # Variables defined by the template itself: SET, USE, MACRO, WHILE (x = ...)
    while ( $code =~ m{\$stash->set\('((?:[^'\\]|\\.)*)',\s*(.*?)\);\n}gs ) {
        my ( $name, $value ) = ( $1, $2 );
        my ($chain) = $value =~ m{^\$stash->get\((.*)\)$}s;
        $assign->( $name, $chain ? $self->_resolve( \%types, _parse_chain($chain) )->{type} : { kind => 'unknown' } );
    }

    # Arguments of MACROs, and parameters of INCLUDE and PROCESS: variables in
    # the macro or block, whose values are not checked. As other variables, they
    # are not scoped: their names are not reported outside it either
    while ( $code =~ m{\@_tt_args\{\s*(.*?)\}\s*=}g ) {
        my $names = $1;
        $assign->( _unquote($1), { kind => 'unknown' } ) while $names =~ m{'((?:[^'\\]|\\.)*)'}g;
    }
    while ( $code =~ m{\$context->(?:process|include)\('(?:[^'\\]|\\.)*',\s*(?=\{)}g ) {
        my $params = _balanced( $code, pos($code) ) // next;
        $assign->( _unquote($1), { kind => 'unknown' } ) while $params =~ m{'((?:[^'\\]|\\.)*)'\s*=>}g;
    }

    # FOREACH: each list lookup is followed by the assignment of its loop
    # variable, before the list of any loop nested in it. A loop without a
    # variable (FOREACH list) instead makes the keys of each element that is a
    # hash variables: as they can be anything, variables are not checked in it,
    # unless its elements are objects, whose fields are not made variables.
    my @lists;
    while ( $code =~ m{my \$_tt_list = (.*?);\n}gs ) {
        push @lists, { list => $1, start => $-[0], end => $+[0] };
    }
    my @imported;    # [ start, end ] of the code of loops without a variable
    for my $i ( 0 .. $#lists ) {
        my $until   = $i < $#lists ? $lists[ $i + 1 ]->{start} : length $code;
        my $body    = substr( $code, $lists[$i]->{end}, $until - $lists[$i]->{end} );
        my ($chain) = $lists[$i]->{list} =~ m{^\$stash->get\((.*)\)$}s;
        my $type    = $chain ? $self->_resolve( \%types, _parse_chain($chain) )->{type} : { kind => 'unknown' };
        if ( $body =~ m{\$stash->\{'((?:[^'\\]|\\.)*)'\} = \$_tt_value;} ) {
            $assign->( $1, _element_type($type) );
        } elsif ( $body =~ m{\$stash->get\(\['import',} && _element_type($type)->{kind} ne 'object' ) {
            my $scope = _localised( $code, $lists[$i]->{end} );
            push @imported, $scope if $scope;
        }
    }

    my @problems;
    my %found;    # Problem key => problem, to report each problem once with all its lines
    my $report = sub {
        my ( $key, $problem, $line ) = @_;
        unless ( $found{$key} ) {
            $found{$key} = { %$problem, lines => [] };
            push @problems, $found{$key};
        }
        push @{ $found{$key}->{lines} }, $line
            if defined $line && !grep { $_ == $line } @{ $found{$key}->{lines} };
    };

    my $line_index = _line_index($code);
    for my $lookup ( _variable_lookups( $code, $line_index ) ) {
        my $problem = $self->_resolve( \%types, $lookup->{chain} )->{problem} or next;
        next
            if $problem->{type} eq 'unknown_variable'
            && grep { $lookup->{at} > $_->[0] && $lookup->{at} < $_->[1] } @imported;

        # Template Toolkit fails on fields that objects do not have, and on
        # filters it cannot find. Other missing variables just print nothing.
        my $fatal = $problem->{type} eq 'unknown_method' || $lookup->{filter};
        my $key   = join '|', $problem->{type}, $problem->{variable};
        $report->( $key, { %$problem, severity => 'warning' }, $lookup->{line} );
        $found{$key}->{severity} = 'error' if $fatal;
    }

    my %blocks = map { $_ => 1 } keys %{ $parsed->{DEFBLOCKS} || {} };
    my @processed;
    while ( $code =~ m{\$context->(?:process|include)\('((?:[^'\\]|\\.)*)'}g ) {
        push @processed, { name => _unquote($1), line => _line_at( $line_index, $-[0] ) };
    }

    # Files from the includes (e.g. PROCESS 'accounts.inc') can define blocks we don't see
    unless ( grep { $_->{name} =~ m{[./]} } @processed ) {
        for my $block ( grep { !$blocks{ $_->{name} } } @processed ) {
            $report->(
                "unknown_block|$block->{name}",
                { type => 'unknown_block', severity => 'error', block => $block->{name} },
                $block->{line}
            );
        }
    }

    # Template Toolkit gives block directives (IF, FOREACH...) the line of their
    # END: find the lines in the template itself when possible
    ( my $tags = $content ) =~ s{(\[%.*?%\])|[^\n]}{ defined $1 ? $1 : ' ' }gse;
    for my $problem (@problems) {
        my @lines = _source_lines( $tags, $problem );
        @lines = @{ $problem->{lines} } unless @lines;
        $problem->{lines} = [ sort { $a <=> $b } @lines ];
    }

    # In the order they appear in the template
    return [ sort { ( $a->{lines}->[0] // 0 ) <=> ( $b->{lines}->[0] // 0 ) } @problems ];
}

=head2 Internal methods

=cut

=head3 _resolve

Follow a variable lookup (as returned by _parse_chain) through the types
known for the template. Returns { type => ... } and, when a step is
certainly wrong, { problem => ... }

=cut

sub _resolve {
    my ( $self, $types, $chain ) = @_;

    my ( $root, @steps ) = @$chain;
    return { type => { kind => 'unknown' } } unless defined $root;

    my $type = $types->{$root};
    unless ($type) {
        if ( $root =~ /^\w+$/ && can_load( modules => { "Koha::Template::Plugin::$root" => undef } ) ) {
            return {
                type    => { kind => 'unknown' },
                problem => { type => 'missing_plugin', variable => $root, plugin => $root },
            };
        }

        # Without the list of the variables of the notice, it may receive any
        return { type => { kind => 'unknown' } } unless $self->knows_variables;

        return {
            type    => { kind => 'unknown' },
            problem => {
                type       => 'unknown_variable',
                variable   => $root,
                available  => [ sort keys %{ $self->{variables} } ],
                suggestion => scalar $self->_suggestion($root),
            },
        };
    }

    my $path = $root;
    for my $step (@steps) {
        return { type => { kind => 'unknown' } } unless defined $step;    # Dynamic step, e.g. foo.$bar
        if ( $type->{kind} eq 'object' ) {
            my $next = _object_step( $type->{class}, $step );
            unless ($next) {
                return {
                    type    => { kind => 'unknown' },
                    problem => {
                        type     => 'unknown_method',
                        variable => "$path.$step",
                        class    => $type->{class},
                    },
                };
            }
            $type = $next;
        } elsif ( $type->{kind} eq 'objects' ) {
            $type =
                  $step =~ /^(?:next|last|single)$/ ? { kind => 'object', class => _object_class( $type->{class} ) }
                : $step eq 'count'                  ? { kind => 'scalar' }
                :                                     { kind => 'unknown' };
        } elsif ( $type->{kind} eq 'array_of_objects' ) {
            $type =
                $step =~ /^(?:\d+|first|last)$/ ? { kind => 'object', class => $type->{class} } : { kind => 'unknown' };
        } elsif ( $type->{kind} eq 'hash' ) {
            my $keys = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables->keys_of($type)
                or return { type => { kind => 'unknown' } };
            if ( $keys->{$step} ) {
                $type = $keys->{$step};
            } elsif ( $HASH_VMETHODS{$step} ) {
                return { type => { kind => 'unknown' } };
            } else {
                return {
                    type    => { kind => 'unknown' },
                    problem => { type => 'unknown_key', variable => "$path.$step", keys => [ sort keys %$keys ] },
                };
            }
        } elsif ( $type->{kind} eq 'array_of_hashes' ) {
            $type = $step =~ /^(?:\d+|first|last)$/ ? _element_type($type) : { kind => 'unknown' };
        } else {
            return { type => { kind => 'unknown' } };
        }
        $path .= ".$step";
    }

    return { type => $type };
}

=head3 _suggestion

A passed variable holding the same kind of object as the name $name usually
does in notices (e.g. 'borrower' for 'patron')

=cut

sub _suggestion {
    my ( $self, $name ) = @_;

    return $self->{suggestions}->{$name} if exists $self->{suggestions}->{$name};
    $self->{usual_class} //= {
        patron  => 'Koha::Patron',
        library => 'Koha::Library',
        map {
            my $config = $_;
            can_load( modules => { $config->{module} => undef } )
                ? ( $config->{singular} => $config->{module}->object_class )
                : ()
        } values %{ Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::TableConfig::tt_table_config() },
    };
    my $class = $self->{usual_class}->{$name} or return $self->{suggestions}->{$name} = undef;

    my ($suggestion) =
        sort grep {
        my $type = $self->{variables}->{$_};
        $type->{kind} eq 'object' && ( $type->{class} // q{} ) eq $class
        } keys %{ $self->{variables} };
    return $self->{suggestions}->{$name} = $suggestion;
}

=head3 _object_step

The type of the next step from an object of class $class, or undef if
$class has no such field or method

=cut

sub _object_step {
    my ( $class, $step ) = @_;

    return { kind => 'unknown' } unless $class && can_load( modules => { $class => undef } );
    return { kind => 'unknown' } unless $class->can('_type');

    my $source = eval { Koha::Database->new->schema->source( $class->_type ) };
    return { kind => 'unknown' } unless $source;

    return { kind => 'scalar' }  if $source->has_column($step);
    return { kind => 'unknown' } if grep { $_ eq $step } qw( is_changed id in_storage get_column make_column_dirty );
    return undef unless $class->can($step);    ## no critic (ProhibitExplicitReturnUndef)

    # Methods named after a relationship return the related object(s)
    if ( $source->has_relationship($step) ) {
        my $info    = $source->relationship_info($step);
        my $related = $info->{class};
        if ( can_load( modules => { $related => undef } ) ) {
            my $accessor = $info->{attrs}->{accessor} // q{};
            if ( $accessor eq 'multi' ) {
                return { kind => 'objects', class => $related->koha_objects_class }
                    if $related->can('koha_objects_class');
            } elsif ( my $object_class = _koha_class_for($related) ) {
                return { kind => 'object', class => $object_class };
            }
        }
    }

    return { kind => 'unknown' };
}

=head3 _koha_class_for

The Koha::Object class for a DBIC result class, following the same convention
as Koha::Object::_get_object_class, if it exists and matches the result class

=cut

sub _koha_class_for {
    my ($result_class) = @_;

    my $class = Koha::Object::_get_object_class($result_class);
    return unless $class && can_load( modules => { $class => undef } ) && $class->can('_type');
    return unless "Koha::Schema::Result::" . $class->_type eq $result_class;
    return $class;
}

=head3 _object_class

The Koha::Object class of the objects in a Koha::Objects class.

=cut

sub _object_class {
    my ($objects_class) = @_;
    return unless $objects_class && can_load( modules => { $objects_class => undef } );
    return $objects_class->can('object_class') ? $objects_class->object_class : undef;
}

=head3 _element_type

The type of the elements of a list, used for the variable of a FOREACH loop.

=cut

sub _element_type {
    my ($type) = @_;
    return { kind => 'object', class => _object_class( $type->{class} ) } if $type->{kind} eq 'objects';
    return { kind => 'object', class => $type->{class} }                  if $type->{kind} eq 'array_of_objects';
    return { kind => 'hash',   map { $type->{$_} ? ( $_ => $type->{$_} ) : () } qw( keys tables ) }
        if $type->{kind} eq 'array_of_hashes';
    return { kind => 'unknown' };
}

=head3 _variable_lookups

All the variable lookups ($stash->get calls) in compiled template code,
including the ones nested in method arguments. Each is a hashref with the
I<chain> of names (see L</_parse_chain>), its position I<at> in I<$code>, the
I<line> of the template it is on, and I<filter> set if the variable is used as a
filter (e.g. | $Price). The import Template Toolkit does in loops without a
variable is not a lookup of a variable, and is left out.

=cut

sub _variable_lookups {
    my ( $code, $line_index ) = @_;
    $line_index //= _line_index($code);
    my @lookups;
    while ( $code =~ m{\$stash->get\(}g ) {
        my $start = pos($code);
        my $args  = _balanced( $code, $start - 1 );
        next unless defined $args;
        my $at = $start - length('$stash->get(');

        # Template Toolkit's import of the elements of a loop without a variable
        next if $args =~ m{^\['import',\s*\[\$_tt_value\]\]$};
        push @lookups, {
            chain  => _parse_chain($args),
            at     => $at,
            line   => _line_at( $line_index, $at ),
            filter => $at >= length $FILTER_CALL
                && substr( $code, $at - length $FILTER_CALL, length $FILTER_CALL ) eq $FILTER_CALL ? 1 : 0,
        };
        pos($code) = $start;
    }
    return @lookups;
}

=head3 _localised

The [ start, end ] of the compiled code run in the stash localised by the
first $context->localise() after I<$position>, up to the matching
$context->delocalise(); undef if there is none.

=cut

sub _localised {
    my ( $code, $position ) = @_;
    pos($code) = $position;
    my ( $start, $depth );
    while ( $code =~ m{\$context->(localise|delocalise)\(\)}g ) {
        if ( $1 eq 'localise' ) {
            $start //= $-[0];
            $depth++;
        } elsif ( defined $start && !--$depth ) {
            return [ $start, $+[0] ];
        }
    }
    return;
}

=head3 _source_lines

The lines of the Template Toolkit tags of I<$tags> (the template with only the
text of its tags, and its newlines) using the variable or block of
I<$problem>.

=cut

sub _source_lines {
    my ( $tags, $problem ) = @_;

    my $pattern;
    if ( $problem->{type} eq 'unknown_block' ) {
        $pattern = qr{\b(?:PROCESS|INCLUDE)\s+['"]?\Q$problem->{block}\E\b};
    } else {
        my $path = join '\s*\.\s*', map { quotemeta } split /\./, $problem->{variable};
        $pattern = qr{(?<![\w.])$path\b};
    }

    # Count the newlines from one match to the next only
    my @lines;
    my ( $line, $counted ) = ( 1, 0 );
    while ( $tags =~ m{$pattern}g ) {
        $line += () = substr( $tags, $counted, $-[0] - $counted ) =~ /\n/g;
        $counted = $-[0];
        push @lines, $line unless @lines && $lines[-1] == $line;
    }
    return @lines;
}

=head3 _line_index

    my $line_index = _line_index($code);

The positions of the '#line' comments Template::Parser adds to the compiled
code, with their line, for L</_line_at>

=cut

sub _line_index {
    my ($code) = @_;
    my @index;
    push @index, [ $+[0], $1 ] while $code =~ m{^#line (\d+) }mg;
    return \@index;
}

=head3 _line_at

    my $line = _line_at( $line_index, $position );

The line of the template the compiled code at position I<$position> comes
from, as given by the last '#line' comment Template::Parser adds before it

=cut

sub _line_at {
    my ( $index, $position ) = @_;
    my ( $low,   $high )     = ( 0, $#$index );
    my $line;
    while ( $low <= $high ) {
        my $middle = int( ( $low + $high ) / 2 );
        if ( $index->[$middle]->[0] <= $position ) {
            $line = $index->[$middle]->[1];
            $low  = $middle + 1;
        } else {
            $high = $middle - 1;
        }
    }
    return $line;
}

=head3 _balanced

The text between the bracket at $open and its matching closing bracket

=cut

sub _balanced {
    my ( $code, $open ) = @_;
    my $depth = 0;
    my $i     = $open;
    while ( $i < length $code ) {
        my $c = substr( $code, $i, 1 );
        if ( $c eq q{'} ) {
            pos($code) = $i;
            $code =~ m{\G'(?:[^'\\]|\\.)*'}gc or return;
            $i = pos($code);
            next;
        }
        $depth++ if $c =~ /[(\[{]/;
        $depth-- if $c =~ /[)\]}]/;
        return substr( $code, $open + 1, $i - $open - 1 ) if $depth == 0;
        $i++;
    }
    return;
}

=head3 _parse_chain

Turn the argument of a $stash->get call into a list of names:
'foo' => ['foo']; ['foo', 0, 'bar', [ args ]] => ['foo', 'bar']
Steps that are not literal names (foo.$bar) are undef.

=cut

sub _parse_chain {
    my ($args) = @_;
    $args =~ s/^\s+|\s+$//g;

    if ( $args =~ m{^'((?:[^'\\]|\\.)*)'$}s ) {
        return [ _unquote($1) ];
    }
    return [] unless $args =~ s/^\[//;

    my @names;
    my $position = 0;
    while ( length $args ) {
        $args =~ s/^[\s,]+//;
        last if $args eq q{} || $args =~ /^\]/;
        my $element;
        if ( $args =~ s{^'((?:[^'\\]|\\.)*)'}{} ) {
            $element = _unquote($1);
        } elsif ( $args =~ /^[\[\{(]/ ) {
            my $inner = _balanced( $args, 0 );
            return \@names unless defined $inner;
            substr( $args, 0, length($inner) + 2 ) = q{};
        } elsif ( $args =~ s/^(\d+)// ) {
            $element = $1;
        } else {

            # An expression (e.g. a nested lookup for foo.$bar): skip to the next element
            my $i     = 0;
            my $depth = 0;
            while ( $i < length $args ) {
                my $c = substr( $args, $i, 1 );
                $depth++ if $c =~ /[(\[{]/;
                $depth-- if $c =~ /[)\]}]/;
                last     if $depth < 0 || ( $depth == 0 && $c eq ',' );
                $i++;
            }
            substr( $args, 0, $i ) = q{};
        }
        push @names, $element if $position % 2 == 0;
        $position++;
    }
    return \@names;
}

=head3 _unquote

Removes the escaping backslashes from a single-quoted string of generated code.

=cut

sub _unquote {
    my ($string) = @_;
    $string =~ s/\\(.)/$1/g;
    return $string;
}

1;
