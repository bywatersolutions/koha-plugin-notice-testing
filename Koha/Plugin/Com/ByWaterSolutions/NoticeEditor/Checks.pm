package Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Checks;

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

use Template::Parser;
use Try::Tiny qw( catch try );

use C4::Context;
use Koha::CirculationRules;
use Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Validator;

=head1 NAME

Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Checks - Check notice templates for problems

=head1 SYNOPSIS

    my $problems = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Checks->new(
        {
            module  => 'circulation',
            code    => 'ODUE',
            title   => $title,
            content => $content,
        }
    )->validate;

=head1 DESCRIPTION

The methods are copies of those of Koha::Notice::Template (Koha bugs 39716 and
43395), for Koha versions without them. Keep them in sync.

=head1 API

=head2 Class methods

=head3 new

    my $checks = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Checks->new(
        { module => $module, code => $code, message_transport_type => $mtt, title => $title, content => $content } );

=cut

sub new {
    my ( $class, $params ) = @_;
    return bless { map { $_ => $params->{$_} } qw( module code message_transport_type title content ) }, $class;
}

=head3 module, code, message_transport_type, title, content

Accessors, as for Koha::Notice::Template

=cut

sub module                 { return $_[0]->{module} }
sub code                   { return $_[0]->{code} }
sub message_transport_type { return $_[0]->{message_transport_type} }
sub title                  { return $_[0]->{title} }
sub content                { return $_[0]->{content} }

=head3 repeatable_content

    my $repeatable = $template->repeatable_content;

Returns a hashref describing the repeatable content this notice is expected to
contain when it is sent, or undef if the notice does not receive a list of
records. The hashref has the following keys:

=over

=item loop

The name of the Template Toolkit variable holding the records (e.g. 'overdues').

=item tokens

An arrayref of bespoke placeholders that are expanded to one line per record
(e.g. 'items.content').

=item tags

An arrayref of bespoke enclosing tags whose content is repeated once per
record (e.g. 'item' for <item>...</item>).

=back

=cut

sub repeatable_content {
    my ($self) = @_;

    return unless ( $self->module // q{} ) eq 'circulation';

    my $code = $self->code // q{};

    if ( $code eq 'PREDUEDGST' || $code eq 'DUEDGST' ) {
        return { loop => 'checkouts', tokens => ['items.content'], tags => [] };
    }

    my $is_overdue_notice = $code eq 'ODUE' || _used_by_overdue_triggers($code);

    if ($is_overdue_notice) {
        return { loop => 'overdues', tokens => ['items.content'], tags => ['item'] };
    }

    return;
}

=head3 _used_by_overdue_triggers

    my $used = _used_by_overdue_triggers($code);

Whether the notice code is used in the overdue notice triggers.

Unlike Koha::Notice::Template::repeatable_content, this supports both places
the triggers are stored in: circulation rules (overdue_X_notice) from Koha
26.11, and the overduerules table before.

=cut

sub _used_by_overdue_triggers {
    my ($code) = @_;

    if ( exists Koha::CirculationRules->rule_kinds->{overdue_X_notice} ) {
        return Koha::CirculationRules->search(
            {
                rule_name  => { -like => 'overdue\_%\_notice' },
                rule_value => $code,
            }
        )->count;
    }

    return C4::Context->dbh->selectrow_array(
        q{SELECT COUNT(*) FROM overduerules WHERE ? IN ( letter1, letter2, letter3 )},
        undef, $code
    );
}

=head3 validate

    my $problems = $template->validate;

Checks the title and content of the notice template for problems that would
stop it from being sent as expected. Returns an arrayref of hashrefs, empty if
no problem was found. Each hashref has:

=over

=item type

The kind of problem, see below.

=item severity

'error' if the notice cannot be generated, 'warning' if it can but will not
show what is expected.

=item field

'title' or 'content', when the problem is in one of them.

=item lines

An arrayref of the line numbers of I<field> where the problem is, when known.

=back

The types of problems are:

=over

=item tt_syntax

The Template Toolkit markup cannot be parsed. I<error> holds the parser error
message.

=item unclosed_tag

A '[%' has no matching '%]'. Template Toolkit prints it as plain text.

=item lowercase_directive

A Template Toolkit directive (I<directive>, e.g. ELSE) is not written in
capitals (as I<used>, e.g. 'else'). Template Toolkit only knows directives in
capitals: it is an error when the template cannot be parsed, else a warning, as
the word is then read as a variable (e.g. the content after [% else %] is always
shown).

=item tt_error

Processing the template without data fails. I<error> holds the Template
Toolkit error message.

=item missing_repeatable_content

The notice receives a list of records (see L</repeatable_content>) but its
content lists them neither with a Template Toolkit loop on I<loop> (FOREACH, or
I<loop>.next) nor with one of the bespoke I<tokens> or I<tags>. SMS templates
are not checked, as they often only give the number of records.

=item unknown_variable, unknown_method, missing_plugin, unknown_block

The I<field> uses a variable, field, plugin or block that will not be
available when the notice is generated. See
L<Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Validator/check_variables>.

=back

=cut

sub validate {
    my ($self) = @_;

    my @problems;

    for my $field (qw( title content )) {
        my $text = $self->$field // q{};
        next if $text eq q{};

        # Template Toolkit outputs an unterminated [% tag as plain text.
        # Blank out the complete tags (keeping newlines) and look for a leftover [%
        ( my $outside_tags = $text ) =~ s{\[%.*?%\]}{ $& =~ s/[^\n]/ /gr }gse;
        my $unclosed = index( $outside_tags, '[%' );
        if ( $unclosed >= 0 ) {
            push @problems, {
                type     => 'unclosed_tag',
                severity => 'warning',
                field    => $field,
                lines    => [ 1 + ( () = substr( $outside_tags, 0, $unclosed ) =~ /\n/g ) ],
            };
        }

        my $parser   = Template::Parser->new;
        my $compiles = defined $parser->parse($text);

        push @problems, map {
            { %$_, severity => $compiles ? 'warning' : 'error', field => $field }
        } _lowercase_directives($text);

        next if $compiles;

        my $error = $parser->error;
        my @lines = $error =~ s/^line (\d+): // ? ($1) : ();
        push @problems, {
            type     => 'tt_syntax',
            severity => 'error',
            field    => $field,
            error    => $error,
            lines    => \@lines,
        };
    }

    # SMS templates often give the number of records instead of listing them
    my $content = $self->content // q{};
    if (   $content ne q{}
        && ( $self->message_transport_type // q{} ) ne 'sms'
        && ( my $repeatable = $self->repeatable_content ) )
    {
        my $loop = $repeatable->{loop};

        # A loop on the records, or going through them (e.g. with WHILE), in a
        # TT tag: using them otherwise (e.g. overdues.count) does not list them
        ( my $tags = $content ) =~ s{(\[%.*?%\])|[^\n]}{ defined $1 ? $1 : ' ' }gse;
        my $found = $tags =~ m{(?:\[%[-+~]?|;)\s*(?:FOREACH|FOR)\s+(?:\w+\s*(?:IN|=)\s*)?\Q$loop\E\b};
        $found ||= $tags =~ m{\b\Q$loop\E\s*\.\s*(?:next|as_list)\b};
        $found ||= grep { $content =~ m{<<\Q$_\E>>} } @{ $repeatable->{tokens} };
        $found ||= grep { $content =~ m{<\Q$_\E>.*</\Q$_\E>}s } @{ $repeatable->{tags} };

        push @problems, { type => 'missing_repeatable_content', severity => 'warning', %$repeatable } unless $found;
    }

    # Only look for unavailable variables in templates that compile
    unless ( grep { $_->{type} eq 'tt_syntax' } @problems ) {
        my $validator = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Validator->new(
            { module => $self->module, code => $self->code } );
        for my $field (qw( title content )) {

            # A lowercase directive read as a variable is already reported
            my %directives = map { $_->{used} => 1 }
                grep { $_->{type} eq 'lowercase_directive' && $_->{field} eq $field } @problems;
            push @problems, map {
                { %$_, field => $field }
                }
                grep { !( $_->{type} eq 'unknown_variable' && $directives{ $_->{variable} } ) }
                @{ $validator->check_variables( $self->$field ) };
        }
    }

    # Errors found while processing the template, when not explained above
    unless ( grep { $_->{severity} eq 'error' } @problems ) {
        for my $field (qw( title content )) {
            my $error = $self->_processing_error( $self->$field ) or next;
            push @problems, { type => 'tt_error', severity => 'error', field => $field, error => $error };
        }
    }

    return \@problems;
}

=head3 _lowercase_directives

    my @problems = _lowercase_directives($text);

Returns a lowercase_directive problem (see L</validate>), without severity nor
field, for each Template Toolkit directive not written in capitals in the tags
of I<$text>: at the start of a statement, or after an expression for those that
can be (e.g. [% name if name %]). Words used as variables by the template (e.g.
[% SET last = 1 %]) are not reported, nor ones followed by a field, arguments
or an assignment (e.g. loop.last, item.in).

=cut

my @TT_DIRECTIVES = qw(
    BLOCK CALL CASE CATCH CLEAR DEBUG DEFAULT ELSE ELSIF END FILTER FINAL FOR FOREACH GET IF INCLUDE INSERT LAST
    MACRO META NEXT PERL PROCESS RAWPERL RETURN SET STOP SWITCH TAGS THROW TRY UNLESS USE VIEW WHILE WRAPPER
);

# Directives that can follow an expression, e.g. [% name IF name %]
my %TT_TRAILING = map { $_ => 1 } qw( IF UNLESS FOR FOREACH WHILE FILTER );

sub _lowercase_directives {
    my ($text) = @_;

    my %directives = map { lc($_) => $_ } @TT_DIRECTIVES, 'IN';

    # Blank out the strings and comments of the tags, keeping their positions
    my @tags;
    while ( $text =~ m{\[%(.*?)%\]}gs ) {
        my ( $tag, $offset ) = ( $1, $-[1] );
        next if $tag =~ m{^[-+~=]?#};                                                   # Comment tag
        $tag         =~ s{"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'}{ ' ' x length $& }gse;
        $tag         =~ s{#[^\n]*}{ ' ' x length $& }ge;
        $tag         =~ s{^[-+~=]|[-+~=]$}{ }g;
        push @tags, { tag => $tag, offset => $offset };
    }

    # Variables the template defines, which can have the name of a directive
    my %variables;
    for my $tag ( map { $_->{tag} } @tags ) {
        $variables{$1} = 1 while $tag =~ m{(?<![\w.\$])(\w+)\s*=(?!=)}g;
        $variables{$1} = 1 while $tag =~ m{\b(?:FOREACH|FOR|MACRO)\s+(\w+)}g;
    }

    my ( @problems, %found );
    for my $tag (@tags) {
        while ( $tag->{tag} =~ m{(?<![\w.\$])([A-Za-z]+)\b(?!\s*(?:[.(]|=(?!=)))}g ) {
            my ( $word, $position ) = ( $1, $-[1] );
            my $directive = $directives{ lc $word };
            next if !$directive || $word eq $directive || $variables{$word};

            my $before = substr( $tag->{tag}, 0, $position );
            if ( $directive eq 'IN' ) {
                next unless $before =~ m{\b(?:FOREACH|FOR)\s+\w+\s+$}i;
            } else {
                next unless $before =~ m{(?:^|;)\s*$} || $TT_TRAILING{$directive};
            }

            my $line = 1 + ( () = substr( $text, 0, $tag->{offset} + $position ) =~ /\n/g );
            unless ( $found{$word} ) {
                $found{$word} = { type => 'lowercase_directive', directive => $directive, used => $word, lines => [] };
                push @problems, $found{$word};
            }
            push @{ $found{$word}->{lines} }, $line unless grep { $_ == $line } @{ $found{$word}->{lines} };
        }
    }
    return @problems;
}

=head3 _processing_error

    my $error = $self->_processing_error($text);

Processes I<$text> as a notice template without any data, as the notice editor
does when showing a notice, and returns the Template Toolkit error message if it
fails. Some errors (e.g. an unknown filter) happen whatever the data is.

=cut

sub _processing_error {
    my ( $self, $text ) = @_;

    return if ( $text // q{} ) eq q{};

    require C4::Letters;
    local $SIG{__WARN__} = sub { };    # Missing data gives 'not numeric' warnings
    return try {
        C4::Letters::_process_tt( { content => $text } );
        return;
    } catch {
        my $error = "$_";
        $error =~ s/^ERROR PROCESSING TEMPLATE: //;
        $error =~ s/\n.*//s;
        $error =~ s/ at \S+ line \d+\.$//;
        return $error;
    };
}

1;
