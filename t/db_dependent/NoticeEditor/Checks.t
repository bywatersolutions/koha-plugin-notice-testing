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
use Test::More tests => 4;

use t::lib::TestBuilder;

use C4::Context;
use Koha::CirculationRules;
use Koha::Database;

use_ok('NoticeEditor::Checks');

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

subtest 'repeatable_content() tests' => sub {
    plan tests => 5;

    $schema->storage->txn_begin;

    # The overdue notice triggers are circulation rules from Koha 26.11, in the overduerules table before
    my $rules = exists Koha::CirculationRules->rule_kinds->{overdue_X_notice};
    if ($rules) {
        Koha::CirculationRules->search( { rule_name => { -like => 'overdue\_%\_notice' } } )->delete;
    } else {
        C4::Context->dbh->do(q{DELETE FROM overduerules});
    }

    my $repeatable = sub {
        my ( $module, $code ) = @_;
        return NoticeEditor::Checks->new( { module => $module, code => $code } )->repeatable_content;
    };

    is_deeply(
        $repeatable->( 'circulation', 'ODUE' ),
        { loop => 'overdues', tokens => ['items.content'], tags => ['item'] },
        'ODUE expects overdues'
    );
    is_deeply(
        $repeatable->( 'circulation', 'PREDUEDGST' ),
        { loop => 'checkouts', tokens => ['items.content'], tags => [] },
        'PREDUEDGST expects checkouts'
    );
    is( $repeatable->( 'circulation', 'MY_ODUE' ), undef, 'Unused code expects nothing' );

    if ($rules) {
        Koha::CirculationRules->set_rule(
            {
                branchcode   => undef,
                categorycode => undef,
                itemtype     => undef,
                rule_name    => 'overdue_2_notice',
                rule_value   => 'MY_ODUE',
            }
        );
    } else {
        my $category = $builder->build_object( { class => 'Koha::Patron::Categories' } );
        C4::Context->dbh->do(
            q{INSERT INTO overduerules ( branchcode, categorycode, letter2 ) VALUES ( '', ?, 'MY_ODUE' )},
            undef, $category->categorycode
        );
    }
    is(
        $repeatable->( 'circulation', 'MY_ODUE' )->{loop}, 'overdues',
        'Code used by an overdue rule expects overdues'
    );
    is( $repeatable->( 'members', 'MY_ODUE' ), undef, 'Only circulation notices are checked' );

    $schema->storage->txn_rollback;
};

subtest 'validate() tests' => sub {
    plan tests => 10;

    $schema->storage->txn_begin;

    my $validate = sub {
        my ( $code, $title, $content ) = @_;
        return NoticeEditor::Checks->new(
            { module => 'circulation', code => $code, title => $title, content => $content } )->validate;
    };

    is_deeply(
        $validate->( 'CHECKOUT', 'Checkouts', '[% borrower.firstname %]' ), [],
        'Valid template has no problems'
    );

    my $problems = $validate->( 'CHECKOUT', 'Checkouts', "Hello\n[% IF borrower.firstname %]Dear" );
    is( scalar @$problems, 1, 'Unclosed IF is a problem' );
    is_deeply(
        $problems->[0],
        {
            type  => 'tt_syntax', severity => 'error', field => 'content', lines => [2],
            error => 'unexpected end of input'
        },
        '... a syntax error in the content, with its line'
    );

    $problems = $validate->( 'CHECKOUT', '[% IF borrower.firstname %]Hi', 'Hello' );
    is( $problems->[0]{field}, 'title', 'Syntax errors in the title are reported' );

    $problems = $validate->( 'CHECKOUT', 'Checkouts', "[% borrower.firstname %]\n\nDear [% borrower.surname" );
    is_deeply(
        $problems,
        [ { type => 'unclosed_tag', severity => 'warning', field => 'content', lines => [3] } ],
        'Unterminated tag is a warning, with its line'
    );

    $problems = NoticeEditor::Checks->new(
        { module => 'not_a_module', code => 'X', title => 'Hi', content => "[% x | \$NotAFilter %]" } )->validate;
    is_deeply(
        $problems,
        [
            {
                type  => 'tt_error', severity => 'error', field => 'content',
                error => 'undef error - : filter not found'
            }
        ],
        'Errors found while processing the template are reported when not explained otherwise'
    );

    $problems = $validate->( 'ODUE', 'Overdue', 'You have overdues. [% borrower.firstname %]' );
    is_deeply(
        [ map { "$_->{type} $_->{severity}" } @$problems ], ['missing_repeatable_content warning'],
        'Overdue notice without a list of items is a problem, even if the word is in plain text'
    );

    is_deeply(
        $validate->( 'ODUE', 'Overdue', "[% FOREACH o IN overdues %][% o.item.barcode %][% END %]" ), [],
        'TT overdues loop is accepted'
    );
    is_deeply( $validate->( 'ODUE', 'Overdue', "Items:\n<<items.content>>" ), [], '<<items.content>> is accepted' );
    is_deeply(
        $validate->( 'ODUE', 'Overdue', "<item><<biblio.title>>\n</item>" ), [],
        '<item> enclosing tags are accepted'
    );

    $schema->storage->txn_rollback;
};

1;
