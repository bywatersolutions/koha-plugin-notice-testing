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
use Test::More tests => 15;
use Try::Tiny qw( catch try );
use YAML::XS;

use t::lib::Mocks;
use t::lib::TestBuilder;

use C4::Context;
use C4::Letters;
use Koha::Database;
use Koha::DateUtils qw( dt_from_string output_pref );

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

subtest 'inputs and find_record' => sub {
    plan tests => 10;

    $schema->storage->txn_begin;

    my $inputs = sub { Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Preview->inputs(@_) };
    is_deeply(
        $inputs->( 'orderacquisition', 'ACQORDER' ), [qw( basket vendor )],
        'A basket order is previewed with a basket and a vendor'
    );
    is_deeply( $inputs->( 'claimacquisition', 'MY_CLAIM' ), ['vendor'], 'A claim, with a vendor' );
    is_deeply(
        $inputs->( 'reserves', 'HOLD' ), [qw( patron item hold )],
        'A hold notice, with a patron, an item and a hold'
    );
    is_deeply( $inputs->( 'not_a_module', 'X' ), [qw( patron item )], 'An unknown notice, with a patron and an item' );
    is_deeply( $inputs->( 'members',      'PASSWORD_RESET' ), [],     'A notice receiving no records, with none' );

    my $find   = sub { Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Preview->find_record(@_) };
    my $patron = $builder->build_object( { class => 'Koha::Patrons' } );
    my $item   = $builder->build_sample_item;
    my $vendor = $builder->build_object( { class => 'Koha::Acquisition::Booksellers' } );
    my $basket =
        $builder->build_object( { class => 'Koha::Acquisition::Baskets', value => { booksellerid => $vendor->id } } );

    is(
        $find->( 'patron', $patron->cardnumber )->borrowernumber, $patron->borrowernumber,
        'A patron is found by card number'
    );
    is( $find->( 'item',    $item->barcode )->itemnumber,  $item->itemnumber, 'An item, by barcode' );
    is( $find->( 'vendor',  $vendor->name )->id,           $vendor->id,       'A vendor, by name' );
    is( $find->( 'basket',  $basket->basketno )->basketno, $basket->basketno, 'Other records, by id' );
    ok( !$find->( 'basket', $basket->basketno + 1000 ), 'Nothing is found for an id that does not exist' );

    $schema->storage->txn_rollback;
};

subtest 'records related to the records given' => sub {
    plan tests => 9;

    $schema->storage->txn_begin;

    my $vendor = $builder->build_object( { class => 'Koha::Acquisition::Booksellers' } );
    my $basket =
        $builder->build_object( { class => 'Koha::Acquisition::Baskets', value => { booksellerid => $vendor->id } } );
    my $order =
        $builder->build_object( { class => 'Koha::Acquisition::Orders', value => { basketno => $basket->basketno } } );

    my $preview = preview( 'orderacquisition', 'ACQORDER', { records => { basket => $basket } } );
    my $objects = $preview->letter_params->{objects};
    is( $objects->{basket}->basketno, $basket->basketno, 'The basket given is used' );
    is( $objects->{bookseller}->id,   $vendor->id,       'with its vendor' );
    is_deeply( [ map { $_->ordernumber } $objects->{orders}->as_list ], [ $order->ordernumber ], 'and its orders' );
    ok( !$preview->patron, 'No patron is used for a notice receiving none' );
    ok( !( grep { $_->{code} eq 'sample_patron' } @{ $preview->notes } ), '... and no note says so' );

    my $patron = $builder->build_object( { class => 'Koha::Patrons' } );
    my $item   = $builder->build_sample_item;
    my $hold   = $builder->build_object(
        {
            class => 'Koha::Holds',
            value => {
                borrowernumber => $patron->borrowernumber, itemnumber => $item->itemnumber,
                biblionumber   => $item->biblionumber,     found      => undef
            }
        }
    );
    $objects = preview( 'reserves', 'HOLD', { records => { hold => $hold } } )->letter_params->{objects};
    is( $objects->{borrower}->borrowernumber, $patron->borrowernumber, 'The patron of the hold given is used' );
    is( $objects->{item}->itemnumber,         $item->itemnumber,       'with its item' );

    my $suggestion = $builder->build_object(
        { class => 'Koha::Suggestions', value => { suggestedby => $patron->borrowernumber, biblionumber => undef } } );
    $objects =
        preview( 'suggestions', 'ACCEPTED', { records => { suggestion => $suggestion } } )->letter_params->{objects};
    is( $objects->{suggestion}->suggestionid, $suggestion->suggestionid, 'The suggestion given is used' );
    is( $objects->{borrower}->borrowernumber, $patron->borrowernumber,   'with the patron who suggested it' );

    $schema->storage->txn_rollback;
};

subtest 'values of records' => sub {
    plan tests => 6;

    $schema->storage->txn_begin;

    is_deeply(
        Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Preview->inputs( 'catalogue', 'OAI_HARVEST_REPORT' ),
        ['oai_server'],
        'An OAI harvest report is previewed with an OAI server'
    );

    my $server = $builder->build_object( { class => 'Koha::OAIServers', value => { oai_set => 'books' } } );
    is(
        Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Preview->find_record( 'oai_server', $server->servername )
            ->id, $server->id,
        'An OAI server is found by name'
    );

    my $preview = preview( 'catalogue', 'OAI_HARVEST_REPORT', { records => { oai_server => $server } } );
    my $values  = $preview->letter_params->{substitute};
    is( $values->{servername}, $server->servername, 'The values come from the OAI server given' );
    is( $values->{set},        'books',             '... from the column they come from (oai_set)' );
    is( $values->{added},      '[added]',           'Values that do not come from a record are placeholders' );

    $preview = preview( 'catalogue', 'OAI_HARVEST_REPORT' );
    $preview->letter_params;
    ok(
        ( grep { $_ eq 'sample oai_server' } @{ note_codes($preview) } ),
        'Without an OAI server, an example one is used, with a note'
    );

    $schema->storage->txn_rollback;
};

subtest 'notices combining items' => sub {
    plan tests => 11;

    $schema->storage->txn_begin;

    my $class = 'Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Preview';
    ok(
        $class->combines( 'circulation', 'CHECKOUT' ) && $class->combines( 'reserves', 'HOLDDGST' ),
        'Checkout notices and hold digests combine items'
    );
    ok( !$class->combines( 'circulation', 'ODUE' ), 'Overdue notices do not (they list them)' );
    ok( !$class->combines( 'reserves',    'HOLD' ), 'Hold notices do not (they are sent one by one)' );

    is_deeply(
        $class->combine_letters(
            [
                { title => 'Title A', content => "Hello A\n----\nItem A\n----\nBye A" },
                { title => 'Title B', content => "Hello B\n----\nItem B\n----\nBye B" },
            ]
        ),
        { title => 'Title A', content => "Hello B\nItem A\nItem B\nBye B" },
        'Letters are combined as queued notices are: the title of the first, the body of each between the header and footer of the last'
    );

    my ( $patron, $item1, $checkout1 ) = patron_with_checkout();
    my $item2     = $builder->build_sample_item;
    my $checkout2 = $builder->build_object(
        {
            class => 'Koha::Checkouts',
            value =>
                { borrowernumber => $patron->borrowernumber, itemnumber => $item2->itemnumber, returndate => undef }
        }
    );

    my $preview = preview( 'circulation', 'CHECKOUT', { patron => $patron } );
    my $list    = $preview->letter_params_list;
    is( $preview->combined, 2, 'Without items, a checkout notice is previewed with the checkouts of the patron' );
    is_deeply(
        [ sort map { $_->{objects}->{checkout}->issue_id } @$list ],
        [ sort ( $checkout1->issue_id, $checkout2->issue_id ) ],
        '... each with its own checkout'
    );

    $preview = preview( 'circulation', 'CHECKOUT', { patron => $patron, items => [ $item2, $item1 ] } );
    is_deeply(
        [ map { $_->{objects}->{item}->itemnumber } @{ $preview->letter_params_list } ],
        [ $item2->itemnumber, $item1->itemnumber ],
        'The items given are used, in their order'
    );

    $preview = preview( 'circulation', 'CHECKOUT', { patron => $patron, item => $item1 } );
    is( scalar @{ $preview->letter_params_list }, 1, 'With one item, the notice is previewed once' );
    is( $preview->combined,                       0, '... and is not combined' );

    my @holds = map {
        my $item = $_;
        $builder->build_object(
            {
                class => 'Koha::Holds',
                value => {
                    borrowernumber => $patron->borrowernumber, itemnumber => $item->itemnumber,
                    biblionumber   => $item->biblionumber,     found      => 'W'
                }
            }
        );
    } ( $item1, $item2 );
    $list = preview( 'reserves', 'HOLDDGST', { patron => $patron, items => [ $item1, $item2 ] } )->letter_params_list;
    is_deeply(
        [ map { $_->{objects}->{hold}->reserve_id } @$list ],
        [ map { $_->reserve_id } @holds ],
        'Each item gets the hold of the patron on it'
    );

    is(
        scalar @{ preview( 'circulation', 'ODUE', { patron => $patron } )->letter_params_list },
        1, 'Other notices are previewed once'
    );

    $schema->storage->txn_rollback;
};

subtest 'libraries and formatted values, as the senders give them' => sub {
    plan tests => 4;

    $schema->storage->txn_begin;

    my $patron = $builder->build_object( { class => 'Koha::Patrons', value => { dateexpiry => '2031-02-03' } } );
    my $pickup = $builder->build_object( { class => 'Koha::Libraries' } );
    my $item   = $builder->build_sample_item;
    my $hold   = $builder->build_object(
        {
            class => 'Koha::Holds',
            value => {
                borrowernumber => $patron->borrowernumber, itemnumber => $item->itemnumber,
                biblionumber   => $item->biblionumber,     branchcode => $pickup->branchcode, found => 'W'
            }
        }
    );

    my $objects = preview( 'reserves', 'HOLD', { records => { hold => $hold } } )->letter_params->{objects};
    is( $objects->{branch}->branchcode, $pickup->branchcode, 'Hold notices have the pickup library of the hold' );

    t::lib::Mocks::mock_preference( 'CircControl',         'ItemHomeLibrary' );
    t::lib::Mocks::mock_preference( 'HomeOrHoldingBranch', 'homebranch' );
    $objects = preview( 'circulation', 'CHECKOUT', { patron => $patron, item => $item } )->letter_params->{objects};
    is( $objects->{branch}->branchcode, $item->homebranch, 'Checkout notices have the circulation control library' );

    $objects = preview( 'members', 'MEMBERSHIP_EXPIRY', { patron => $patron } )->letter_params->{objects};
    is( $objects->{branch}->branchcode, $patron->branchcode, 'Other notices have the library of the patron' );

    my $letter = C4::Letters::GetPreparedLetter(
        letter => { title => 'T', content => '<<borrowers.dateexpiry>>', lang => 'default' },
        %{ preview( 'members', 'MEMBERSHIP_EXPIRY', { patron => $patron } )->letter_params },
    );
    is(
        $letter->{content}, output_pref( { dt => dt_from_string('2031-02-03'), dateonly => 1 } ),
        '<<table.column>> values are formatted, as in sent notices'
    );

    $schema->storage->txn_rollback;
};

subtest 'related records' => sub {
    plan tests => 6;

    $schema->storage->txn_begin;

    my $patron = $builder->build_object( { class => 'Koha::Patrons' } );
    my $item   = $builder->build_sample_item;
    my @old    = map {
        $builder->build_object(
            {
                class => 'Koha::Old::Checkouts',
                value => { borrowernumber => $patron->borrowernumber, itemnumber => $item->itemnumber }
            }
        )
    } 1 .. 2;
    my $objects = preview( 'circulation', 'CHECKIN', { patron => $patron, item => $item } )->letter_params->{objects};
    my ($latest) = sort { $b <=> $a } map { $_->issue_id } @old;
    is( $objects->{old_checkout}->issue_id, $latest, 'The latest related record is used' );

    my $other_item = $builder->build_sample_item;
    my $hold       = $builder->build_object(
        {
            class => 'Koha::Holds',
            value => {
                borrowernumber => $patron->borrowernumber,   itemnumber => $other_item->itemnumber,
                biblionumber   => $other_item->biblionumber, found      => undef
            }
        }
    );
    my $preview = preview( 'reserves', 'HOLD', { patron => $patron, item => $item } );
    is(
        $preview->letter_params->{objects}->{hold}->reserve_id,
        $hold->reserve_id, 'Without a record related to all the records given, one related to some is used'
    );
    ok( ( grep { $_ eq 'partial hold' } @{ note_codes($preview) } ), '... with a note' );

    my $biblio_hold = $builder->build_object(
        {
            class => 'Koha::Holds',
            value => {
                borrowernumber => $patron->borrowernumber,   itemnumber => undef,
                biblionumber   => $other_item->biblionumber, found      => undef
            }
        }
    );
    $objects = preview( 'reserves', 'HOLD', { records => { hold => $biblio_hold } } )->letter_params->{objects};
    is( $objects->{item}->biblionumber, $other_item->biblionumber, 'A hold on a record gets an item of the record' );

    my $schema_source = sub { Koha::Database->new->schema->source(shift) };
    ok(
        Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Preview::_refers_to(
            $schema_source->('Aqbasket'), 'booksellerid', 'Koha::Acquisition::Bookseller'
        ),
        'The booksellerid of baskets refers to vendors'
    );
    ok(
        !Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Preview::_refers_to(
            $schema_source->('Item'), 'booksellerid', 'Koha::Acquisition::Bookseller'
        ),
        '... not the one of items, which is a free text'
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
            my $name    = "$notice->{code} $notice->{message_transport_type}";

            # Templates computing with values the preview leaves empty or shows as
            # placeholders (e.g. [change]) give 'isn't numeric' warnings: other
            # warnings are failures
            local $SIG{__WARN__} = sub { push @failed, "$name: warning: $_[0]" unless $_[0] =~ /isn't numeric/ };
            my $failed;
            my $letter = try {
                C4::Letters::GetPreparedLetter(
                    letter => {
                        title   => $notice->{title},   content => join( "\n", @{ $notice->{content} } ),
                        is_html => $notice->{is_html}, lang    => 'default'
                    },
                    %{ $preview->letter_params },
                );
            } catch {
                push @failed, "$name: $_";
                $failed = 1;
            };
            push @failed, "$name: nothing rendered" unless $letter || $failed;
        }
    }
    is_deeply( \@failed, [], 'All the sample notices render' );

    $schema->storage->txn_rollback;
};
