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

use_ok('Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Checks');

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
        return Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Checks->new( { module => $module, code => $code } )
            ->repeatable_content;
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
    plan tests => 19;

    $schema->storage->txn_begin;

    my $validate = sub {
        my ( $code, $title, $content ) = @_;
        return Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Checks->new(
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

    $problems = $validate->( 'CHECKOUT', 'Checkouts', "[% IF borrower.firstname %]Dear\n[% else %]Hello[% END %]" );
    is_deeply(
        $problems,
        [
            {
                type      => 'lowercase_directive', severity => 'warning', field => 'content', lines => [2],
                directive => 'ELSE', used => 'else'
            }
        ],
        'Lowercase directive that is read as a variable is a warning, with its line'
    );

    $problems = $validate->( 'CHECKOUT', 'Checkouts', "[% if borrower.firstname %]Dear[% End %]" );
    is_deeply(
        [ map { "$_->{type} $_->{severity} " . ( $_->{used} // q{} ) } @$problems ],
        [ 'lowercase_directive error if', 'lowercase_directive error End', 'tt_syntax error ' ],
        'Lowercase directives are errors when the template cannot be parsed, as well as the syntax error'
    );

    $problems = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Checks->new(
        {
            module  => 'not_a_module', code => 'X', title => 'Hi',
            content => "[% FOREACH c in list %]\n[% c.title if c.title %][% END %]\n[% IF x %]a[% else %]b[% END %]"
        }
    )->validate;
    is_deeply(
        [ map { "$_->{directive} @{ $_->{lines} }" } grep { $_->{type} eq 'lowercase_directive' } @$problems ],
        [ 'IN 1', 'IF 2', 'ELSE 3' ],
        'Lowercase IN of FOREACH and directives after an expression are reported'
    );

    is_deeply(
        Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Checks->new(
            {
                module  => 'not_a_module', code => 'X', title => 'Hi',
                content => "[%# if this is set %][% SET last = 1 %][% last %][% loop.last %][% \"if\" %]"
                    . "[% x IF y and not z or a mod 2 %][% INCLUDE b next = 1 %][% BLOCK b %][% END %]"
            }
        )->validate,
        [],
        'Variables, fields, strings, comments and lowercase operators are not reported'
    );

    is_deeply(
        Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Checks->new(
            {
                module  => 'catalogue', code => 'OAI_HARVEST_REPORT', title => 'Hi',
                content => "Set: [% set %] [% set | html %] [% set IF set %] [% set _ ' (' _ endpoint _ ')' %]"
            }
        )->validate,
        [],
        'A variable the notice receives with the name of a directive is not reported (the set of OAI harvests)'
    );
    is_deeply(
        [
            map { join ' ', $_->{type}, $_->{severity}, @{ $_->{lines} || [] } }
                @{ Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Checks->new(
                    {
                        module  => 'catalogue', code => 'OAI_HARVEST_REPORT', title => 'Hi',
                        content => "Set: [% set %]\n[% set x = 1 %]"
                    }
                )->validate
                }
        ],
        [ 'lowercase_directive error 2', 'tt_syntax error 2' ],
        '... but it is when it is used as the directive, even if the template cannot be parsed'
    );

    $problems = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Checks->new(
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

    $problems = $validate->(
        'ODUE', 'Overdue',
        '[%- IF overdues.count > 1 %]These items are overdue:[%- ELSE -%]This item is overdue:[%- END -%]'
    );
    is_deeply(
        [ map { $_->{type} } @$problems ], ['missing_repeatable_content'],
        'Using the list without a loop (e.g. counting) does not list the items'
    );
    is_deeply(
        $validate->( 'ODUE', 'Overdue', "[% WHILE ( o = overdues.next ) %][% o.item.barcode %][% END %]" ), [],
        'Going through the list with next is accepted'
    );
    is_deeply(
        Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Checks->new(
            {
                module  => 'circulation', code => 'ODUE', message_transport_type => 'sms', title => 'Overdue',
                content => 'You have [% overdues.count %] overdue items'
            }
        )->validate,
        [],
        'SMS templates are not required to list the items'
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
