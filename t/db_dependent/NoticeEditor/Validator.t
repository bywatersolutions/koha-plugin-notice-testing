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
use Test::More tests => 8;

use YAML::XS;

use C4::Context;
use Koha::Database;
use Koha::Schema::Result::Borrower;

use_ok('NoticeEditor::Validator');

sub problems {
    my ( $module, $code, $content ) = @_;
    my $validator = NoticeEditor::Validator->new( { module => $module, code => $code } );
    return [ map { join ' ', $_->{type}, $_->{variable} // $_->{block}, $_->{suggestion} ? "-> $_->{suggestion}" : () }
            @{ $validator->check_variables($content) } ];
}

subtest 'Variables passed to the notice' => sub {
    plan tests => 4;

    is_deeply(
        problems( 'patron_slip', 'MYSLIP', '[% borrower.firstname %] [% branch.branchname %] [% today %]' ), [],
        'Passed variables and globals are accepted'
    );
    is_deeply(
        problems( 'patron_slip', 'MYSLIP', '[% patron.firstname %] [% total %] [% "Dear $title" %]' ),
        [ 'unknown_variable patron -> borrower', 'unknown_variable total', 'unknown_variable title' ],
        'Variables not passed are reported, with a suggestion when one holds the same kind of object'
    );
    is_deeply(
        problems( 'patron_slip', 'MYSLIP', '[% Branches.GetName( patron.branchcode ) %]' ),
        [ 'missing_plugin Branches', 'unknown_variable patron -> borrower' ],
        'Plugins used without USE and variables in method arguments are reported'
    );
    is_deeply(
        problems(
            'patron_slip', 'MYSLIP',
            '[% USE Branches %][% SET p = borrower %][% p.firstname %][% MACRO hi BLOCK %]hi[% END %][% hi %]'
                . '[% FOREACH x IN [1, 2] %][% x %][% loop.count %][% END %][% Branches.GetName( borrower.branchcode ) %]'
        ),
        [],
        'Variables defined by the template are accepted'
    );
};

subtest 'Fields and methods of objects' => sub {
    plan tests => 5;

    SKIP: {
        skip 'No checkouts relationship for patrons in this Koha version', 1
            unless Koha::Schema::Result::Borrower->has_relationship('checkouts');
        is_deeply(
            problems(
                'patron_slip', 'MYSLIP', '[% borrower.checkouts.next.date_due %][% borrower.checkouts.next.anything %]'
            ),
            ['unknown_method borrower.checkouts.next.anything'],
            'Sets returned by relationships are followed to their objects'
        );
    }
    is_deeply(
        problems( 'patron_slip', 'MYSLIP', '[% borrower.firstnme %][% borrower.library.branchnme %]' ),
        [ 'unknown_method borrower.firstnme', 'unknown_method borrower.library.branchnme' ],
        'Unknown fields are reported, following relationships to the related object'
    );
    is_deeply(
        problems( 'patron_slip', 'MYSLIP', '[% borrower.account.balance %][% borrower.account.anything %]' ),
        [], 'Results of methods that are not relationships are not checked'
    );
    is_deeply(
        problems(
            'circulation', 'ODUE',
            '[% FOREACH o IN overdues %][% o.item.biblio.title %][% o.item.biblio.not_a_field %][% END %][% overdues.count %]'
        ),
        ['unknown_method o.item.biblio.not_a_field'],
        'Loop variables have the type of the elements of the list'
    );
    is_deeply(
        problems( 'patron_slip', 'MYSLIP', '[% SET lib = borrower.library %][% lib.branchnme %]' ),
        ['unknown_method lib.branchnme'], 'Variables set from an object have its type'
    );
};

subtest 'Severity and lines' => sub {
    plan tests => 1;

    my $validator = NoticeEditor::Validator->new( { module => 'patron_slip', code => 'MYSLIP' } );
    my $problems  = $validator->check_variables(
              "[% IF ( patron ) %]\n[% patron.firstname %]\n[% END %]\n[% total | \$Price %] [% borrower.firstnme %]\n"
            . "[% Branches.GetName( borrower.branchcode ) %][% PROCESS nope %]" );
    is_deeply(
        [
            map {
                sprintf '%s %s %s: %s', $_->{severity}, $_->{type}, $_->{variable} // $_->{block}, join ',',
                    @{ $_->{lines} }
            } @$problems
        ],
        [
            'warning unknown_variable patron: 1,2',
            'error missing_plugin Price: 4',
            'warning unknown_variable total: 4',
            'error unknown_method borrower.firstnme: 4',
            'warning missing_plugin Branches: 5',
            'error unknown_block nope: 5',
        ],
        'Problems that make the notice fail are errors, and each lists the lines it is on (not the END of IF blocks)'
    );
};

subtest 'Blocks' => sub {
    plan tests => 3;

    is_deeply(
        problems( 'patron_slip', 'MYSLIP', '[% BLOCK b %]x[% END %][% PROCESS b %][% PROCESS c %]' ),
        ['unknown_block c'], 'Blocks the template does not define are reported'
    );
    is_deeply(
        problems( 'patron_slip', 'MYSLIP', '[% PROCESS "accounts.inc" %][% PROCESS account_type_description %]' ),
        [], 'Blocks are not checked when the template processes a file, which may define them'
    );
    is_deeply(
        problems( 'patron_slip', 'MYSLIP', '[% INCLUDE "patron-title.inc" patron = borrower %]' ),
        [], 'Including a file is accepted'
    );
};

subtest 'Notices whose variables are not known' => sub {
    plan tests => 3;

    my $validator = NoticeEditor::Validator->new( { module => 'not_a_module', code => 'X' } );
    ok( !$validator->knows_variables, 'Unknown module' );
    is_deeply( $validator->check_variables('[% anything.goes %]'), [], 'No problems reported' );
    is_deeply( problems( 'patron_slip', 'MYSLIP', '[% IF %]' ), [], 'Templates that do not compile are not checked' );
};

subtest 'Sample notices' => sub {
    plan tests => 1;

    # Problems in the sample notices themselves, to be fixed separately
    my %known = map { $_ => 1 } (
        'circulation/ACCOUNT_DEBIT/print: credit',
        'circulation/HOLD_SLIP/email: reserve',
        'pos/RECEIPT/email: payment',
        'pos/RECEIPT/email: debit',
    );

    my $file = C4::Context->config('intranetdir') . '/installer/data/mysql/en/mandatory/sample_notices.yml';
    my $data = YAML::XS::LoadFile($file);

    my @unexpected;
    for my $table ( @{ $data->{tables} } ) {
        for my $notice ( @{ $table->{letter}->{rows} || [] } ) {
            my $validator =
                NoticeEditor::Validator->new( { module => $notice->{module}, code => $notice->{code} } );
            my $content = join "\n", @{ $notice->{content} };
            for my $problem ( @{ $validator->check_variables($content) } ) {
                my $name = $problem->{variable} // $problem->{block};
                next if $name eq 'LibraryName';
                my $key = sprintf '%s/%s/%s: %s', $notice->{module}, $notice->{code},
                    $notice->{message_transport_type}, $name;
                push @unexpected, $key unless $known{$key};
            }
        }
    }
    is_deeply( \@unexpected, [], 'Sample notices only use variables they receive' );
};
