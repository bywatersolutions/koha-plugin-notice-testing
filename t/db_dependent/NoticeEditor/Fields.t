#!/usr/bin/perl

# Copyright 2024 Koha Development team
#
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

use Test::NoWarnings;
use Test::More tests => 7;
use Test::MockModule;

use t::lib::TestBuilder;

use Koha::Database;

use_ok('NoticeEditor::Fields');

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

sub texts {
    my ( $fields, $syntax ) = @_;
    return [ map { $_->{text} } grep { $_->{syntax} eq $syntax || $_->{syntax} eq 'both' } @{ $fields->{fields} } ];
}

subtest 'for_notice() Template Toolkit only' => sub {
    plan tests => 3;

    my $fields = NoticeEditor::Fields->for_notice( 'bookings', 'BOOKING_CONFIRMATION' );
    is_deeply( $fields->{insert_syntaxes}, { tt => 1, bespoke => 0 }, 'Booking notices cannot use the bespoke syntax' );
    ok( ( grep { $_ eq 'booking.start_date' } @{ texts( $fields, 'tt' ) } ), 'The booking fields are offered' );
    is( scalar @{ texts( $fields, 'bespoke' ) }, 0, 'No bespoke fields' );
};

subtest 'for_notice() both syntaxes' => sub {
    plan tests => 4;

    my $fields = NoticeEditor::Fields->for_notice( 'circulation', 'CHECKOUT' );
    is_deeply( $fields->{insert_syntaxes}, { tt => 1, bespoke => 1 }, 'CHECKOUT can use both syntaxes' );
    my ($date_due) = grep { $_->{text} eq 'checkout.date_due' } @{ $fields->{fields} };
    is( $date_due->{tt}, '[% checkout.date_due %]', 'Template Toolkit field' );
    my ($issues) = grep { $_->{text} eq 'issues.date_due' } @{ $fields->{fields} };
    is( $issues->{value}, 'issues.date_due', 'Bespoke field' );
    ok( !( grep { /^FOREACH \w+ IN overdues$/ } @{ texts( $fields, 'tt' ) } ), 'Only the variables of CHECKOUT' );
};

subtest 'for_notice() bespoke where needed' => sub {
    plan tests => 4;

    my $fields = NoticeEditor::Fields->for_notice( 'claimacquisition', 'ACQCLAIM' );
    is_deeply( $fields->{insert_syntaxes}, { mixed => 1, bespoke => 1 }, 'Claims insert TT, bespoke where needed' );
    ok( ( grep { $_ eq 'ORDERS' } @{ $fields->{only_bespoke} } ), 'The orders are only available to bespoke' );
    my ($ordernumber) = grep { $_->{text} eq 'aqorders.ordernumber' } @{ $fields->{fields} };
    ok( $ordernumber->{fallback} && !$ordernumber->{tt}, 'Bespoke only fields are a fallback, without TT' );
    ok( ( grep { $_->{text} eq '---ORDERS--- (bespoke only)' } @{ $fields->{fields} } ), 'Their heading says so' );
};

subtest 'for_notice() unknown notices' => sub {
    plan tests => 2;

    my $fields = NoticeEditor::Fields->for_notice( 'not_a_module', 'X' );
    is_deeply( $fields->{insert_syntaxes}, { tt => 1, bespoke => 1 }, 'Both syntaxes' );
    ok( ( grep { $_->{text} eq 'borrowers.firstname' } @{ $fields->{fields} } ), 'The fields usually available' );
};

subtest 'patron attributes' => sub {
    plan tests => 2;

    $schema->storage->txn_begin;

    my $type = $builder->build_object(
        { class => 'Koha::Patron::Attribute::Types', value => { code => 'NOTICEEDITOR', repeatable => 0 } } );

    my $attribute = sub {
        my ($field) = grep { ( $_->{value} // q{} ) eq 'borrower-attribute:NOTICEEDITOR' }
            @{ NoticeEditor::Fields->for_notice( 'not_a_module', 'X' )->{fields} };
        return $field->{tt};
    };

    my $patron = Test::MockModule->new('Koha::Patron');
    $patron->mock( 'extended_attribute_values', sub { } );
    is( $attribute->(), '[% borrower.extended_attribute_values.NOTICEEDITOR %]', 'Koha bug 30657 is used when available' );

    $patron->unmock('extended_attribute_values') if Koha::Patron->can('extended_attribute_values');
    no warnings qw( once redefine );
    local *Koha::Patron::can = sub { $_[1] eq 'extended_attribute_values' ? undef : UNIVERSAL::can(@_) };
    is(
        $attribute->(), q{[% borrower.get_extended_attribute('NOTICEEDITOR').attribute %]},
        'get_extended_attribute is used otherwise'
    );

    $schema->storage->txn_rollback;
};
