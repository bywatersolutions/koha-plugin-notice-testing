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
use Test::More tests => 6;
use Test::Mojo;

use t::lib::TestBuilder;
use t::lib::Mocks;

use Koha::CirculationRules;
use Koha::Database;
use Mojo::JSON;
use Koha::Plugin::Com::ByWaterSolutions::NoticeEditor;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

my $base = '/api/v1/contrib/' . Koha::Plugin::Com::ByWaterSolutions::NoticeEditor->new->api_namespace;

my $t = Test::Mojo->new('Koha::REST::V1');
t::lib::Mocks::mock_preference( 'RESTBasicAuth', 1 );

my $password = 'thePassword123';

sub librarian {
    my ($permission) = @_;
    my $patron = $builder->build_object( { class => 'Koha::Patrons', value => { flags => 0 } } );
    $builder->build(
        {
            source => 'UserPermission',
            value  => { borrowernumber => $patron->borrowernumber, module_bit => 13, code => $permission },
        }
    ) if $permission;
    $patron->set_password( { password => $password, skip_validation => 1 } );
    return $patron->userid;
}

subtest 'validate() permissions' => sub {
    plan tests => 6;

    $schema->storage->txn_begin;

    my $body = { module => 'circulation', code => 'CHECKOUT', templates => [] };

    $t->post_ok( "$base/validation" => json => $body )->status_is(401);

    my $userid = librarian('manage_staged_marc');
    $t->post_ok( "//$userid:$password\@$base/validation" => json => $body )->status_is(403);

    $userid = librarian('edit_notices');
    $t->post_ok( "//$userid:$password\@$base/validation" => json => $body )->status_is(200);

    $schema->storage->txn_rollback;
};

subtest 'validate() problems' => sub {
    plan tests => 13;

    $schema->storage->txn_begin;

    Koha::CirculationRules->search( { rule_name => { -like => 'overdue\_%\_notice' } } )->delete;

    my $userid = librarian('edit_notices');
    my $url    = "//$userid:$password\@$base/validation";

    $t->post_ok(
        $url => json => {
            module    => 'circulation',
            code      => 'CHECKOUT',
            templates => [
                {
                    message_transport_type => 'email', lang => 'default', title => 'Checkouts',
                    content                => '[% borrower.firstname %]'
                },
                {
                    message_transport_type => 'sms', lang => 'default', title => 'Checkouts',
                    content                => "Hello\n[% IF borrower.firstname %]Dear"
                },
                { message_transport_type => 'print', lang => 'default', title => q{}, content => q{} },
            ]
        }
        )
        ->status_is(200)
        ->json_is( '/templates/0' => { message_transport_type => 'email', lang => 'default', problems => [] } )
        ->json_is( '/templates/1/problems/0/type'     => 'tt_syntax' )
        ->json_is( '/templates/1/problems/0/severity' => 'error' )
        ->json_is( '/templates/1/problems/0/lines'    => [2] )
        ->json_hasnt( '/templates/2', 'Templates without a title and a content are not checked' );

    $t->post_ok(
        $url => json => {
            module    => 'circulation',
            code      => 'ODUE',
            templates =>
                [ { message_transport_type => 'email', lang => 'default', title => 'Overdue', content => 'Hello' } ]
        }
        )
        ->status_is(200)
        ->json_is( '/templates/0/problems/0/type'     => 'missing_repeatable_content' )
        ->json_is( '/templates/0/problems/0/severity' => 'warning' );

    $t->post_ok( $url => json => { module => 'circulation', templates => [], unknown => 1 } )->status_is(400);

    $schema->storage->txn_rollback;
};

subtest 'validate() variable problems' => sub {
    plan tests => 8;

    $schema->storage->txn_begin;

    my $userid = librarian('edit_notices');

    $t->post_ok(
        "//$userid:$password\@$base/validation" => json => {
            module    => 'patron_slip',
            code      => 'MYSLIP',
            templates => [
                {
                    message_transport_type => 'print', lang => 'default', title => 'Slip',
                    content                => "[% patron.firstname %]\n[% total %] [% borrower.firstnme %]"
                }
            ]
        }
        )
        ->status_is(200)
        ->json_is( '/templates/0/problems/0/variable'   => 'patron' )
        ->json_is( '/templates/0/problems/0/suggestion' => 'borrower' )
        ->json_is( '/templates/0/problems/1/suggestion' => undef )
        ->json_is( '/templates/0/problems/1/available'  => [ 'borrower', 'branch' ] )
        ->json_is( '/templates/0/problems/2/type'       => 'unknown_method' )
        ->json_is( '/templates/0/problems/2/class'      => 'Koha::Patron' );

    $schema->storage->txn_rollback;
};

subtest 'fields() tests' => sub {
    plan tests => 9;

    $schema->storage->txn_begin;

    $t->get_ok("$base/fields?module=bookings&code=BOOKING_CONFIRMATION")->status_is(401);

    my $userid = librarian('edit_notices');
    $t->get_ok("//$userid:$password\@$base/fields?module=bookings&code=BOOKING_CONFIRMATION")
        ->status_is(200)
        ->json_is( '/insert_syntaxes' => ['tt'] );

    $t->get_ok("//$userid:$password\@$base/fields?module=claimacquisition&code=ACQCLAIM")
        ->status_is(200)
        ->json_is( '/insert_syntaxes' => [ 'bespoke', 'mixed' ] )
        ->json_has( '/only_bespoke/0' );

    $schema->storage->txn_rollback;
};

subtest 'preview() tests' => sub {
    plan tests => 11;

    $schema->storage->txn_begin;

    my $patron = $builder->build_object( { class => 'Koha::Patrons' } );
    my $body   = {
        module                 => 'members',
        code                   => 'MEMBERSHIP_EXPIRY',
        message_transport_type => 'email',
        title                  => 'Expiry',
        content                => '<h1>Hello [% borrower.firstname %]</h1> [% branch.branchcode %]',
        is_html                => Mojo::JSON->true,
        patron                 => $patron->cardnumber,
    };

    $t->post_ok( "$base/preview" => json => $body )->status_is(401);

    my $userid = librarian('edit_notices');
    $t->post_ok( "//$userid:$password\@$base/preview" => json => $body )
        ->status_is(200)
        ->json_is( '/patron/cardnumber' => $patron->cardnumber )
        ->json_like( '/html' => qr{<h1>Hello \Q@{[ $patron->firstname ]}\E</h1> \Q@{[ $patron->branchcode ]}\E} )
        ->json_is( '/messages' => [] );

    $t->post_ok(
        "//$userid:$password\@$base/preview" => json => { %$body, patron => 'NOT_A_CARDNUMBER', is_html => Mojo::JSON->false } )
        ->status_is(200)
        ->json_is( '/messages/0/code' => 'no_patron' )
        ->json_like( '/html' => qr{^<div style="white-space: pre-wrap;">} );

    $schema->storage->txn_rollback;
};
