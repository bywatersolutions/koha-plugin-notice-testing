package Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Preview;

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

use C4::Letters;
use C4::Message;
use Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Checks;
use Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::TableConfig;
use Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables;
use Koha::Account::Lines;
use Koha::Acquisition::Booksellers;
use Koha::Database;
use Koha::Items;
use Koha::Patrons;

=head1 NAME

Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Preview - Data to preview notice templates with

=head1 SYNOPSIS

    my $kinds   = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Preview->inputs( 'orderacquisition', 'ACQORDER' );    # [ 'basket', 'vendor' ]
    my $basket  = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Preview->find_record( 'basket', $basketno );
    my $preview = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Preview->new(
        { module => 'orderacquisition', code => 'ACQORDER', records => { basket => $basket } } );
    my $letter = C4::Letters::GetPreparedLetter( letter => $letter, %{ $preview->letter_params } );
    my $notes  = $preview->notes;

=head1 DESCRIPTION

A copy of Koha::Notice::Template::Preview (Koha bug 29490), for Koha versions
without it. Keep them in sync.

Builds the parameters of C4::Letters::GetPreparedLetter to preview a notice,
from the variables the notice receives (see Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables)
and the records it is previewed with, which depend on the notice (see
L</inputs>): a patron and an item, a basket, a vendor, a hold...

The records related to them are used too: the vendor and the orders of a
basket, the patron and the item of a hold, the library, checkouts, holds and
account lines of a patron...

When no related record of a kind is found, a sample record of that kind is
used. The variables that are plain values get placeholders. The I<notes> say
which data does not come from the records the notice is previewed with.

=head1 API

=cut

# The kinds of records a notice can be previewed with, in the order the notice
# editor offers them:
# - class: their class
# - fk: the column other tables refer to them with (e.g. aqbasket.booksellerid
#   for vendors), to find the records related to them
# - related: the methods giving the records of other kinds related to them,
#   when their columns are named otherwise (e.g. the suggester of a suggestion)
# - library: the method giving the library their notices are sent with (e.g.
#   the pickup library of a hold)
# - find: how to find them from what staff know them by, else by their id
# - input: 0 if they are only found from other records
our @RECORDS = (
    {
        kind => 'patron', class => 'Koha::Patron', fk => 'borrowernumber',
        find => sub {
            my ($value) = @_;
            return Koha::Patrons->find( { cardnumber => $value } ) || Koha::Patrons->find( { userid => $value } );
        },
    },
    {
        kind => 'item', class => 'Koha::Item', fk => 'itemnumber',
        find => sub { return Koha::Items->find( { barcode => $_[0] } ) },
    },
    { kind => 'basket', class => 'Koha::Acquisition::Basket', fk => 'basketno' },
    { kind => 'order',  class => 'Koha::Acquisition::Order',  fk => 'ordernumber' },
    {
        kind => 'vendor', class => 'Koha::Acquisition::Bookseller', fk => 'booksellerid',
        find => sub {
            my ($value) = @_;
            return ( $value =~ /^\d+$/ && Koha::Acquisition::Booksellers->find($value) )
                || Koha::Acquisition::Booksellers->search( { name => $value } )->next;
        },
    },
    { kind => 'hold', class => 'Koha::Hold', fk => 'reserve_id', library => 'pickup_library' },
    {
        kind    => 'suggestion', class => 'Koha::Suggestion', fk => 'suggestionid',
        related => { patron => 'suggester' },
    },
    {
        kind    => 'illrequest',           class   => 'Koha::ILL::Request', fk => 'illrequest_id',
        related => { biblio => 'biblio' }, library => 'library',
    },
    {
        kind => 'booking', class => 'Koha::Booking', fk => 'booking_id',
        related => { patron => 'patron', item => 'item', biblio => 'biblio' }, library => 'pickup_library',
    },
    { kind => 'article_request', class => 'Koha::ArticleRequest', library => 'branch' },
    {
        kind => 'recall', class => 'Koha::Recall', fk => 'recall_id',
        related => { patron => 'patron', item => 'item', biblio => 'biblio' }, library => 'library',
    },
    {
        kind    => 'ticket', class => 'Koha::Ticket', fk => 'ticket_id',
        related => { patron => 'reporter', biblio => 'biblio' },
    },
    {
        kind    => 'subscription', class => 'Koha::Subscription', fk => 'subscriptionid',
        related => { vendor => 'vendor' },
    },
    {
        kind => 'oai_server', class => 'Koha::OAIServer', fk => 'oai_server_id',
        find => sub {
            my ($value) = @_;
            require Koha::OAIServers;
            return ( $value =~ /^\d+$/ && Koha::OAIServers->find($value) )
                || Koha::OAIServers->search( { servername => $value } )->next;
        },
    },
    { kind => 'biblio', class => 'Koha::Biblio', fk => 'biblionumber', input => 0 },
);

# Notices queued once per item, and combined while the first one is not sent
# (see C4::Message->append): checkouts, checkins and renewals
# (C4::Circulation::SendCirculationAlert), and the digest of waiting holds
# (C4::Reserves::_koha_notify_reserve: HOLD is sent on its own, HOLDDGST to
# patrons who want a digest). The patron's records to preview them with when
# no items are given.
our %COMBINED = (
    circulation => { CHECKIN  => 'old_checkouts', CHECKOUT => 'checkouts', RENEWAL => 'checkouts' },
    reserves    => { HOLDDGST => 'holds' },
);

# How many records of a patron to preview combined notices with by default
my $DEFAULT_COMBINED = 3;

=head2 Class methods

=head3 combines

    my $combines = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Preview->combines( $module, $code );

Whether the notice is sent once per item, the notices for several items being
combined into one message (e.g. CHECKOUT, when items are checked out before the
first notice is sent). Those can be previewed with several items.

=cut

sub combines {
    my ( $class, $module, $code ) = @_;
    return ( $COMBINED{ $module // q{} } && $COMBINED{$module}->{ $code // q{} } ) ? 1 : 0;
}

=head3 combine_letters

    my $letter = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Preview->combine_letters( \@letters );

Combines the letters prepared for each item into one, as C4::Message->append
does for queued notices: the content of each letter is split into a header, a
body and a footer by lines of ----, and the bodies of all the letters are put
between the header and the footer of the last one. Everything else, like the
title, is taken from the first letter: append only changes the content of the
message queued for it.

=cut

sub combine_letters {
    my ( $class, $letters ) = @_;

    my @letters = grep { defined && ref } @{ $letters || [] };
    return unless @letters;
    return $letters[0] if @letters == 1;

    my @metadata = map { C4::Message::_metadata($_) } @letters;
    return {
        %{ $letters[0] },
        content => join(
            q{}, ( $metadata[-1]->{header} // q{} ), ( map { $_->{body}->[0] // q{} } @metadata ),
            ( $metadata[-1]->{footer} // q{} )
        ),
    };
}

=head3 inputs

    my $kinds = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Preview->inputs( $module, $code );

Returns an arrayref of the kinds of records (e.g. 'patron', 'basket') the
notice can be previewed with: those of the single objects it receives (lists,
like the orders of a basket, come from them), and those its values are taken
from (e.g. the OAI server of OAI_HARVEST_REPORT). Notices that are not known
are previewed with a patron and an item.

=cut

sub inputs {
    my ( $class, $module, $code ) = @_;
    my %classes = map { $_ => 1 } _received_classes( $module, $code, { single => 1 } );
    return [ map { $_->{kind} } grep { ( $_->{input} // 1 ) && $classes{ $_->{class} } } @RECORDS ];
}

=head3 record_kinds

    my $kinds = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Preview->record_kinds;

Returns an arrayref of the kinds of records notices can be previewed with

=cut

sub record_kinds {
    return [ map { $_->{kind} } grep { $_->{input} // 1 } @RECORDS ];
}

=head3 find_record

    my $basket = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Preview->find_record( 'basket', $basketno );

Returns the record of the kind I<$kind> staff know by I<$value>: a patron by
their card number or username, an item by its barcode, a vendor or an OAI
server by its id or name, other records by their id. Returns undef if there is
none.

=cut

sub find_record {
    my ( $class, $kind, $value ) = @_;

    my ($record) = grep { $_->{kind} eq $kind } @RECORDS;
    return unless $record && defined $value && $value ne q{};
    return $record->{find}->($value) if $record->{find};

    my $set_class = _set_class( $record->{class} ) or return;
    return eval { $set_class->find($value) };
}

=head3 new

    my $preview = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Preview->new(
        { module => $module, code => $code, records => { patron => $patron, basket => $basket } } );

I<records> are the records to preview the notice with, by kind (see
L</inputs>), all optional. The records related to them are used too (e.g. the
vendor of a basket). I<patron> and I<item> can also be given on their own.
Without a patron, a notice receiving one is previewed with a sample patron,
one with checkouts if any.

Notices that combine items (see L</combines>) can be given several I<items>
(an arrayref of Koha::Item), see L</letter_params_list>.

=cut

sub new {
    my ( $class, $params ) = @_;

    my %records = %{ $params->{records} || {} };
    $records{patron} //= $params->{patron} if $params->{patron};
    $records{item}   //= $params->{item}   if $params->{item};

    my $self = bless {
        module  => $params->{module} // q{},
        code    => $params->{code}   // q{},
        given   => {%records},
        items   => $params->{items},
        records => \%records,
        notes   => [],
        objects => {},
    }, $class;

    $self->_add_related_records;
    $self->{patron} = $records{patron};
    $self->{item}   = $records{item};

    if ( !$self->{patron} && grep { $_ eq 'Koha::Patron' } _received_classes( $self->{module}, $self->{code} ) ) {
        $self->{patron} = Koha::Patrons->search(
            { 'issues.issue_id' => { '!=' => undef } },
            { join              => 'issues', rows => 1 }
            )->next
            || Koha::Patrons->search( {}, { rows => 1 } )->next;
        $self->_note( 'sample_patron', $self->{patron} ? $self->{patron}->borrowernumber : undef );
        $records{patron} = $self->{patron};
    }

    return $self;
}

=head3 letter_params

    my $params = $preview->letter_params;

Returns the I<objects>, I<substitute> and I<repeat> parameters of
C4::Letters::GetPreparedLetter to preview the notice with.

=cut

sub letter_params {
    my ($self) = @_;

    return $self->{letter_params} if $self->{letter_params};

    my $variables = _variables( $self->{module}, $self->{code} );
    my $bespoke   = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables->bespoke_for_notice(
        $self->{module},
        $self->{code}, { strict => 1 }
    ) // { tables => [qw( borrowers branches items biblio biblioitems issues )], tokens => [] };

    # Variables of different kinds for different codes of the module (e.g. for
    # a custom code): use the object usually known by that name
    my %usual = map { $_->{singular} => { kind => 'object', class => $_->{module} } }
        values %{ Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::TableConfig::tt_table_config() };

    my ( %objects, %substitute );
    for my $name ( sort keys %$variables ) {
        my $type = $variables->{$name};
        if ( $type->{kind} eq 'unknown' && $usual{$name} && can_load( modules => { $usual{$name}->{class} => undef } ) )
        {
            $type = { kind => 'object', class => $usual{$name}->{class}->object_class };
        }
        my $kind = $type->{kind};
        if ( $kind eq 'object' ) {
            my $object = $self->_object_for( $name, $type->{class} );
            $objects{$name} = $object if $object;
        } elsif ( $kind eq 'objects' || $kind eq 'array_of_objects' ) {

            # Lists of objects are described by the class of their objects
            my $set_class = $kind eq 'objects' ? $type->{class} : _set_class( $type->{class} );
            my $set       = $self->_objects_for( $name, $set_class );
            next unless $set;
            $objects{$name} = $kind eq 'objects' ? $set : [ $set->as_list ];
        } elsif ( $kind eq 'hash' ) {
            $substitute{$name} = {};
            $self->_note( 'no_data', $name );
        } elsif ( $kind eq 'array_of_hashes' ) {
            $substitute{$name} = [];
            $self->_note( 'no_data', $name );
        } elsif ( my $value = $self->_value_from( $type->{from} ) ) {

            # A value of a record, e.g. the name of an OAI server
            $substitute{$name} = $value->{value};
        } else {
            $substitute{$name} = "[$name]";
            $self->_note( 'placeholder', $name );
        }
    }

    # The bespoke syntax gets the same records, passed as tables as the code
    # sending the notice does: GetPreparedLetter substitutes their columns for
    # <<table.column>>, formatted (e.g. dates). The plugins adding content to
    # notices (notices_content hook) may use them too (e.g. the hold of a HOLD
    # notice). Template Toolkit still gets the objects, which take precedence.
    my %tables;
    my $config = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::TableConfig::tt_table_config();
    for my $table ( @{ $bespoke->{tables} } ) {
        my $tt_name = $config->{$table} && $config->{$table}->{singular};
        my $object  = $tt_name          && $objects{$tt_name};
        $object //= $self->_object_for( $tt_name, $config->{$table}->{module}->object_class )
            if $tt_name && can_load( modules => { $config->{$table}->{module} => undef } );
        next unless $object && ref $object && $object->can('unblessed');
        my $columns = $object->unblessed;

        # As the senders do: the key of tables looked up by a foreign key
        # (e.g. the itemnumber of issues), else the record
        my $fk = $config->{$table} && $config->{$table}->{fk};
        $tables{$table} = $fk && !ref $fk ? $columns->{$fk} : $columns;
    }
    for my $token ( @{ $bespoke->{tokens} } ) {
        next if exists $substitute{$token};
        $substitute{$token} = $token eq 'items.content' ? $self->_items_content : "[$token]";
    }

    # GetPreparedLetter does not process notices without any data: notices whose
    # records are all missing are previewed without them
    $substitute{_preview} = 1;

    $self->{objects}       = \%objects;
    $self->{letter_params} = {

        # Given as the senders do, for the plugins adding content (e.g. to HOLD notices only)
        module      => $self->{module},
        letter_code => $self->{code},
        objects     => \%objects,
        tables      => \%tables,
        substitute  => \%substitute,
        repeat      => scalar $self->_repeat,
    };
    return $self->{letter_params};
}

=head3 letter_params_list

    my $params_list = $preview->letter_params_list;
    my @letters = map { C4::Letters::GetPreparedLetter( letter => {%$letter}, %$_ ) } @$params_list;
    my $letter  = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Preview->combine_letters( \@letters );

Returns an arrayref of the parameters of C4::Letters::GetPreparedLetter to
preview the notice with: one for each item for notices that combine items (see
L</combines>), the items given or the patron's (e.g. their checkouts, at most
3), else only L</letter_params>.

=cut

sub letter_params_list {
    my ($self) = @_;

    return $self->{letter_params_list} if $self->{letter_params_list};

    my @items = $self->combines( $self->{module}, $self->{code} ) ? $self->_combined_items : ();
    if ( @items < 2 ) {
        return $self->{letter_params_list} = [ $self->letter_params ];
    }

    my @list;
    for my $item (@items) {
        my $preview = ( ref $self )->new(
            {
                module  => $self->{module},
                code    => $self->{code},
                records => { %{ $self->{given} }, patron => $self->{patron}, item => $item },
            }
        );
        push @list, $preview->letter_params;
        $self->_note( $_->{code}, $_->{variable} ) for @{ $preview->notes };
    }
    $self->{combined} = scalar @items;
    return $self->{letter_params_list} = \@list;
}

=head3 combined

The number of items the notice is previewed with when it combines several
(see L</letter_params_list>), else 0

=cut

sub combined {
    my ($self) = @_;
    $self->letter_params_list;
    return $self->{combined} // 0;
}

=head3 notes

    my $notes = $preview->notes;

Returns an arrayref of hashrefs about the data that does not come from the
records the notice is previewed with, each with a I<code> and the I<variable>
concerned:

=over

=item sample_patron - no patron was given, an example patron is used (one with checkouts if any)

=item sample - no such record is related to the records given, a sample record is used

=item no_overdues - the patron has no overdues, their checkouts are used

=item partial - no such record is related to all the records given, one related to some is used

=item missing - no record of this kind could be found

=item placeholder - a placeholder is used for this value

=item no_data - this value is empty

=back

=cut

sub notes {
    my ($self) = @_;
    $self->letter_params;
    return $self->{notes};
}

=head3 patron

The patron the notice is previewed for

=cut

sub patron {
    my ($self) = @_;
    return $self->{patron};
}

=head2 Internal methods

=head3 _variables

    my $variables = _variables( $module, $code );

The variables the notice surely receives (as other codes of the module may use
the same names for other kinds of data), else L</_default_variables>

=cut

sub _variables {
    my ( $module, $code ) = @_;
    return Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables->for_notice( $module, $code, { strict => 1 } )
        // _default_variables();
}

=head3 _received_classes

    my @classes = _received_classes( $module, $code, { single => 1 } );

The classes of the objects the notice receives, alone or in lists (with
I<single>, alone only), and of the records its values are taken from

=cut

sub _received_classes {
    my ( $module, $code, $params ) = @_;
    my $single = $params && $params->{single};
    my %classes;
    for my $type ( values %{ _variables( $module, $code ) } ) {
        if ( my ($kind) = ( $type->{from} // q{} ) =~ m{^(\w+)\.} ) {
            my ($record) = grep { $_->{kind} eq $kind } @RECORDS;
            $classes{ $record->{class} } = 1 if $record;
        }
        next unless $type->{class};
        if ( $type->{kind} eq 'object' || ( !$single && $type->{kind} eq 'array_of_objects' ) ) {
            $classes{ $type->{class} } = 1;
        } elsif ( !$single && $type->{kind} eq 'objects' && can_load( modules => { $type->{class} => undef } ) ) {
            $classes{ $type->{class}->object_class } = 1 if $type->{class}->can('object_class');
        }
    }
    my @classes = sort keys %classes;
    return @classes;
}

=head3 _add_related_records

Adds to the records given those related to them, of the kinds the notice
receives: e.g. the vendor of a basket, the patron and the item of a hold

=cut

sub _add_related_records {
    my ($self) = @_;

    my $records  = $self->{records};
    my %received = map  { $_ => 1 } _received_classes( $self->{module}, $self->{code} );
    my @targets  = grep { $received{ $_->{class} } } @RECORDS;

    my $added = 1;
    while ($added) {
        $added = 0;
        for my $from ( grep { $records->{ $_->{kind} } } @RECORDS ) {
            for my $to ( grep { !$records->{ $_->{kind} } } @targets ) {
                my $related = _related_record( $from, $records->{ $from->{kind} }, $to ) or next;
                $records->{ $to->{kind} } = $related;
                $added = 1;
            }
        }
    }
    return;
}

=head3 _refers_to

    my $refers = _refers_to( $source, $column, $class );

Whether I<$column> of the DBIC result source I<$source> refers to the records
of I<$class> (a Koha::Object class), as one of its relationships says

=cut

sub _refers_to {
    my ( $source, $column, $class ) = @_;
    return unless $class->can('_type');

    # relationship_info gives the related source as a class or a source name,
    # depending on what is loaded: compare the source names
    return grep {
        my $relationship = $_;
        my $cond         = $source->relationship_info($relationship)->{cond};

        # Conditions can also be code, for relationships that are not on columns
        ref $cond eq 'HASH'
            && ( grep { $_ eq "self.$column" } values %$cond )
            && eval { $source->related_source($relationship)->source_name }
            eq $class->_type
    } $source->relationships;
}

=head3 _related_record

    my $related = _related_record( $from, $record, $to );

The record of the kind I<$to> related to I<$record>, of the kind I<$from>
(entries of @RECORDS): by the method I<$from> lists for it, else by the column
of I<$record> referring to it (e.g. the booksellerid of a basket)

=cut

sub _related_record {
    my ( $from, $record, $to ) = @_;

    my $related;
    if ( my $method = $from->{related} && $from->{related}->{ $to->{kind} } ) {
        $related = $record->can($method) && eval { $record->$method };
    } elsif ( $to->{fk} && $to->{fk} ne ( $from->{fk} // q{} ) && $record->can('_result') ) {
        my $source = $record->_result->result_source;

        # Only columns referring to that kind of record (e.g. not the
        # booksellerid of items, which is a free text)
        return unless _refers_to( $source, $to->{fk}, $to->{class} );
        my $value = $source->has_column( $to->{fk} ) && $record->_result->get_column( $to->{fk} );
        my $set   = defined $value && $value ne q{} && _set_class( $to->{class} );
        $related = $set && eval { $set->find($value) };
    }
    return $related && ref $related && $related->isa( $to->{class} ) ? $related : undef;
}

=head3 _value_from

    my $value = $self->_value_from('oai_server.servername');

The value of the field of a record given (or related to them), else of a sample
record of that kind, as a hashref with I<value>; undef if there is no such
record

=cut

sub _value_from {
    my ( $self, $from ) = @_;

    my ( $kind, $field ) = ( $from // q{} ) =~ m{^(\w+)\.(\w+)$} or return;
    my ($record) = grep { $_->{kind} eq $kind } @RECORDS;
    return unless $record && can_load( modules => { $record->{class} => undef } );

    my $object = $self->{records}->{$kind};
    unless ($object) {
        my $row = eval {
            Koha::Database->new->schema->resultset( $record->{class}->_type )->search( {}, { rows => 1 } )->next;
        };
        return unless $row;
        $object = $self->{records}->{$kind} = $record->{class}->_new_from_dbic($row);
        $self->_note( 'sample', $kind );
    }
    return { value => $object->_result->get_column($field) // q{} };
}

=head3 _combined_items

The items to preview a notice that combines items with: those given, else
those of the patron's records the notice is sent for (see %COMBINED)

=cut

sub _combined_items {
    my ($self) = @_;

    return @{ $self->{items} } if $self->{items} && @{ $self->{items} };
    return                     if $self->{given}->{item};

    my $patron = $self->{patron} or return;
    my $kind   = $COMBINED{ $self->{module} }->{ $self->{code} };
    my $records =
          $kind eq 'old_checkouts' ? $patron->old_checkouts->search( {}, { order_by => { -desc => 'returndate' } } )
        : $kind eq 'holds'
        ? $patron->holds->search( { itemnumber => { '!=' => undef } }, { order_by => { -desc => 'found' } } )
        : $patron->checkouts;
    return grep { defined } map { $_->item } $records->search( {}, { rows => $DEFAULT_COMBINED } )->as_list;
}

=head3 _library

The library the notice is sent with, as its senders do: the pickup library of
the hold, booking or recall (or the library of the request) it is about, the
circulation control library for checkouts, checkins and renewals, else the
patron's library, else the holding library of the item

=cut

sub _library {
    my ($self) = @_;

    my %received = map { $_ => 1 } _received_classes( $self->{module}, $self->{code} );
    for my $record ( grep { $_->{library} && $received{ $_->{class} } } @RECORDS ) {
        my $object  = $self->_object_for( $record->{kind}, $record->{class} ) or next;
        my $method  = $record->{library};
        my $library = $object->can($method) && eval { $object->$method };
        return $library if $library && ref $library && $library->isa('Koha::Library');
    }

    my $patron = $self->{patron};
    my $item   = $self->_item;
    if ( $patron && $item && $self->{module} eq 'circulation' && $COMBINED{circulation}->{ $self->{code} } ) {
        require Koha::Libraries;

        # Koha::Policy::Circulation is not in Koha 26.05, which has
        # C4::Circulation::_GetCircControlBranch instead
        my $branchcode =
            can_load( modules => { 'Koha::Policy::Circulation' => undef } )
            ? Koha::Policy::Circulation->circ_control_library( $item, $patron )
            : do { require C4::Circulation; C4::Circulation::_GetCircControlBranch( $item, $patron ) };
        my $library = Koha::Libraries->find($branchcode);
        return $library if $library;
    }

    return $patron ? $patron->library : $item && $item->holding_branch;
}

=head3 _default_variables

The variables used for notices that are not known: the patron, their library,
and the item with its record and checkout

=cut

sub _default_variables {
    return {
        borrower   => { kind => 'object', class => 'Koha::Patron' },
        branch     => { kind => 'object', class => 'Koha::Library' },
        item       => { kind => 'object', class => 'Koha::Item' },
        biblio     => { kind => 'object', class => 'Koha::Biblio' },
        biblioitem => { kind => 'object', class => 'Koha::Biblioitem' },
        checkout   => { kind => 'object', class => 'Koha::Checkout' },
    };
}

=head3 _object_for

    my $object = $self->_object_for( $name, $class );

The record of class I<$class> to use for the variable I<$name>

=cut

sub _object_for {
    my ( $self, $name, $class ) = @_;

    return unless $class && can_load( modules => { $class => undef } );

    for my $record (@RECORDS) {
        my $object = $record->{class} eq $class && $self->{records}->{ $record->{kind} };
        return $object if $object;
    }

    my $patron = $self->{patron};
    my $item   = $self->_item;
    my $object;

    if ( $class eq 'Koha::Patron' ) {
        $object = $patron;
    } elsif ( $class eq 'Koha::Library' ) {
        $object = $self->_library;
    } elsif ( $class eq 'Koha::Item' ) {
        $object = $item;
    } elsif ( $class eq 'Koha::Biblio' ) {
        $object = $item && $item->biblio;
    } elsif ( $class eq 'Koha::Biblioitem' ) {
        $object = $item && $item->biblioitem;
    } elsif ( $class eq 'Koha::Checkout' ) {
        $object = ( $item && $item->checkout ) || ( $patron && $patron->checkouts->next );
    } elsif ( $class eq 'Koha::Account::Line' ) {

        # Credits and debits are account lines, with methods for one or the other
        my $kind =
              ( $name // q{} ) eq 'credit'
            ? { credit_type_code => { '!=' => undef } }
            : { debit_type_code  => { '!=' => undef } };
        my $order = { order_by => { -desc => 'accountlines_id' } };
        $object = $patron
            && Koha::Account::Lines->search( { %$kind, borrowernumber => $patron->borrowernumber }, $order )->next;
        unless ($object) {
            $object = Koha::Account::Lines->search( $kind, $order )->next;
            $self->_note( $object ? 'sample' : 'missing', $name );
            return $object;
        }
    } elsif ( $class->can('_type') ) {
        $object = $self->_patron_record( $class->_type, $class, undef, $name );
    }

    return $object if $object;

    # A record of the kind, not related to the patron
    my $row = $class->can('_type')
        && eval { Koha::Database->new->schema->resultset( $class->_type )->search( {}, { rows => 1 } )->next };
    if ($row) {
        $self->_note( 'sample', $name );
        return $class->_new_from_dbic($row);
    }

    $self->_note( 'missing', $name );
    return;
}

=head3 _objects_for

    my $set = $self->_objects_for( $name, $class );

The records of the set class I<$class> (a Koha::Objects) to use for the
variable I<$name>

=cut

sub _objects_for {
    my ( $self, $name, $class ) = @_;

    return unless $class && can_load( modules => { $class => undef } );

    my $patron = $self->{patron};

    if ( $name eq 'overdues' && $patron ) {
        my $overdues = $patron->overdues;
        return $overdues if $overdues->count;
        my $checkouts = $patron->checkouts;
        if ( $checkouts->count ) {
            $self->_note( 'no_overdues', $name );
            return $checkouts;
        }
    }

    my $object_class = $class->can('object_class') && $class->object_class;
    my $set =
           $object_class
        && can_load( modules => { $object_class => undef } )
        && $self->_patron_record( $object_class->_type, $object_class, $class );
    return $set if $set && $set->count;

    $set = $class->search( {}, { rows => 3 } );
    if ( $set->count ) {
        $self->_note( 'sample', $name );
        return $set;
    }

    $self->_note( 'missing', $name );
    return;
}

=head3 _patron_record

    my $record = $self->_patron_record( $source_name, $object_class, undef, $name );
    my $set    = $self->_patron_record( $source_name, $object_class, $set_class );

The first record of I<$object_class> related to the records the notice is
previewed with, when its table has a column referring to one of them (e.g.
the basketno of the orders of a basket, the borrowernumber of the holds of a
patron, the itemnumber or biblionumber of those of an item). With
I<$set_class>, all of them, as a set of that class.

=cut

sub _patron_record {
    my ( $self, $source_name, $object_class, $set_class, $name ) = @_;

    my $source = eval { Koha::Database->new->schema->source($source_name) } or return;
    my $item   = $self->_item;

    # The records chosen for this notice (e.g. a basket) first, then the
    # patron's, the item's and its record's
    my %value_of = (
        borrowernumber => $self->{patron} && $self->{patron}->borrowernumber,
        itemnumber     => $item           && $item->itemnumber,
        biblionumber   => $item           && $item->biblionumber,
    );
    my @columns = qw( borrowernumber itemnumber biblionumber );
    for my $record ( reverse grep { $_->{fk} } @RECORDS ) {
        my $object = $self->{records}->{ $record->{kind} } or next;
        next if exists $value_of{ $record->{fk} };
        $value_of{ $record->{fk} } = $object->_result->id;
        unshift @columns, $record->{fk};
    }

    my @usable = grep { $source->has_column($_) && $value_of{$_} } @columns;
    return unless @usable;

    # Lists are those of the first record (e.g. the checkouts of the patron)
    return $set_class->search( { $usable[0] => $value_of{ $usable[0] } } ) if $set_class;

    # The latest record related to all of them if any (e.g. the hold of the
    # patron on the item), else to the first one, with a note
    my $rs       = Koha::Database->new->schema->resultset($source_name);
    my @order    = map { { -desc => $_ } } $rs->result_source->primary_columns;
    my @searches = (
        { map { $_ => $value_of{$_} } @usable },
        map {
            { $_ => $value_of{$_} }
        } @usable
    );
    for my $i ( 0 .. $#searches ) {
        my $row = $rs->search( $searches[$i], { order_by => \@order, rows => 1 } )->next or next;
        $self->_note( 'partial', $name ) if $i > 0 && @usable > 1 && defined $name;
        return $object_class->_new_from_dbic($row);
    }
    return;
}

=head3 _item

The item given, else an item of the record of the records given (e.g. of a
hold on a record), else the item of the first checkout of the patron

=cut

sub _item {
    my ($self) = @_;
    return $self->{item} if $self->{item};

    # An item of the record of a hold, booking... given without item, before
    # the items of the patron's checkouts, which are not related to it
    if ( my $biblio = $self->{records}->{biblio} ) {
        $self->{item} = $biblio->items->search( {}, { rows => 1 } )->next;
        return $self->{item} if $self->{item};
    }
    my $checkout = $self->{patron} && $self->{patron}->checkouts->next;
    $self->{item} = $checkout->item if $checkout;
    return $self->{item};
}

=head3 _items

The items listed in notices, as for overdue notices: the overdues of the
patron, else their checkouts

=cut

sub _items {
    my ($self)    = @_;
    my $patron    = $self->{patron} or return;
    my $checkouts = $patron->overdues->count ? $patron->overdues : $patron->checkouts;
    return map { $_->item } $checkouts->as_list;
}

=head3 _items_content

The value of <<items.content>>: a line for each item, as for overdue notices

=cut

sub _items_content {
    my ($self) = @_;
    my @fields = qw( date_due title barcode author itemnumber );
    return join q{}, map {
        my $item     = $_;
        my $checkout = $item->checkout;
        C4::Letters::get_item_content(
            {
                item => {
                    %{ $item->unblessed },
                    %{ $item->biblio->unblessed },
                    ( $checkout ? %{ $checkout->unblessed } : () ),
                },
                item_content_fields => \@fields,
            }
        );
    } $self->_items;
}

=head3 _repeat

The records repeated in <item>...</item> for notices listing items

=cut

sub _repeat {
    my ($self) = @_;

    my $repeatable =
        Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Checks->new(
        { module => $self->{module}, code => $self->{code} } )->repeatable_content;
    return unless $repeatable && @{ $repeatable->{tags} };

    my @records = map {
        my $item     = $_;
        my $checkout = $item->checkout;
        {
            biblio      => $item->biblionumber,
            biblioitems => $item->biblionumber,
            items       => $item->unblessed,
            ( $checkout ? ( issues => $item->itemnumber ) : () ),
        }
    } $self->_items;

    return { map { $_ => \@records } @{ $repeatable->{tags} } };
}

=head3 _set_class

The Koha::Objects class of the objects of class I<$object_class>

=cut

sub _set_class {
    my ($object_class) = @_;
    return unless can_load( modules => { $object_class => undef } ) && $object_class->can('_type');
    my $result_class = 'Koha::Schema::Result::' . $object_class->_type;
    return $result_class->koha_objects_class
        if can_load( modules => { $result_class => undef } ) && $result_class->can('koha_objects_class');
    my $set_class = $object_class . 's';
    return can_load( modules => { $set_class => undef } ) ? $set_class : undef;
}

=head3 _note

Adds a note about the data used for a variable, once

=cut

sub _note {
    my ( $self, $code, $variable ) = @_;
    return if grep { $_->{code} eq $code && ( $_->{variable} // q{} ) eq ( $variable // q{} ) } @{ $self->{notes} };
    push @{ $self->{notes} }, { code => $code, variable => $variable };
    return;
}

1;
