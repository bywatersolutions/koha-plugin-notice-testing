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

use Test::NoWarnings;
use Test::More tests => 9;
use Try::Tiny qw( catch try );
use YAML::XS;

use t::lib::Mocks;
use t::lib::TestBuilder;

use C4::Context;
use C4::Letters;
use Koha::Database;
use Koha::DateUtils qw( dt_from_string );

use_ok('Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Preview');

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

# A patron with an item checked out, overdue if $overdue
sub patron_with_checkout {
    my ($overdue) = @_;
    my $patron    = $builder->build_object( { class => 'Koha::Patrons' } );
    my $item      = $builder->build_sample_item;
    my $checkout  = $builder->build_object(
        {
            class => 'Koha::Checkouts',
            value => {
                borrowernumber => $patron->borrowernumber,
                itemnumber     => $item->itemnumber,
                date_due       => dt_from_string->add( days => $overdue ? -3 : 3 ),
                returndate     => undef,
            },
        }
    );
    return ( $patron, $item, $checkout );
}

sub preview {
    my ( $module, $code, $params ) = @_;
    return Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Preview->new(
        { module => $module, code => $code, %{ $params || {} } } );
}

sub note_codes {
    my ($preview) = @_;
    return [ map { "$_->{code} $_->{variable}" } grep { $_->{variable} } @{ $preview->notes } ];
}

subtest 'objects of the patron' => sub {
    plan tests => 5;

    $schema->storage->txn_begin;

    my ( $patron, $item, $checkout ) = patron_with_checkout('overdue');
    my $preview = preview( 'circulation', 'ODUE', { patron => $patron } );
    my $objects = $preview->letter_params->{objects};

    is( $objects->{borrower}->borrowernumber, $patron->borrowernumber, 'borrower is the patron' );
    is( $objects->{branch}->branchcode,       $patron->branchcode,     'branch is their library' );
    is_deeply( [ map { $_->issue_id } $objects->{overdues}->as_list ], [ $checkout->issue_id ], 'overdues are theirs' );
    is( $preview->patron->borrowernumber, $patron->borrowernumber, 'patron' );
    ok( !( grep { $_->{code} eq 'no_overdues' } @{ $preview->notes } ), 'No note about overdues' );

    $schema->storage->txn_rollback;
};

subtest 'fallbacks' => sub {
    plan tests => 4;

    $schema->storage->txn_begin;

    my ( $patron, $item, $checkout ) = patron_with_checkout();
    my $preview = preview( 'circulation', 'ODUE', { patron => $patron } );
    is_deeply(
        [ map { $_->issue_id } $preview->letter_params->{objects}->{overdues}->as_list ], [ $checkout->issue_id ],
        'Without overdues, the checkouts are used'
    );
    ok( ( grep { $_ eq 'no_overdues overdues' } @{ note_codes($preview) } ), '... with a note' );

    $preview = preview( 'members', 'PASSWORD_RESET', { patron => $patron } );
    is( $preview->letter_params->{substitute}->{passwordreseturl}, '[passwordreseturl]', 'Placeholder for values' );
    ok( ( grep { $_ eq 'placeholder passwordreseturl' } @{ note_codes($preview) } ), '... with a note' );

    $schema->storage->txn_rollback;
};

subtest 'credits and debits' => sub {
    plan tests => 2;

    $schema->storage->txn_begin;

    my $patron = $builder->build_object( { class => 'Koha::Patrons' } );
    $patron->account->add_debit( { amount => 5, type => 'MANUAL', interface => 'intranet' } );
    $patron->account->add_credit( { amount => 2, type => 'PAYMENT', interface => 'intranet' } );

    my $objects = preview( 'circulation', 'ACCOUNT_CREDIT', { patron => $patron } )->letter_params->{objects};
    ok( $objects->{credit}->is_credit, 'credit is a credit' );
    $objects = preview( 'circulation', 'ACCOUNT_DEBIT', { patron => $patron } )->letter_params->{objects};
    ok( $objects->{debit}->is_debit, 'debit is a debit' );

    $schema->storage->txn_rollback;
};

subtest 'bespoke syntax' => sub {
    plan tests => 2;

    $schema->storage->txn_begin;

    my ( $patron, $item ) = patron_with_checkout('overdue');
    my $params = preview( 'circulation', 'ODUE', { patron => $patron } )->letter_params;
    my $letter = C4::Letters::GetPreparedLetter(
        letter => { title => 'T', content => "Dear <<borrowers.firstname>>\n<<items.content>>", lang => 'default' },
        %$params,
    );
    like( $letter->{content}, qr/^Dear \Q@{[ $patron->firstname ]}\E\n/, 'Columns are substituted' );
    like( $letter->{content}, qr/\Q@{[ $item->barcode ]}\E/,             'items.content lists the items' );

    $schema->storage->txn_rollback;
};

subtest 'tables' => sub {
    plan tests => 3;

    $schema->storage->txn_begin;

    my $patron = $builder->build_object( { class => 'Koha::Patrons' } );
    my $hold   = $builder->build_object(
        { class => 'Koha::Holds', value => { borrowernumber => $patron->borrowernumber, found => undef } } );
    my $params = preview( 'reserves', 'HOLD', { patron => $patron } )->letter_params;
    is(
        $params->{tables}->{reserves}->{reserve_id}, $hold->reserve_id,
        'The records are passed as tables too, as the code sending the notice does (e.g. for plugins adding content)'
    );
    is( $params->{tables}->{borrowers}->{borrowernumber}, $patron->borrowernumber, '... for each table' );
    is_deeply(
        [ @{$params}{qw( module letter_code )} ], [ 'reserves', 'HOLD' ],
        'The module and code of the notice are given, as the senders do'
    );

    $schema->storage->txn_rollback;
};

subtest 'unknown notices and no patron' => sub {
    plan tests => 3;

    $schema->storage->txn_begin;

    my ( $patron, $item ) = patron_with_checkout();
    my $objects = preview( 'not_a_module', 'X', { patron => $patron, item => $item } )->letter_params->{objects};
    is( $objects->{borrower}->borrowernumber, $patron->borrowernumber, 'Unknown notices get the patron' );
    is( $objects->{item}->itemnumber,         $item->itemnumber,       '... and the item' );

    my $preview = preview( 'circulation', 'CHECKOUT' );
    ok(
        ( grep { $_->{code} eq 'sample_patron' } @{ $preview->notes } ) && $preview->patron,
        'A sample patron is used'
    );

    $schema->storage->txn_rollback;
};

subtest 'Every sample notice can be previewed' => sub {
    plan tests => 1;

    $schema->storage->txn_begin;

    my ($patron) = patron_with_checkout('overdue');
    t::lib::Mocks::mock_userenv( { patron => $patron } );

    my $file = C4::Context->config('intranetdir') . '/installer/data/mysql/en/mandatory/sample_notices.yml';
    my @failed;
    for my $table ( @{ YAML::XS::LoadFile($file)->{tables} } ) {
        for my $notice ( @{ $table->{letter}->{rows} || [] } ) {
            my $preview = preview( $notice->{module}, $notice->{code}, { patron => $patron } );
            local $SIG{__WARN__} = sub { };
            my $letter = try {
                C4::Letters::GetPreparedLetter(
                    letter => {
                        title   => $notice->{title},   content => join( "\n", @{ $notice->{content} } ),
                        is_html => $notice->{is_html}, lang    => 'default'
                    },
                    %{ $preview->letter_params },
                );
            } catch {
                push @failed, "$notice->{code} $notice->{message_transport_type}: $_";
            };
            push @failed, "$notice->{code} $notice->{message_transport_type}: nothing rendered"
                unless $letter || @failed;
        }
    }
    is_deeply( \@failed, [], 'All the sample notices render' );

    $schema->storage->txn_rollback;
};
