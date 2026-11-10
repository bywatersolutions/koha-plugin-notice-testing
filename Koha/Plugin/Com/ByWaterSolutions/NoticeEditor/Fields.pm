package Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Fields;

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

use C4::Context;
use Koha::Database;
use Koha::Patron;
use Koha::Patron::Attribute::Types;
use Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Checks;
use Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::TableConfig;
use Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables;

=head1 NAME

Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Fields - The fields the notice editor offers to insert in a notice

=head1 DESCRIPTION

A copy of the code building the field list in tools/letter.pl (Koha bugs 36588
and 39716), for Koha versions without it. Keep them in sync.

=head1 API

=head2 Class methods

=head3 for_notice

    my $fields = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Fields->for_notice( $module, $code );

Returns a hashref with:

=over

=item fields

The fields to offer, each a hashref with the I<text> to show, the I<syntax>
it can be inserted with ('tt', 'bespoke' or 'both'), and the I<tt>, I<value>
(for <<value>>) or I<bespoke> text to insert. I<use> names the Template Toolkit
plugin a field needs, and I<fallback> marks the fields only the bespoke syntax
can use in the notice.

=item insert_syntaxes

The syntaxes the notice can use: I<tt>, I<bespoke>, and I<mixed> (Template
Toolkit, bespoke where needed).

=item only_bespoke

The names of the tables only the bespoke syntax can use, for I<mixed>.

=back

=cut

sub for_notice {
    my ( $class, $module, $code ) = @_;

    $module //= q{};

    my $field_selection = [ repeatable_content_fields( $module, $code ) ];

    # The fields each syntax can use, from the data the notice receives
    my $tt_variables =
        Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables->for_notice( $module, $code, { strict => 1 } );
    my $bespoke = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables->bespoke_for_notice(
        $module, $code,
        { strict => 1 }
    );
    my %insert_syntaxes;
    my $only_bespoke = [];
    if ( $tt_variables && $bespoke ) {
        my $repeatable = $code
            && Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Checks->new( { module => $module, code => $code } )
            ->repeatable_content;
        push @{$field_selection}, tt_variable_fields( $tt_variables, $repeatable ? $repeatable->{loop} : undef );
        push @{$field_selection}, bespoke_fields($bespoke);
        %insert_syntaxes = (
            tt      => %$tt_variables                                         ? 1 : 0,
            bespoke => ( @{ $bespoke->{tables} } || @{ $bespoke->{tokens} } ) ? 1 : 0,
        );

        # Some data is only available to the bespoke syntax: insert Template
        # Toolkit where possible, and the bespoke syntax for that data
        if ( $insert_syntaxes{tt} && $insert_syntaxes{bespoke} && @{ $bespoke->{only_bespoke} } ) {
            %insert_syntaxes = ( mixed => 1, bespoke => 1 );
            $only_bespoke =
                [ map { ( get_columns_for($_) )[0]->{text} =~ s/^-+|-+$//gr } @{ $bespoke->{only_bespoke} } ];
        }
    } else {

        # Not known: offer the fields usually available to the notices of the module
        if ( $module eq 'members' and $code and $code eq 'VIRTUALCARD' ) {
            push @{$field_selection}, { value => '', text => '---VIRTUALCARD---' },
                { value => 'my_image',   text => 'my_image',   tt => '[% my_image %]' },
                { value => 'my_barcode', text => 'my_barcode', tt => '[% my_barcode %]' };
        }
        push @{$field_selection}, add_fields('branches');
        if ( $module eq 'reserves' ) {
            push @{$field_selection}, add_fields( 'borrowers', 'reserves', 'biblio', 'biblioitems', 'items' );
        } elsif ( $module eq 'acquisition' ) {
            push @{$field_selection}, add_fields( 'aqbooksellers', 'aqorders', 'biblio', 'items' );
        } elsif ( $module eq 'claimacquisition' || $module eq 'orderacquisition' ) {
            push @{$field_selection}, add_fields( 'aqbooksellers', 'aqbasket', 'aqorders', 'biblio', 'biblioitems' );
        } elsif ( $module eq 'claimissues' ) {
            push @{$field_selection}, add_fields( 'aqbooksellers', 'serial', 'subscription', 'biblio', 'biblioitems' );
        } elsif ( $module eq 'patron_slip' ) {
            push @{$field_selection}, add_fields('borrowers');
        } elsif ( $module eq 'serial' ) {
            push @{$field_selection},
                add_fields( 'branches', 'biblio', 'biblioitems', 'borrowers', 'subscription', 'serial' );
        } elsif ( $module eq 'suggestions' ) {
            push @{$field_selection}, add_fields( 'suggestions', 'borrowers', 'biblio' );
        } elsif ( $module eq 'bookings' ) {
            push @{$field_selection}, add_fields( 'borrowers', 'bookings', 'biblio', 'biblioitems', 'items' );
        } else {
            push @{$field_selection}, add_fields( 'biblio', 'biblioitems' ),
                add_fields('items'),
                { value => 'items.content', text => 'items.content' },
                { value => 'items.fine',    text => 'items.fine' },
                add_fields('borrowers');
            if ( $module eq 'circulation' ) {
                push @{$field_selection}, add_fields( 'additional_contents', 'recalls' );

            }

            if ( $module eq 'circulation' and $code and ( $code eq "CHECKIN" or $code eq "CHECKINSLIP" ) ) {
                push @{$field_selection}, add_fields('old_issues');
            } else {
                push @{$field_selection}, add_fields('issues');
            }

            if ( $module eq 'circulation' and $code and $code =~ /^AR_/ ) {
                push @{$field_selection}, add_fields('article_requests');
            }

            if ( $module eq 'members' and $code and $code eq 'PROBLEM_REPORT' ) {
                push @{$field_selection}, add_fields('problem_reports');
            }

            if ( $module eq 'ill' ) {
                push @{$field_selection}, add_fields('illrequests');
            }
        }
        %insert_syntaxes = ( tt => 1, bespoke => 1 );
    }
    %insert_syntaxes = ( tt => 1, bespoke => 1 ) unless grep { $_ } values %insert_syntaxes;

    push @{$field_selection}, plugin_content_fields( $module, $code );
    push @{$field_selection}, tt_plugin_fields();

    # Fields without an explicit syntax can be inserted with the syntaxes they have a value for
    for my $field (@$field_selection) {
        $field->{syntax} //=
              $field->{tt} && ( $field->{value} || $field->{bespoke} ) ? 'both'
            : $field->{tt}                                             ? 'tt'
            : ( $field->{value} || $field->{bespoke} )                 ? 'bespoke'
            :                                                            'both';
    }

    return {
        fields          => $field_selection,
        insert_syntaxes => \%insert_syntaxes,
        only_bespoke    => $only_bespoke,
    };
}

=head2 Internal functions

The field lists, as built by tools/letter.pl

=cut

sub add_fields {
    my @tables = @_;
    my @fields = ();

    for my $table (@tables) {
        push @fields, get_columns_for($table);

    }
    return @fields;
}

sub get_columns_for {
    my $table = shift;

    # FIXME untranslatable
    my %column_map = (
        aqbooksellers => '---BOOKSELLERS---',
        aqorders      => '---ORDERS---',
        serial        => '---SERIALS---',
        reserves      => '---HOLDS---',
        suggestions   => '---SUGGESTIONS---',
    );
    my @fields = ();
    if ( exists $column_map{$table} ) {
        push @fields, {
            value => q{},
            text  => $column_map{$table},
        };
    } else {
        my $tlabel = '---' . uc $table;
        $tlabel .= '---';
        push @fields, {
            value => q{},
            text  => $tlabel,
        };
    }

    # Tables the notices fetch from another table (see C4::Letters::_parseletter_sth)
    my %columns_from = (
        credits   => 'accountlines',
        debits    => 'accountlines',
        opac_news => 'additional_contents_localizations',
    );
    my $sql = sprintf "SHOW COLUMNS FROM %s", $columns_from{$table} // $table;    # TODO not db agnostic
    my $table_prefix = $table . q|.|;
    my $tt_object =
        Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::TableConfig::tt_table_config()->{$table}->{singular};
    my $rows = C4::Context->dbh->selectall_arrayref( $sql, { Slice => {} } );
    for my $row ( @{$rows} ) {
        next
            if $row->{'Field'} eq 'timestamp'
            ; # this is really an irrelevant field and there may be other common fields that should be excluded from the list
        next
            if $row->{'Field'} eq 'password'
            ; # passwords can no longer be shown in notices so the password field should be removed as a template option
        push @fields, {
            value => $table_prefix . $row->{Field},
            text  => $table_prefix . $row->{Field},
            ( $tt_object ? ( tt => "[% $tt_object.$row->{Field} %]" ) : () ),
        };
    }
    push @fields, patron_attribute_fields() if $table eq 'borrowers';
    return @fields;
}

# Fields for the patron attributes, as borrower.extended_attribute_values in
# Template Toolkit (a loop for repeatable attribute types)
sub patron_attribute_fields {
    my @fields;

    # Koha::Patron->extended_attribute_values is added by Koha bug 30657
    my $has_attribute_values = Koha::Patron->can('extended_attribute_values');
    my $attribute_types      = Koha::Patron::Attribute::Types->search( {}, { order_by => 'code' } );
    while ( my $at = $attribute_types->next ) {

        # Codes that are not valid TT identifiers are looked up with the hash 'item' method
        my $tt_code = $at->code =~ /^[A-Za-z_]\w*$/ ? $at->code : sprintf( q{item('%s')}, $at->code =~ s/'/\\'/gr );
        push @fields, {
            value => "borrower-attribute:" . $at->code,
            text  => "attribute:" . $at->code,
            tt    => !$has_attribute_values
            ? sprintf( q{[%% borrower.get_extended_attribute('%s').attribute %%]}, $at->code =~ s/'/\\'/gr )
            : $at->repeatable
            ? "[% FOREACH value IN borrower.extended_attribute_values.$tt_code %][% value %] [% END %]"
            : "[% borrower.extended_attribute_values.$tt_code %]",
        };
    }
    return @fields;
}

# Fields inserting a whole block that is repeated once per record, for notices
# that receive a list of records (e.g. overdue notices).
sub repeatable_content_fields {
    my ( $module, $code ) = @_;

    return unless $code;

    my $repeatable =
        Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Checks->new( { module => $module, code => $code } )
        ->repeatable_content;
    return unless $repeatable;

    my @fields = ( { value => q{}, text => '---REPEATABLE CONTENT---' } );

    if ( $repeatable->{loop} eq 'overdues' ) {
        push @fields, {
            value => q{},
            text  => 'FOREACH overdue IN overdues',
            tt    => "[% FOREACH overdue IN overdues %]\n"
                . "[% overdue.item.biblio.title %], [% overdue.item.biblio.author %], [% overdue.item.barcode %], "
                . "due [% overdue.date_due | \$KohaDates %]\n"
                . "[% END %]",
        };
    } elsif ( $repeatable->{loop} eq 'checkouts' ) {
        push @fields, {
            value => q{},
            text  => 'FOREACH checkout IN checkouts',
            tt    => "[% FOREACH checkout IN checkouts %]\n"
                . "[% checkout.title %], [% checkout.author %] ([% checkout.barcode %])\n"
                . "[% END %]",
        };
    }

    push @fields, map {
        {
            value   => q{},
            text    => "<$_>...</$_>",
            bespoke => "<$_><<biblio.title>>, <<biblio.author>>, <<items.barcode>>, due <<issues.date_due>></$_>",
        }
    } @{ $repeatable->{tags} };

    return @fields;
}

# Fields for the Template Toolkit variables a notice receives: the columns of
# the objects, a loop for the lists, and the plain values. The list named
# $skip_loop, if any, is left out, when a richer loop is offered for it.
sub tt_variable_fields {
    my ( $variables, $skip_loop ) = @_;

    my ( @objects, @lists, @values );
    for my $name ( sort keys %$variables ) {
        my $type = $variables->{$name};
        my $keys = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables->keys_of($type);
        if ( my @columns = object_fields( $name, $type ) ) {
            push @objects, { value => q{}, text => "---$name---", syntax => 'tt' }, @columns;
        } elsif ( $keys && $type->{kind} eq 'hash' ) {
            push @objects, { value => q{}, text => "---$name---", syntax => 'tt' }, hash_fields( $name, $keys );
        } elsif ( $type->{kind} =~ /^(?:objects|array_of_objects|array_of_hashes)$/ ) {
            my $skip = defined $skip_loop && $name eq $skip_loop;
            push @lists, loop_field($name) unless $skip;

            # The fields of the hashes of the list, in its loop
            if ($keys) {
                my $element = loop_element($name);
                push @objects, { value => q{}, text => "---$element IN $name---", syntax => 'tt' },
                    hash_fields( $element, $keys );
            }
        } else {
            push @values, { value => q{}, text => $name, tt => "[% $name %]" };
        }
    }

    return (
        @objects,
        ( @lists  ? ( { value => q{}, text => '---LISTS---',  syntax => 'tt' }, @lists )  : () ),
        ( @values ? ( { value => q{}, text => '---VALUES---', syntax => 'tt' }, @values ) : () ),
    );
}

# The name of the loop variable for the elements of the list $name
sub loop_element {
    my ($name)   = @_;
    my ($last)   = $name =~ /(\w+)$/;
    my %singular = map { $_->{plural} => $_->{singular} }
        values %{ Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::TableConfig::tt_table_config() };
    my $element = $singular{$last} // ( $last =~ s/s$//r );
    return $element eq $last ? 'element' : $element;
}

# A loop on the list $name
sub loop_field {
    my ($name) = @_;
    my $element = loop_element($name);
    return {
        value => q{},
        text  => "FOREACH $element IN $name",
        tt    => "[% FOREACH $element IN $name %]\n\n[% END %]",
    };
}

# The columns of the object $name of type $type, if it is an object
sub object_fields {
    my ( $name, $type ) = @_;

    return
           unless $type->{kind} eq 'object'
        && $type->{class}
        && can_load( modules => { $type->{class} => undef } )
        && $type->{class}->can('_type');
    my $source = eval { Koha::Database->new->schema->source( $type->{class}->_type ) } or return;

    my @fields = map { { value => q{}, text => "$name.$_", tt => "[% $name.$_ %]" } }
        grep { $_ ne 'timestamp' && $_ ne 'password' } $source->columns;
    if ( $type->{class} eq 'Koha::Patron' ) {
        push @fields, map {
            { %$_, value => q{}, text => "$name.$_->{text}", tt => $_->{tt} =~ s/borrower\./$name./gr }
        } patron_attribute_fields();
    }
    return @fields;
}

# The keys of the hash $name: its values, then the fields of the objects,
# hashes and lists it holds
sub hash_fields {
    my ( $name, $keys ) = @_;

    my ( @values, @nested );
    for my $key ( sort keys %$keys ) {
        next if $key eq 'timestamp' || $key eq 'password';
        my $type     = $keys->{$key};
        my $path     = "$name.$key";
        my $sub_keys = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables->keys_of($type);
        if ( my @columns = object_fields( $path, $type ) ) {
            push @nested, @columns;
        } elsif ( $sub_keys && $type->{kind} eq 'hash' ) {
            push @nested, hash_fields( $path, $sub_keys );
        } elsif ( $type->{kind} =~ /^(?:objects|array_of_objects|array_of_hashes)$/ ) {
            push @nested, loop_field($path);
            push @nested, hash_fields( loop_element($path), $sub_keys ) if $sub_keys;
        } else {
            push @values, { value => q{}, text => $path, tt => "[% $path %]" };
        }
    }
    return ( @values, @nested );
}

# Fields for the bespoke <<table.column>> syntax: the columns of the tables the
# notice receives, and its other values as <<token>>
sub bespoke_fields {
    my ($bespoke) = @_;

    # Tables whose data Template Toolkit cannot reach are also offered when
    # inserting Template Toolkit, as a fallback
    my %only_bespoke = map { $_ => 1 } @{ $bespoke->{only_bespoke} || [] };

    my @fields;
    for my $table ( @{ $bespoke->{tables} } ) {

        # Only the bespoke syntax: the Template Toolkit variables are listed separately
        my @table_fields = map {
            { %$_, syntax => 'bespoke', tt => undef }
        } add_fields($table);
        if ( $only_bespoke{$table} ) {
            $_->{fallback} = 1 for @table_fields;
            $table_fields[0]->{text} .= ' (bespoke only)';
        }
        push @fields, @table_fields;
    }
    push @fields, { value => 'items.fine', text => 'items.fine', syntax => 'bespoke' }
        if grep { $_ eq 'items' } @{ $bespoke->{tables} };

    if ( @{ $bespoke->{tokens} } ) {
        push @fields, { value => q{}, text => '---VALUES---', syntax => 'bespoke' };
        push @fields, map { { value => $_, text => $_, syntax => 'bespoke' } } @{ $bespoke->{tokens} };
    }
    return @fields;
}

# Fields for the content Koha plugins add to the notice with the
# notices_content hook, as plugin_content.<namespace>: the variables of the
# content when the plugin describes them (notices_content_variables hook)
sub plugin_content_fields {
    my ( $module, $code ) = @_;

    my $names = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables->plugin_content_namespaces;
    my $content =
        Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables->plugin_content_type( $module, $code )->{keys};

    my @fields;
    for my $namespace ( sort keys %$content ) {
        my $path = "plugin_content.$namespace";
        my $keys = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables->keys_of( $content->{$namespace} );
        push @fields, { value => q{}, text => "---$path ($names->{$namespace})---", syntax => 'tt' },
            $keys ? hash_fields( $path, $keys ) : { value => q{}, text => $path, tt => "[% $path %]" };
    }
    return @fields;
}

# Template Toolkit plugins that are useful in notices, in alphabetical order,
# with examples of their methods and filter options. 'use' names the plugin the
# example needs loaded; KohaDates and Remove_MARC_punctuation are always loaded
# for notices (see C4::Letters::_process_tt).
sub tt_plugin_fields {

    # Values that come from the staff member generating the notice are only
    # available on slips: notices sent by cron jobs have none
    my $staff = '(staff slips only)';

    my @plugins = (
        {
            name     => 'AdditionalContents',
            examples => [
                [
                    'news for slips' =>
                        "[% SET news = AdditionalContents.get( category => 'news', location => 'slip', library => branch.branchcode ) %]\n"
                        . "[% FOREACH entry IN news.content %][% entry.title %]: [% entry.content %]\n[% END %]"
                ],
            ],
        },
        {
            name     => 'AuthorisedValues',
            examples => [
                [ 'staff description' => q{[% AuthorisedValues.GetByCode( 'LOC', item.location ) %]} ],
                [ 'OPAC description'  => q{[% AuthorisedValues.GetByCode( 'LOC', item.location, 1 ) %]} ],
                [
                    'description by field' =>
                        q{[% AuthorisedValues.GetDescriptionByKohaField( kohafield => 'items.location', authorised_value => item.location ) %]}
                ],
            ],
        },
        {
            name     => 'Branches',
            examples => [
                [ 'library name'                  => q{[% Branches.GetName( borrower.branchcode ) %]} ],
                [ 'library URL'                   => q{[% Branches.GetURL( borrower.branchcode ) %]} ],
                [ "logged in library name $staff" => q{[% Branches.GetLoggedInBranchname %]} ],
                [ "logged in library code $staff" => q{[% Branches.GetLoggedInBranchcode %]} ],
            ],
        },
        {
            name     => 'Categories',
            examples => [
                [ 'patron category name' => q{[% Categories.GetName( borrower.categorycode ) %]} ],
            ],
        },
        {
            name     => 'CirculationRules',
            examples => [
                [
                    'renewals remaining' =>
                        q{[% SET renewals = CirculationRules.Renewals( borrower.borrowernumber, item.itemnumber ) %]}
                        . q{[% renewals.remaining %] of [% renewals.allowed %] renewals remaining}
                ],
                [
                    'renewals used' =>
                        q{[% SET renewals = CirculationRules.Renewals( borrower.borrowernumber, item.itemnumber ) %]}
                        . q{[% renewals.count %] renewals used}
                ],
                [
                    'effective rule' =>
                        q{[% CirculationRules.Get( item.homebranch, borrower.categorycode, item.effective_itemtype, 'issuelength' ) %]}
                ],
                [
                    'rule set for these values' =>
                        q{[% CirculationRules.Search( item.homebranch, borrower.categorycode, item.effective_itemtype, 'renewalsallowed' ) %]}
                ],
            ],
        },
        {
            name     => 'Desks',
            examples => [
                [ "logged in desk name $staff" => q{[% Desks.GetLoggedInDeskName %]} ],
                [ "logged in desk id $staff"   => q{[% Desks.GetLoggedInDeskId %]} ],
            ],
        },
        {
            name     => 'ItemTypes',
            examples => [
                [ 'item type description' => q{[% ItemTypes.GetDescription( item.effective_itemtype ) %]} ],
            ],
        },
        {
            name     => 'Koha',
            examples => [
                [ 'system preference' => q{[% Koha.Preference( 'LibraryName' ) %]} ],
                [
                    'system preference with several values' =>
                        q{[% FOREACH value IN Koha.MultivaluePreference( 'PatronSelfRegistrationBorrowerMandatoryField' ) %][% value %] [% END %]}
                ],
            ],
        },
        {
            name     => 'KohaDates',
            loaded   => 1,
            examples => [
                [ 'date'                         => q{[% checkout.date_due | $KohaDates %]} ],
                [ 'date with time'               => q{[% checkout.date_due | $KohaDates with_hours => 1 %]} ],
                [ 'due date (time if not 23:59)' => q{[% checkout.date_due | $KohaDates as_due_date => 1 %]} ],
                [ 'date in ISO format'           => q{[% checkout.date_due | $KohaDates dateformat => 'iso' %]} ],
                [ 'date plus 7 days'             => q{[% checkout.date_due | $KohaDates add_days => 7 %]} ],
                [ 'today'                        => q{[% today | $KohaDates %]} ],
                [ 'time zone'                    => q{[% KohaDates.tz %]} ],
            ],
        },
        {
            name     => 'Price',
            examples => [
                [ 'amount'             => q{[% borrower.account.balance | $Price %]} ],
                [ 'amount with symbol' => q{[% borrower.account.balance | $Price with_symbol => 1 %]} ],
            ],
        },
        {
            name     => 'Registers',
            examples => [
                [ "logged in cash register name $staff" => q{[% Registers.session_register_name %]} ],
                [ "logged in cash register id $staff"   => q{[% Registers.session_register_id %]} ],
            ],
        },
        {
            name     => 'Remove_MARC_punctuation',
            loaded   => 1,
            examples => [
                [ 'remove trailing punctuation' => q{[% item.itemcallnumber | $Remove_MARC_punctuation %]} ],
            ],
        },
    );

    my @fields;
    for my $plugin ( sort { lc $a->{name} cmp lc $b->{name} } @plugins ) {
        my $name = $plugin->{name};
        push @fields, { value => q{}, text => "---PLUGIN: $name---", syntax => 'tt' };
        push @fields, { value => q{}, text => "USE $name",           tt => "[% USE $name %]" } unless $plugin->{loaded};
        push @fields, map {
            {
                value => q{},
                text  => "$name: $_->[0]",
                tt    => $_->[1],
                ( $plugin->{loaded} ? () : ( use => $name ) ),
            }
        } @{ $plugin->{examples} };
    }
    return @fields;
}

1;
