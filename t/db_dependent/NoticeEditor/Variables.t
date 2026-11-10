#!/usr/bin/perl

# This file is part of Koha
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
# along with Koha; if not, see <https://www.gnu.org/licenses>

use Modern::Perl;
no warnings 'once';    # The lists of the module are only read here

use Test::NoWarnings;
use Test::More tests => 9;

use Test::MockModule;
use t::lib::Mocks;

use C4::Context;

use_ok('Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables');

subtest 'for_notice() tests' => sub {
    plan tests => 7;

    my $odue = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables->for_notice( 'circulation', 'ODUE' );
    is( $odue->{overdues}->{class}, 'Koha::Checkouts', 'Overdue notices receive overdues' );

    my $checkin = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables->for_notice( 'circulation', 'checkin' );
    is( $checkin->{old_checkout}->{class}, 'Koha::Old::Checkout', 'Codes are case insensitive' );
    ok( !$checkin->{overdues}, 'A listed code only receives the variables of its entry' );

    my $custom =
        Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables->for_notice( 'circulation', 'MY_CUSTOM_CODE' );
    ok( $custom->{credit} && $custom->{overdues}, 'Codes not listed accept the variables of the whole module' );

    my $strict = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables->for_notice(
        'circulation', 'CHECKIN',
        { strict => 1 }
    );
    ok( $strict->{old_checkout} && !$strict->{overdues}, 'strict: only the variables of a listed code' );

    $strict = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables->for_notice(
        'circulation', 'MY_CUSTOM_CODE',
        { strict => 1 }
    );
    ok(
        $strict->{overdues} && !$strict->{credit},
        'strict: the variables of the codes chosen by the library for others'
    );

    is(
        Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables->for_notice( 'not_a_module', 'X' ), undef,
        'Unknown module'
    );
};

subtest 'bespoke_for_notice() tests' => sub {
    plan tests => 6;

    my $variables = 'Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables';

    is_deeply(
        $variables->bespoke_for_notice( 'bookings', 'BOOKING_CONFIRMATION', { strict => 1 } ),
        { tables => [], tokens => [], only_bespoke => [] },
        'Notices only receiving objects cannot use the bespoke syntax'
    );
    is_deeply(
        $variables->bespoke_for_notice( 'members', 'PASSWORD_RESET', { strict => 1 } ),
        { tables => [], tokens => [qw( passwordreseturl user )], only_bespoke => [] },
        'Substitute values are tokens'
    );

    my $odue = $variables->bespoke_for_notice( 'circulation', 'ODUE', { strict => 1 } );
    ok( ( grep { $_ eq 'items' } @{ $odue->{tables} } ), 'Tables of repeated records are included' );
    ok(
        ( grep { $_ eq 'items.content' } @{ $odue->{tokens} } ) && !( grep { $_ eq 'overdues' } @{ $odue->{tokens} } ),
        'Only values that print as text are tokens'
    );

    is_deeply(
        $variables->bespoke_for_notice( 'claimacquisition', 'ACQCLAIM', { strict => 1 } )->{only_bespoke},
        [qw( aqbasket aqcontacts aqorders biblio biblioitems )],
        'The claimed orders are only available to the bespoke syntax'
    );

    is( $variables->bespoke_for_notice( 'not_a_module', 'X' ), undef, 'Unknown module' );
};

subtest 'plugin_content_namespaces() tests' => sub {
    plan tests => 2;

    t::lib::Mocks::mock_config( 'enable_plugins', 0 );
    is_deeply(
        Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables->plugin_content_namespaces, {},
        'No plugins when they are disabled'
    );

    # An enabled plugin adding content to notices, and one that does not
    package Test::NoticesContent {
        sub new             { return bless {}, shift }
        sub get_metadata    { return { namespace => 'rapido', name => 'Rapido' } }
        sub notices_content { return {} }
    }

    package Test::NoContent {
        sub new          { return bless {}, shift }
        sub get_metadata { return { namespace => 'other', name => 'Other' } }
    }
    t::lib::Mocks::mock_config( 'enable_plugins', 1 );
    my $plugins = Test::MockModule->new('Koha::Plugins');
    $plugins->mock( get_enabled_plugins => sub { return ( Test::NoticesContent->new, Test::NoContent->new ) } );
    is_deeply(
        Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables->plugin_content_namespaces,
        { rapido => 'Rapido' },
        'The namespaces of the enabled plugins adding content to notices, with their names'
    );
};

subtest 'plugin_content_type() tests' => sub {
    plan tests => 4;

    # Enabled plugins adding content to notices: one describing it for HOLD
    # notices, one whose description fails, and one not describing it
    package Test::Described {
        sub new             { return bless {}, shift }
        sub get_metadata    { return { namespace => 'rapido', name => 'Rapido' } }
        sub notices_content { return {} }

        sub notices_content_variables {
            my ( $self, $params ) = @_;
            return unless $params->{letter_code} =~ /^HOLD/;
            return { title => { kind => 'scalar' } };
        }
    }

    package Test::Failing {
        sub new                       { return bless {}, shift }
        sub get_metadata              { return { namespace => 'failing', name => 'Failing' } }
        sub notices_content           { return {} }
        sub notices_content_variables { die "Failed\n" }
    }

    package Test::NotDescribed {
        sub new             { return bless {}, shift }
        sub get_metadata    { return { namespace => 'other', name => 'Other' } }
        sub notices_content { return {} }
    }
    t::lib::Mocks::mock_config( 'enable_plugins', 1 );
    my $plugins = Test::MockModule->new('Koha::Plugins');
    $plugins->mock(
        get_enabled_plugins => sub { return ( Test::Described->new, Test::Failing->new, Test::NotDescribed->new ) } );

    my $variables = 'Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables';
    my $hold      = $variables->plugin_content_type( 'reserves', 'HOLD' )->{keys};
    is_deeply(
        $hold->{rapido}, { kind => 'hash', keys => { title => { kind => 'scalar' } } },
        'The variables a plugin describes for the notice'
    );
    is_deeply(
        [ $hold->{failing}, $hold->{other} ], [ { kind => 'unknown' }, { kind => 'unknown' } ],
        'The content of plugins whose description fails or who do not describe it is not known'
    );
    my $checkout = $variables->plugin_content_type( 'circulation', 'CHECKOUT' )->{keys};
    ok( !exists $checkout->{rapido}, 'Plugins adding no content to the notice are left out' );
    ok( exists $checkout->{other},   '... but not the ones that do not describe it' );
};

subtest 'keys_of() tests' => sub {
    plan tests => 5;

    my $variables = 'Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables';

    my $branch = $variables->for_notice( 'circulation', 'SR_SLIP', { strict => 1 } )->{branch};
    my $keys   = $variables->keys_of($branch);
    ok( $keys->{name} && $keys->{items}, 'Keys of a hash' );
    my $item = $variables->keys_of( $keys->{items} );
    is( $item->{object}->{class}, 'Koha::StockRotationItem', '... and of the hashes of a list it holds' );
    ok( $variables->keys_of( $item->{branch} )->{branchname}, 'Columns of the tables of a hash are its keys' );

    my $checkout = $variables->keys_of( $variables->for_notice( 'circulation', 'DUE', { strict => 1 } )->{checkout} );
    ok( $checkout->{title} && $checkout->{barcode} && $checkout->{date_due}, '... from each of its tables' );

    is( $variables->keys_of( $variables->for_notice( 'report', 'X' )->{data} ), undef, 'Keys can be unknown' );
};

# All the types in the lists of variables, including the keys of the hashes
sub all_types {
    my @types;
    my @queue = map { values %$_ }
        map { values %$_ } values %$Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables::VARIABLES;
    while ( my $type = shift @queue ) {
        push @types, $type;
        push @queue, values %{ $type->{keys} || {} };
    }
    return @types;
}

subtest 'Classes in the list of variables' => sub {
    plan tests => 2;

    my @wrong;
    for my $type ( grep { $_->{class} } all_types() ) {
        my $class = $type->{class};
        my $ok    = eval "require $class; 1";    ## no critic (ProhibitStringyEval)
        $ok &&= $type->{kind} eq 'objects' ? $class->can('object_class') : $class->can('_type');
        push @wrong, "$type->{kind} $class" unless $ok;
    }
    is_deeply( \@wrong, [], 'Every class exists and is an object or a set as declared' );

    my $dbh = C4::Context->dbh;
    my @missing =
        grep { !$dbh->selectrow_array( 'SHOW TABLES LIKE ?', undef, $_ ) } map { @{ $_->{tables} || [] } } all_types();
    is_deeply( \@missing, [], 'Every table of a hash exists' );
};

subtest 'Tables in the list of the bespoke syntax' => sub {
    plan tests => 1;

    my @wrong;
    my %columns_from = ( credits => 'accountlines', debits => 'accountlines' );
    my $dbh          = C4::Context->dbh;
    for my $codes ( values %$Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables::BESPOKE ) {
        for my $bespoke ( values %$codes ) {
            for my $table ( @{ $bespoke->{tables} } ) {
                my $real = $columns_from{$table} // $table;
                push @wrong, $table unless $dbh->selectrow_array( 'SHOW TABLES LIKE ?', undef, $real );
            }
        }
    }
    is_deeply( \@wrong, [], 'Every table exists' );
};
