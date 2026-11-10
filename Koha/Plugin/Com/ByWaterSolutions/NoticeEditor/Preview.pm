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
use Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Checks;
use Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::TableConfig;
use Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables;
use Koha::Account::Lines;
use Koha::Database;
use Koha::Patrons;

=head1 NAME

Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Preview - Data to preview notice templates with

=head1 SYNOPSIS

    my $preview = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Preview->new(
        { module => 'circulation', code => 'ODUE', patron => $patron, item => $item } );
    my $letter = C4::Letters::GetPreparedLetter( letter => $letter, %{ $preview->letter_params } );
    my $notes  = $preview->notes;

=head1 DESCRIPTION

A copy of Koha::Notice::Template::Preview (Koha bug 29490), for Koha versions
without it. Keep them in sync.

Builds the parameters of C4::Letters::GetPreparedLetter to preview a notice,
from the variables the notice receives (see Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables)
and the records of a patron, and optionally an item: their library, checkouts,
holds, account lines...

When the patron has no record of a kind, a sample record of that kind is used.
The variables that are plain values get placeholders. The I<notes> say which
data is not the patron's own.

=head1 API

=head2 Class methods

=head3 new

    my $preview = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Preview->new(
        { module => $module, code => $code, patron => $patron, item => $item } );

I<patron> (a Koha::Patron) and I<item> (a Koha::Item) are optional. Without a
patron, a patron with checkouts is used as a sample.

=cut

sub new {
    my ( $class, $params ) = @_;

    my $self = bless {
        module  => $params->{module} // q{},
        code    => $params->{code}   // q{},
        patron  => $params->{patron},
        item    => $params->{item},
        notes   => [],
        objects => {},
    }, $class;

    unless ( $self->{patron} ) {
        $self->{patron} = Koha::Patrons->search(
            { 'issues.issue_id' => { '!=' => undef } },
            { join              => 'issues', rows => 1 }
            )->next
            || Koha::Patrons->search( {}, { rows => 1 } )->next;
        $self->_note( 'sample_patron', $self->{patron} ? $self->{patron}->borrowernumber : undef );
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

    # What the notice surely receives, as other codes of the module may use the
    # same names for other kinds of data
    my $variables = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables->for_notice(
        $self->{module}, $self->{code},
        { strict => 1 }
    ) // $self->_default_variables;
    my $bespoke = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables->bespoke_for_notice(
        $self->{module},
        $self->{code}, { strict => 1 }
    ) // { tables => [qw( borrowers branches items biblio biblioitems issues )], tokens => [] };

    # Variables of different kinds for different codes of the module (e.g. a
    # code chosen by the library): use the object usually known by that name
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
        } else {
            $substitute{$name} = "[$name]";
            $self->_note( 'placeholder', $name );
        }
    }

    # The bespoke syntax gets the same records: their columns are substituted
    # for <<table.column>>, as GetPreparedLetter does for its substitute keys.
    # They are also passed as tables, as the code sending the notice does, for
    # the plugins adding content to notices (notices_content hook), which may
    # use them (e.g. the hold of a HOLD notice): Template Toolkit still gets
    # the objects, which take precedence.
    my %tables;
    my $config = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::TableConfig::tt_table_config();
    for my $table ( @{ $bespoke->{tables} } ) {
        my $tt_name = $config->{$table} && $config->{$table}->{singular};
        my $object  = $tt_name          && $objects{$tt_name};
        $object //= $self->_object_for( $tt_name, $config->{$table}->{module}->object_class )
            if $tt_name && can_load( modules => { $config->{$table}->{module} => undef } );
        next unless $object && ref $object && $object->can('unblessed');
        my $columns = $object->unblessed;
        $substitute{"$table.$_"} //= $columns->{$_} // q{} for keys %$columns;

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

=head3 notes

    my $notes = $preview->notes;

Returns an arrayref of hashrefs about the data that is not the patron's own,
each with a I<code> and the I<variable> concerned:

=over

=item sample_patron - no patron was given, an example patron is used (one with checkouts if any)

=item sample - the patron has no such record, a sample record is used

=item no_overdues - the patron has no overdues, their checkouts are used

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

    my $patron = $self->{patron};
    my $item   = $self->_item;
    my $object;

    if ( $class eq 'Koha::Patron' ) {
        $object = $patron;
    } elsif ( $class eq 'Koha::Library' ) {
        $object = $patron ? $patron->library : $item && $item->holding_branch;
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
        $object = $self->_patron_record( $class->_type, $class );
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

    my $record = $self->_patron_record( $source_name, $object_class );
    my $set    = $self->_patron_record( $source_name, $object_class, $set_class );

The first record of I<$object_class> belonging to the patron, or to the item,
when its table has a borrowernumber, itemnumber or biblionumber column. With
I<$set_class>, all of them, as a set of that class.

=cut

sub _patron_record {
    my ( $self, $source_name, $object_class, $set_class ) = @_;

    my $source = eval { Koha::Database->new->schema->source($source_name) } or return;
    my $item   = $self->_item;

    my $search =
        $source->has_column('borrowernumber') && $self->{patron} ? { borrowernumber => $self->{patron}->borrowernumber }
        : $source->has_column('itemnumber')   && $item           ? { itemnumber => $item->itemnumber }
        : $source->has_column('biblionumber') && $item           ? { biblionumber => $item->biblionumber }
        :                                                          undef;
    return unless $search;

    return $set_class->search($search) if $set_class;

    my $row = Koha::Database->new->schema->resultset($source_name)->search( $search, { rows => 1 } )->next;
    return $row && $object_class->_new_from_dbic($row);
}

=head3 _item

The item given, or the item of the first checkout of the patron

=cut

sub _item {
    my ($self) = @_;
    return $self->{item} if $self->{item};
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
