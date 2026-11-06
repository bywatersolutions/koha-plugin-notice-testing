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
use Test::More tests => 6;

use C4::Context;

use_ok('NoticeEditor::Variables');

subtest 'for_notice() tests' => sub {
    plan tests => 7;

    my $odue = NoticeEditor::Variables->for_notice( 'circulation', 'ODUE' );
    is( $odue->{overdues}->{class}, 'Koha::Checkouts', 'Overdue notices receive overdues' );

    my $checkin = NoticeEditor::Variables->for_notice( 'circulation', 'checkin' );
    is( $checkin->{old_checkout}->{class}, 'Koha::Old::Checkout', 'Codes are case insensitive' );
    ok( $checkin->{overdues}, 'Variables of codes chosen by the library are added to every code of the module' );

    my $custom = NoticeEditor::Variables->for_notice( 'circulation', 'MY_CUSTOM_CODE' );
    ok( $custom->{credit} && $custom->{overdues}, 'Codes not listed accept the variables of the whole module' );

    my $strict = NoticeEditor::Variables->for_notice( 'circulation', 'CHECKIN', { strict => 1 } );
    ok( $strict->{old_checkout} && !$strict->{overdues}, 'strict: only the variables of a listed code' );

    $strict = NoticeEditor::Variables->for_notice( 'circulation', 'MY_CUSTOM_CODE', { strict => 1 } );
    ok(
        $strict->{overdues} && !$strict->{credit},
        'strict: the variables of the codes chosen by the library for others'
    );

    is( NoticeEditor::Variables->for_notice( 'not_a_module', 'X' ), undef, 'Unknown module' );
};

subtest 'bespoke_for_notice() tests' => sub {
    plan tests => 6;

    my $variables = 'NoticeEditor::Variables';

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

subtest 'Classes in the list of variables' => sub {
    plan tests => 1;

    my @wrong;
    for my $codes ( values %$NoticeEditor::Variables::VARIABLES ) {
        for my $variables ( values %$codes ) {
            for my $type ( values %$variables ) {
                next unless $type->{class};
                my $class = $type->{class};
                my $ok    = eval "require $class; 1";    ## no critic (ProhibitStringyEval)
                $ok &&= $type->{kind} eq 'objects' ? $class->can('object_class') : $class->can('_type');
                push @wrong, "$type->{kind} $class" unless $ok;
            }
        }
    }
    is_deeply( \@wrong, [], 'Every class exists and is an object or a set as declared' );
};

subtest 'Tables in the list of the bespoke syntax' => sub {
    plan tests => 1;

    my @wrong;
    my %columns_from = ( credits => 'accountlines', debits => 'accountlines' );
    my $dbh          = C4::Context->dbh;
    for my $codes ( values %$NoticeEditor::Variables::BESPOKE ) {
        for my $bespoke ( values %$codes ) {
            for my $table ( @{ $bespoke->{tables} } ) {
                my $real = $columns_from{$table} // $table;
                push @wrong, $table unless $dbh->selectrow_array( 'SHOW TABLES LIKE ?', undef, $real );
            }
        }
    }
    is_deeply( \@wrong, [], 'Every table exists' );
};
