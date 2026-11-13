package Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables;

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

use Try::Tiny qw( catch try );

use C4::Context;
use Koha::Database;
use Koha::Logger;

=head1 NAME

Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables - The data each notice receives

=head1 DESCRIPTION

Lists what the code that generates each notice passes to
C<C4::Letters::GetPreparedLetter>: the Template Toolkit variables, and the
tables and keys the bespoke <<table.column>> syntax can use. The notice editor
uses it to offer the fields a notice can use, and to tell when a template uses
a variable the notice will not have.

Each variable has a I<kind>:

=over

=item object - a single Koha::Object of I<class>

=item objects - a Koha::Objects set of I<class>

=item array_of_objects - an arrayref of Koha::Object of I<class>

=item hash - a hashref, whose I<keys> (key => type) are given when known, or
whose keys are the columns of the database I<tables> (e.g. a row fetched with
SELECT biblio.*, items.*); both can be given

=item array_of_hashes - an arrayref of hashrefs, whose I<keys> or I<tables> are
given as for hash

=item scalar, unknown - values whose content is not checked

=back

Hashes with neither I<keys> nor I<tables> can have any keys (e.g. the columns
of a report).

Scalars taken from a record have I<from>: the kind of record and its field
(e.g. 'oai_server.servername'), for previews (see
Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Preview).

It is a copy of Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables (Koha bug 36588), for Koha
versions without it. Keep them in sync.

=cut

# An item of the stock rotation report (Koha::StockRotationItem->investigate)
my $STOCKROTATION_ITEM = {
    kind => 'array_of_hashes',
    keys => {
        ( map { $_ => { kind => 'scalar' } } qw( author barcode callnumber itemnumber location onloan reason title ) ),
        branch => { kind => 'hash',   tables => ['branches'] },
        object => { kind => 'object', class  => 'Koha::StockRotationItem' },
    },
};

# The checkouts fetched by misc/cronjobs/advance_notices.pl
my @ADVANCE_NOTICE_TABLES = qw( biblio items issues );

# module => { code => { variable => type } }. The code '*' lists the variables
# of notices with a custom code: one that isn't listed here, created in the
# notices tool (e.g. for the overdue notice triggers).
our $VARIABLES = {
    acquisition => {
        'ACQ_NOTIF_ON_RECEIV' => {
            biblio   => { kind => 'object', class => 'Koha::Biblio' },
            borrower => { kind => 'object', class => 'Koha::Patron' },
            branch   => { kind => 'object', class => 'Koha::Library' },
            order    => { kind => 'object', class => 'Koha::Acquisition::Order' },
        },
        'EDI_DUP_INV_LIBRARY' => {
            bookseller            => { kind => 'object', class => 'Koha::Acquisition::Bookseller' },
            filename              => { kind => 'scalar' },
            invoicenumber         => { kind => 'scalar' },
            message_id            => { kind => 'scalar' },
            original_invoiceid    => { kind => 'scalar' },
            original_shipmentdate => { kind => 'scalar' },
            received_date         => { kind => 'scalar' },
            vendor_id             => { kind => 'scalar' },
            vendor_san            => { kind => 'scalar' },
        },
        'EDI_DUP_INV_VENDOR' => {
            bookseller            => { kind => 'object', class => 'Koha::Acquisition::Bookseller' },
            filename              => { kind => 'scalar' },
            invoicenumber         => { kind => 'scalar' },
            message_id            => { kind => 'scalar' },
            original_invoiceid    => { kind => 'scalar' },
            original_shipmentdate => { kind => 'scalar' },
            received_date         => { kind => 'scalar' },
            vendor_id             => { kind => 'scalar' },
            vendor_san            => { kind => 'scalar' },
        },
        'EDI_DUP_ORD_LIBRARY' => {
            basketno          => { kind => 'scalar' },
            bookseller        => { kind => 'object', class => 'Koha::Acquisition::Bookseller' },
            existing_basketno => { kind => 'scalar' },
            po_number         => { kind => 'scalar' },
            vendor_id         => { kind => 'scalar' },
            vendor_san        => { kind => 'scalar' },
        },
        'EDI_DUP_ORD_VENDOR' => {
            basketno          => { kind => 'scalar' },
            bookseller        => { kind => 'object', class => 'Koha::Acquisition::Bookseller' },
            existing_basketno => { kind => 'scalar' },
            po_number         => { kind => 'scalar' },
            vendor_id         => { kind => 'scalar' },
            vendor_san        => { kind => 'scalar' },
        },
    },
    add_message => {
        '*' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            branch   => { kind => 'object', class => 'Koha::Library' },
        },
    },
    bookings => {
        'BOOKING_CANCELLATION' => {
            booking     => { kind => 'object', class => 'Koha::Booking' },
            old_booking => { kind => 'object', class => 'Koha::Booking' },
        },
        'BOOKING_CONFIRMATION' => {
            booking => { kind => 'object', class => 'Koha::Booking' },
        },
        'BOOKING_MODIFICATION' => {
            booking     => { kind => 'object', class => 'Koha::Booking' },
            old_booking => { kind => 'object', class => 'Koha::Booking' },
        },
    },
    catalogue => {
        'CART' => {
            biblios  => { kind => 'objects', class => 'Koha::Biblios' },
            borrower => { kind => 'object',  class => 'Koha::Patron' },
            comment  => { kind => 'scalar' },
        },
        'OAI_HARVEST_REPORT' => {
            added      => { kind => 'scalar' },
            dataformat => { kind => 'scalar', from => 'oai_server.dataformat' },
            deleted    => { kind => 'scalar' },
            endpoint   => { kind => 'scalar', from => 'oai_server.endpoint' },
            in_error   => { kind => 'scalar' },
            recordtype => { kind => 'scalar', from => 'oai_server.recordtype' },
            servername => { kind => 'scalar', from => 'oai_server.servername' },
            set        => { kind => 'scalar', from => 'oai_server.oai_set' },
            skipped    => { kind => 'scalar' },
            total      => { kind => 'scalar' },
            updated    => { kind => 'scalar' },
        },
        'TICKET_ACKNOWLEDGE' => {
            ticket => { kind => 'object', class => 'Koha::Ticket' },
        },
        'TICKET_ASSIGNED' => {
            ticket => { kind => 'object', class => 'Koha::Ticket' },
        },
        'TICKET_NOTIFY' => {
            ticket => { kind => 'object', class => 'Koha::Ticket' },
        },
        'TICKET_RESOLVE' => {
            ticket_update => { kind => 'object', class => 'Koha::Ticket::Update' },
        },
        'TICKET_UPDATE' => {
            ticket_update => { kind => 'object', class => 'Koha::Ticket::Update' },
        },
    },
    circulation => {
        '*' => {
            bib      => { kind => 'scalar' },
            borrower => { kind => 'object', class => 'Koha::Patron' },
            branch   => { kind => 'object', class => 'Koha::Library' },
            count    => { kind => 'scalar' },
            overdues => { kind => 'objects', class => 'Koha::Checkouts' },
        },
        'ACCOUNT_CANCELLATION' => {
            borrower => { kind => 'object',           class => 'Koha::Patron' },
            branch   => { kind => 'object',           class => 'Koha::Library' },
            credit   => { kind => 'object',           class => 'Koha::Account::Line' },
            offsets  => { kind => 'array_of_objects', class => 'Koha::Account::Offset' },
        },
        'ACCOUNT_CASHUP_SURPLUS' => {
            borrower => { kind => 'object',           class => 'Koha::Patron' },
            branch   => { kind => 'object',           class => 'Koha::Library' },
            credit   => { kind => 'object',           class => 'Koha::Account::Line' },
            offsets  => { kind => 'array_of_objects', class => 'Koha::Account::Offset' },
        },
        'ACCOUNT_CREDIT' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            branch   => { kind => 'object', class => 'Koha::Library' },
            change   => { kind => 'scalar' },
            credit   => { kind => 'object',           class => 'Koha::Account::Line' },
            offsets  => { kind => 'array_of_objects', class => 'Koha::Account::Offset' },
            tendered => { kind => 'scalar' },
        },
        'ACCOUNT_DEBIT' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            debit    => { kind => 'object', class => 'Koha::Account::Line' },
        },
        'ACCOUNT_DISCOUNT' => {
            borrower => { kind => 'object',           class => 'Koha::Patron' },
            branch   => { kind => 'object',           class => 'Koha::Library' },
            credit   => { kind => 'object',           class => 'Koha::Account::Line' },
            offsets  => { kind => 'array_of_objects', class => 'Koha::Account::Offset' },
        },
        'ACCOUNT_FORGIVEN' => {
            borrower => { kind => 'object',           class => 'Koha::Patron' },
            branch   => { kind => 'object',           class => 'Koha::Library' },
            credit   => { kind => 'object',           class => 'Koha::Account::Line' },
            offsets  => { kind => 'array_of_objects', class => 'Koha::Account::Offset' },
        },
        'ACCOUNT_LOST_FOUND' => {
            borrower => { kind => 'object',           class => 'Koha::Patron' },
            branch   => { kind => 'object',           class => 'Koha::Library' },
            credit   => { kind => 'object',           class => 'Koha::Account::Line' },
            offsets  => { kind => 'array_of_objects', class => 'Koha::Account::Offset' },
        },
        'ACCOUNT_OVERPAYMENT' => {
            borrower => { kind => 'object',           class => 'Koha::Patron' },
            branch   => { kind => 'object',           class => 'Koha::Library' },
            credit   => { kind => 'object',           class => 'Koha::Account::Line' },
            offsets  => { kind => 'array_of_objects', class => 'Koha::Account::Offset' },
        },
        'ACCOUNT_PAYMENT' => {
            borrower => { kind => 'object',           class => 'Koha::Patron' },
            branch   => { kind => 'object',           class => 'Koha::Library' },
            credit   => { kind => 'object',           class => 'Koha::Account::Line' },
            offsets  => { kind => 'array_of_objects', class => 'Koha::Account::Offset' },
        },
        'ACCOUNT_PROCESSING_FOUND' => {
            borrower => { kind => 'object',           class => 'Koha::Patron' },
            branch   => { kind => 'object',           class => 'Koha::Library' },
            credit   => { kind => 'object',           class => 'Koha::Account::Line' },
            offsets  => { kind => 'array_of_objects', class => 'Koha::Account::Offset' },
        },
        'ACCOUNT_PURCHASE' => {
            borrower => { kind => 'object',           class => 'Koha::Patron' },
            branch   => { kind => 'object',           class => 'Koha::Library' },
            credit   => { kind => 'object',           class => 'Koha::Account::Line' },
            offsets  => { kind => 'array_of_objects', class => 'Koha::Account::Offset' },
        },
        'ACCOUNT_REFUND' => {
            borrower => { kind => 'object',           class => 'Koha::Patron' },
            branch   => { kind => 'object',           class => 'Koha::Library' },
            credit   => { kind => 'object',           class => 'Koha::Account::Line' },
            offsets  => { kind => 'array_of_objects', class => 'Koha::Account::Offset' },
        },
        'ACCOUNT_WRITEOFF' => {
            borrower => { kind => 'object',           class => 'Koha::Patron' },
            branch   => { kind => 'object',           class => 'Koha::Library' },
            credit   => { kind => 'object',           class => 'Koha::Account::Line' },
            offsets  => { kind => 'array_of_objects', class => 'Koha::Account::Offset' },
        },
        'AR_CANCELED' => {
            article_request => { kind => 'object', class => 'Koha::ArticleRequest' },
            biblio          => { kind => 'object', class => 'Koha::Biblio' },
            biblioitem      => { kind => 'object', class => 'Koha::Biblioitem' },
            borrower        => { kind => 'object', class => 'Koha::Patron' },
            branch          => { kind => 'object', class => 'Koha::Library' },
            item            => { kind => 'object', class => 'Koha::Item' },
            reason          => { kind => 'scalar' },
        },
        'AR_COMPLETED' => {
            article_request => { kind => 'object', class => 'Koha::ArticleRequest' },
            biblio          => { kind => 'object', class => 'Koha::Biblio' },
            biblioitem      => { kind => 'object', class => 'Koha::Biblioitem' },
            borrower        => { kind => 'object', class => 'Koha::Patron' },
            branch          => { kind => 'object', class => 'Koha::Library' },
            item            => { kind => 'object', class => 'Koha::Item' },
            reason          => { kind => 'scalar' },
        },
        'AR_PENDING' => {
            article_request => { kind => 'object', class => 'Koha::ArticleRequest' },
            biblio          => { kind => 'object', class => 'Koha::Biblio' },
            biblioitem      => { kind => 'object', class => 'Koha::Biblioitem' },
            borrower        => { kind => 'object', class => 'Koha::Patron' },
            branch          => { kind => 'object', class => 'Koha::Library' },
            item            => { kind => 'object', class => 'Koha::Item' },
            reason          => { kind => 'scalar' },
        },
        'AR_PROCESSING' => {
            article_request => { kind => 'object', class => 'Koha::ArticleRequest' },
            biblio          => { kind => 'object', class => 'Koha::Biblio' },
            biblioitem      => { kind => 'object', class => 'Koha::Biblioitem' },
            borrower        => { kind => 'object', class => 'Koha::Patron' },
            branch          => { kind => 'object', class => 'Koha::Library' },
            item            => { kind => 'object', class => 'Koha::Item' },
            reason          => { kind => 'scalar' },
        },
        'AR_REQUESTED' => {
            article_request => { kind => 'object', class => 'Koha::ArticleRequest' },
            biblio          => { kind => 'object', class => 'Koha::Biblio' },
            biblioitem      => { kind => 'object', class => 'Koha::Biblioitem' },
            borrower        => { kind => 'object', class => 'Koha::Patron' },
            branch          => { kind => 'object', class => 'Koha::Library' },
            item            => { kind => 'object', class => 'Koha::Item' },
            reason          => { kind => 'scalar' },
        },
        'AR_SLIP' => {
            article_request => { kind => 'object', class => 'Koha::ArticleRequest' },
            biblio          => { kind => 'object', class => 'Koha::Biblio' },
            biblioitem      => { kind => 'object', class => 'Koha::Biblioitem' },
            borrower        => { kind => 'object', class => 'Koha::Patron' },
            branch          => { kind => 'object', class => 'Koha::Library' },
            item            => { kind => 'object', class => 'Koha::Item' },
        },
        'AUTO_RENEWALS' => {
            biblio   => { kind => 'object', class => 'Koha::Biblio' },
            borrower => { kind => 'object', class => 'Koha::Patron' },
            branch   => { kind => 'object', class => 'Koha::Library' },
            checkout => { kind => 'object', class => 'Koha::Checkout' },
            item     => { kind => 'object', class => 'Koha::Item' },
        },
        'AUTO_RENEWALS_DGST' => {
            borrower  => { kind => 'object',  class => 'Koha::Patron' },
            branch    => { kind => 'object',  class => 'Koha::Library' },
            checkouts => { kind => 'objects', class => 'Koha::Checkouts' },
            error     => { kind => 'scalar' },
            results   => { kind => 'hash' },
            success   => { kind => 'scalar' },
        },
        'CHECKIN' => {
            biblio       => { kind => 'object', class => 'Koha::Biblio' },
            biblioitem   => { kind => 'object', class => 'Koha::Biblioitem' },
            borrower     => { kind => 'object', class => 'Koha::Patron' },
            branch       => { kind => 'object', class => 'Koha::Library' },
            item         => { kind => 'object', class => 'Koha::Item' },
            old_checkout => { kind => 'object', class => 'Koha::Old::Checkout' },
        },
        'CHECKINSLIP' => {
            borrower      => { kind => 'object',  class => 'Koha::Patron' },
            branch        => { kind => 'object',  class => 'Koha::Library' },
            old_checkouts => { kind => 'objects', class => 'Koha::Old::Checkouts' },
        },
        'CHECKOUT' => {
            biblio     => { kind => 'object', class => 'Koha::Biblio' },
            biblioitem => { kind => 'object', class => 'Koha::Biblioitem' },
            borrower   => { kind => 'object', class => 'Koha::Patron' },
            branch     => { kind => 'object', class => 'Koha::Library' },
            checkout   => { kind => 'object', class => 'Koha::Checkout' },
            item       => { kind => 'object', class => 'Koha::Item' },
        },
        'CHECKOUT_NOTE' => {
            biblio   => { kind => 'object', class => 'Koha::Biblio' },
            borrower => { kind => 'object', class => 'Koha::Patron' },
            checkout => { kind => 'object', class => 'Koha::Checkout' },
            item     => { kind => 'object', class => 'Koha::Item' },
        },
        'CREDIT_CANCELLATION' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            change   => { kind => 'scalar' },
            credit   => { kind => 'object', class => 'Koha::Account::Line' },
            tendered => { kind => 'scalar' },
        },
        'CREDIT_CASHUP_SURPLUS' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            change   => { kind => 'scalar' },
            credit   => { kind => 'object', class => 'Koha::Account::Line' },
            tendered => { kind => 'scalar' },
        },
        'CREDIT_CREDIT' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            change   => { kind => 'scalar' },
            credit   => { kind => 'object', class => 'Koha::Account::Line' },
            tendered => { kind => 'scalar' },
        },
        'CREDIT_DISCOUNT' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            change   => { kind => 'scalar' },
            credit   => { kind => 'object', class => 'Koha::Account::Line' },
            tendered => { kind => 'scalar' },
        },
        'CREDIT_FORGIVEN' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            change   => { kind => 'scalar' },
            credit   => { kind => 'object', class => 'Koha::Account::Line' },
            tendered => { kind => 'scalar' },
        },
        'CREDIT_LOST_FOUND' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            change   => { kind => 'scalar' },
            credit   => { kind => 'object', class => 'Koha::Account::Line' },
            tendered => { kind => 'scalar' },
        },
        'CREDIT_OVERPAYMENT' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            change   => { kind => 'scalar' },
            credit   => { kind => 'object', class => 'Koha::Account::Line' },
            tendered => { kind => 'scalar' },
        },
        'CREDIT_PAYMENT' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            change   => { kind => 'scalar' },
            credit   => { kind => 'object', class => 'Koha::Account::Line' },
            tendered => { kind => 'scalar' },
        },
        'CREDIT_PROCESSING_FOUND' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            change   => { kind => 'scalar' },
            credit   => { kind => 'object', class => 'Koha::Account::Line' },
            tendered => { kind => 'scalar' },
        },
        'CREDIT_PURCHASE' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            change   => { kind => 'scalar' },
            credit   => { kind => 'object', class => 'Koha::Account::Line' },
            tendered => { kind => 'scalar' },
        },
        'CREDIT_REFUND' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            change   => { kind => 'scalar' },
            credit   => { kind => 'object', class => 'Koha::Account::Line' },
            tendered => { kind => 'scalar' },
        },
        'CREDIT_WRITEOFF' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            change   => { kind => 'scalar' },
            credit   => { kind => 'object', class => 'Koha::Account::Line' },
            tendered => { kind => 'scalar' },
        },
        'DEBIT_ACCOUNT' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            debit    => { kind => 'object', class => 'Koha::Account::Line' },
        },
        'DEBIT_ACCOUNT_RENEW' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            debit    => { kind => 'object', class => 'Koha::Account::Line' },
        },
        'DEBIT_ARTICLE_REQUEST' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            debit    => { kind => 'object', class => 'Koha::Account::Line' },
        },
        'DEBIT_CASHUP_DEFICIT' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            debit    => { kind => 'object', class => 'Koha::Account::Line' },
        },
        'DEBIT_LOST' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            debit    => { kind => 'object', class => 'Koha::Account::Line' },
        },
        'DEBIT_MANUAL' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            debit    => { kind => 'object', class => 'Koha::Account::Line' },
        },
        'DEBIT_NEW_CARD' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            debit    => { kind => 'object', class => 'Koha::Account::Line' },
        },
        'DEBIT_OVERDUE' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            debit    => { kind => 'object', class => 'Koha::Account::Line' },
        },
        'DEBIT_PAYOUT' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            debit    => { kind => 'object', class => 'Koha::Account::Line' },
        },
        'DEBIT_PROCESSING' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            debit    => { kind => 'object', class => 'Koha::Account::Line' },
        },
        'DEBIT_RENT' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            debit    => { kind => 'object', class => 'Koha::Account::Line' },
        },
        'DEBIT_RENT_DAILY' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            debit    => { kind => 'object', class => 'Koha::Account::Line' },
        },
        'DEBIT_RENT_DAILY_RENEW' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            debit    => { kind => 'object', class => 'Koha::Account::Line' },
        },
        'DEBIT_RENT_RENEW' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            debit    => { kind => 'object', class => 'Koha::Account::Line' },
        },
        'DEBIT_RESERVE' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            debit    => { kind => 'object', class => 'Koha::Account::Line' },
        },
        'DEBIT_RESERVE_EXPIRED' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            debit    => { kind => 'object', class => 'Koha::Account::Line' },
        },
        'DEBIT_VOID' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            debit    => { kind => 'object', class => 'Koha::Account::Line' },
        },
        'DUE' => {
            biblio     => { kind => 'object', class  => 'Koha::Biblio' },
            biblioitem => { kind => 'object', class  => 'Koha::Biblioitem' },
            borrower   => { kind => 'object', class  => 'Koha::Patron' },
            branch     => { kind => 'object', class  => 'Koha::Library' },
            checkout   => { kind => 'hash',   tables => \@ADVANCE_NOTICE_TABLES },
            item       => { kind => 'object', class  => 'Koha::Item' },
        },
        'DUEDGST' => {
            borrower  => { kind => 'object',          class  => 'Koha::Patron' },
            branch    => { kind => 'object',          class  => 'Koha::Library' },
            checkouts => { kind => 'array_of_hashes', tables => \@ADVANCE_NOTICE_TABLES },
            count     => { kind => 'scalar' },
            items     => { kind => 'objects', class => 'Koha::Items' },
        },
        'HOLD_SLIP' => {
            biblio     => { kind => 'object', class => 'Koha::Biblio' },
            biblioitem => { kind => 'object', class => 'Koha::Biblioitem' },
            borrower   => { kind => 'object', class => 'Koha::Patron' },
            branch     => { kind => 'object', class => 'Koha::Library' },
            hold       => { kind => 'object', class => 'Koha::Hold' },
            item       => { kind => 'object', class => 'Koha::Item' },
        },
        'ISSUEQSLIP' => {
            borrower  => { kind => 'object',  class => 'Koha::Patron' },
            branch    => { kind => 'object',  class => 'Koha::Library' },
            checkouts => { kind => 'objects', class => 'Koha::Checkouts' },
        },
        'ISSUESLIP' => {
            additional_contents => { kind => 'objects', class => 'Koha::AdditionalContentsLocalizations' },
            borrower            => { kind => 'object',  class => 'Koha::Patron' },
            branch              => { kind => 'object',  class => 'Koha::Library' },
            checkouts           => { kind => 'objects', class => 'Koha::Checkouts' },
            news                => { kind => 'objects', class => 'Koha::AdditionalContentsLocalizations' },
            overdues            => { kind => 'objects', class => 'Koha::Checkouts' },
        },
        'OVERDUE' => {
            biblio     => { kind => 'object', class => 'Koha::Biblio' },
            biblioitem => { kind => 'object', class => 'Koha::Biblioitem' },
            borrower   => { kind => 'object', class => 'Koha::Patron' },
        },
        'OVERDUES_SLIP' => {
            borrower => { kind => 'object',  class => 'Koha::Patron' },
            branch   => { kind => 'object',  class => 'Koha::Library' },
            overdues => { kind => 'objects', class => 'Koha::Checkouts' },
        },
        'OVERDUE_FINE_DESC' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            checkout => { kind => 'object', class => 'Koha::Checkout' },
            item     => { kind => 'object', class => 'Koha::Item' },
        },
        'PICKUP_RECALLED_ITEM' => {
            biblio   => { kind => 'object', class => 'Koha::Biblio' },
            borrower => { kind => 'object', class => 'Koha::Patron' },
            item     => { kind => 'object', class => 'Koha::Item' },
            recall   => { kind => 'object', class => 'Koha::Recall' },
        },
        'PREDUE' => {
            biblio     => { kind => 'object', class  => 'Koha::Biblio' },
            biblioitem => { kind => 'object', class  => 'Koha::Biblioitem' },
            borrower   => { kind => 'object', class  => 'Koha::Patron' },
            branch     => { kind => 'object', class  => 'Koha::Library' },
            checkout   => { kind => 'hash',   tables => \@ADVANCE_NOTICE_TABLES },
            item       => { kind => 'object', class  => 'Koha::Item' },
        },
        'PREDUEDGST' => {
            borrower  => { kind => 'object',          class  => 'Koha::Patron' },
            branch    => { kind => 'object',          class  => 'Koha::Library' },
            checkouts => { kind => 'array_of_hashes', tables => \@ADVANCE_NOTICE_TABLES },
            count     => { kind => 'scalar' },
            items     => { kind => 'objects', class => 'Koha::Items' },
        },
        'RECALL_REQUESTER_DET' => {
            biblio   => { kind => 'object', class => 'Koha::Biblio' },
            borrower => { kind => 'object', class => 'Koha::Patron' },
            branch   => { kind => 'object', class => 'Koha::Library' },
            item     => { kind => 'object', class => 'Koha::Item' },
            recall   => { kind => 'object', class => 'Koha::Recall' },
        },
        'RENEWAL' => {
            biblio     => { kind => 'object', class => 'Koha::Biblio' },
            biblioitem => { kind => 'object', class => 'Koha::Biblioitem' },
            borrower   => { kind => 'object', class => 'Koha::Patron' },
            branch     => { kind => 'object', class => 'Koha::Library' },
            checkout   => { kind => 'object', class => 'Koha::Checkout' },
            item       => { kind => 'object', class => 'Koha::Item' },
        },
        'RETURN_RECALLED_ITEM' => {
            biblio   => { kind => 'object', class => 'Koha::Biblio' },
            borrower => { kind => 'object', class => 'Koha::Patron' },
            checkout => { kind => 'object', class => 'Koha::Checkout' },
            item     => { kind => 'object', class => 'Koha::Item' },
        },
        'SR_SLIP' => {
            branch => {
                kind => 'hash',
                keys => {
                    ( map { $_ => { kind => 'scalar' } } qw( code email name phone ) ),
                    items => $STOCKROTATION_ITEM,
                    log   => $STOCKROTATION_ITEM,
                },
            },
        },
        'TRANSFERSLIP' => {
            biblio => { kind => 'object', class => 'Koha::Biblio' },
            branch => { kind => 'object', class => 'Koha::Library' },
            item   => { kind => 'object', class => 'Koha::Item' },
        },
    },
    claimacquisition => {
        '*' => {
            bookseller => { kind => 'object', class => 'Koha::Acquisition::Bookseller' },
            branch     => { kind => 'object', class => 'Koha::Library' },
        },
    },
    claimissues => {
        '*' => {
            bookseller => { kind => 'object', class => 'Koha::Acquisition::Bookseller' },
            branch     => { kind => 'object', class => 'Koha::Library' },
        },
    },
    commandline => {
        'SFTP_FAILURE' => {
            email      => { kind => 'scalar' },
            file       => { kind => 'scalar' },
            host       => { kind => 'scalar' },
            sftp_error => { kind => 'scalar' },
            upload_dir => { kind => 'scalar' },
            user       => { kind => 'scalar' },
        },
        'SFTP_SUCCESS' => {
            email      => { kind => 'scalar' },
            file       => { kind => 'scalar' },
            host       => { kind => 'scalar' },
            sftp_error => { kind => 'scalar' },
            upload_dir => { kind => 'scalar' },
            user       => { kind => 'scalar' },
        },
    },
    debit_description => {
        '*' => {
            accountline => { kind => 'object', class => 'Koha::Account::Line' },
            borrower    => { kind => 'object', class => 'Koha::Patron' },
            branch      => { kind => 'object', class => 'Koha::Library' },
        },
    },
    ill => {
        '*' => {
            additional_text      => { kind => 'scalar' },
            biblio               => { kind => 'object', class => 'Koha::Biblio' },
            borrower             => { kind => 'object', class => 'Koha::Patron' },
            branch               => { kind => 'object', class => 'Koha::Library' },
            ill_bib_author       => { kind => 'scalar' },
            ill_bib_title        => { kind => 'scalar' },
            ill_full_metadata    => { kind => 'scalar' },
            illrequest           => { kind => 'object', class => 'Koha::ILL::Request' },
            illrequestattributes => { kind => 'hash' },
        },
    },
    lists => {
        'LIST' => {
            biblios  => { kind => 'objects', class => 'Koha::Biblios' },
            borrower => { kind => 'object',  class => 'Koha::Patron' },
            comment  => { kind => 'scalar' },
            listname => { kind => 'scalar' },
        },
        'SHARE_ACCEPT' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            listname => { kind => 'scalar' },
        },
        'SHARE_INVITE' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            listname => { kind => 'scalar' },
            shareurl => { kind => 'scalar' },
        },
        'TRANSFER_OWNERSHIP' => {
            old_owner => { kind => 'object', class => 'Koha::Patron' },
            owner     => { kind => 'object', class => 'Koha::Patron' },
            shelf     => { kind => 'object', class => 'Koha::Virtualshelf' },
        },
    },
    members => {
        '*' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
        },
        '2FA_DISABLE' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            branch   => { kind => 'object', class => 'Koha::Library' },
        },
        '2FA_ENABLE' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            branch   => { kind => 'object', class => 'Koha::Library' },
        },
        '2FA_OTP_TOKEN' => {
            borrower  => { kind => 'object', class => 'Koha::Patron' },
            otp_token => { kind => 'scalar' },
        },
        'ACCOUNTS_SUMMARY' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
        },
        'DISCHARGE' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            branch   => { kind => 'object', class => 'Koha::Library' },
        },
        'MEMBERSHIP_EXPIRY' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            branch   => { kind => 'object', class => 'Koha::Library' },
        },
        'MEMBERSHIP_RENEWED' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            branch   => { kind => 'object', class => 'Koha::Library' },
        },
        'OPAC_REG' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
        },
        'OPAC_REG_VERIFY' => {
            patron_modification => { kind => 'object', class => 'Koha::Patron::Modification' },
        },
        'PASSWORD_CHANGE' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            branch   => { kind => 'object', class => 'Koha::Library' },
        },
        'PASSWORD_RESET' => {
            passwordreseturl => { kind => 'scalar' },
            user             => { kind => 'scalar' },
        },
        'PROBLEM_REPORT' => {
            problemreport => { kind => 'object', class => 'Koha::ProblemReport' },
        },
        'STAFF_PASSWORD_RESET' => {
            passwordreseturl => { kind => 'scalar' },
            user             => { kind => 'scalar' },
        },
        'VIRTUALCARD' => {
            borrower   => { kind => 'object', class => 'Koha::Patron' },
            branch     => { kind => 'object', class => 'Koha::Library' },
            my_barcode => { kind => 'scalar' },
            my_image   => { kind => 'scalar' },
        },
        'WELCOME' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            branch   => { kind => 'object', class => 'Koha::Library' },
        },
    },
    orderacquisition => {
        'ACQORDER' => {
            basket     => { kind => 'object',  class => 'Koha::Acquisition::Basket' },
            bookseller => { kind => 'object',  class => 'Koha::Acquisition::Bookseller' },
            branch     => { kind => 'object',  class => 'Koha::Library' },
            orders     => { kind => 'objects', class => 'Koha::Acquisition::Orders' },
        },
    },
    patron_slip => {
        '*' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            branch   => { kind => 'object', class => 'Koha::Library' },
        },
    },
    pos => {
        'PAYOUT' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            change   => { kind => 'scalar' },
            debit    => { kind => 'object', class => 'Koha::Account::Line' },
            tendered => { kind => 'scalar' },
        },
        'RECEIPT' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            change   => { kind => 'scalar' },
            credit   => { kind => 'object', class => 'Koha::Account::Line' },
            tendered => { kind => 'scalar' },
        },
    },
    preservation => {
        '*' => {
            train_item => { kind => 'object', class => 'Koha::Preservation::Train::Item' },
        },
    },
    report => {
        '*' => {
            data         => { kind => 'array_of_hashes' },
            for_download => { kind => 'scalar' },
            report       => { kind => 'object', class => 'Koha::Report' },
            report_id    => { kind => 'scalar' },
        },
    },
    reserves => {
        'CANCEL_HOLD_ON_LOST' => {
            biblio     => { kind => 'object', class => 'Koha::Biblio' },
            biblioitem => { kind => 'object', class => 'Koha::Biblioitem' },
            borrower   => { kind => 'object', class => 'Koha::Patron' },
            branch     => { kind => 'object', class => 'Koha::Library' },
            hold       => { kind => 'object', class => 'Koha::Hold' },
            item       => { kind => 'object', class => 'Koha::Item' },
        },
        'HOLD' => {
            biblio     => { kind => 'object', class => 'Koha::Biblio' },
            biblioitem => { kind => 'object', class => 'Koha::Biblioitem' },
            borrower   => { kind => 'object', class => 'Koha::Patron' },
            branch     => { kind => 'object', class => 'Koha::Library' },
            hold       => { kind => 'object', class => 'Koha::Hold' },
            item       => { kind => 'object', class => 'Koha::Item' },
        },
        'HOLDDGST' => {
            biblio     => { kind => 'object', class => 'Koha::Biblio' },
            biblioitem => { kind => 'object', class => 'Koha::Biblioitem' },
            borrower   => { kind => 'object', class => 'Koha::Patron' },
            branch     => { kind => 'object', class => 'Koha::Library' },
            hold       => { kind => 'object', class => 'Koha::Hold' },
            item       => { kind => 'object', class => 'Koha::Item' },
        },
        'HOLDPLACED' => {
            biblio     => { kind => 'object', class => 'Koha::Biblio' },
            biblioitem => { kind => 'object', class => 'Koha::Biblioitem' },
            borrower   => { kind => 'object', class => 'Koha::Patron' },
            branch     => { kind => 'object', class => 'Koha::Library' },
            hold       => { kind => 'object', class => 'Koha::Hold' },
            item       => { kind => 'object', class => 'Koha::Item' },
        },

        # misc/cronjobs/holds/holds_reminder.pl, whose --lettercode is HOLD_REMINDER by default
        'HOLD_REMINDER' => {
            borrower => { kind => 'object',  class => 'Koha::Patron' },
            branch   => { kind => 'object',  class => 'Koha::Library' },
            holds    => { kind => 'objects', class => 'Koha::Holds' },
        },
        'HOLDPLACED_PATRON' => {
            borrower => { kind => 'object', class => 'Koha::Patron' },
            hold     => { kind => 'object', class => 'Koha::Hold' },
        },
        'HOLD_CANCELLATION' => {
            biblio     => { kind => 'object', class => 'Koha::Biblio' },
            biblioitem => { kind => 'object', class => 'Koha::Biblioitem' },
            borrower   => { kind => 'object', class => 'Koha::Patron' },
            branch     => { kind => 'object', class => 'Koha::Library' },
            hold       => { kind => 'object', class => 'Koha::Hold' },
            item       => { kind => 'object', class => 'Koha::Item' },
        },
        'HOLD_CHANGED' => {
            biblio     => { kind => 'object', class => 'Koha::Biblio' },
            biblioitem => { kind => 'object', class => 'Koha::Biblioitem' },
            borrower   => { kind => 'object', class => 'Koha::Patron' },
            branch     => { kind => 'object', class => 'Koha::Library' },
            hold       => { kind => 'object', class => 'Koha::Hold' },
            item       => { kind => 'object', class => 'Koha::Item' },
            today      => { kind => 'scalar' },
        },
        'NEW_CURBSIDE_PICKUP' => {
            borrower        => { kind => 'object', class => 'Koha::Patron' },
            branch          => { kind => 'object', class => 'Koha::Library' },
            curbside_pickup => { kind => 'object', class => 'Koha::CurbsidePickup' },
        },
    },
    serial => {
        '*' => {
            biblio       => { kind => 'object', class => 'Koha::Biblio' },
            biblioitem   => { kind => 'object', class => 'Koha::Biblioitem' },
            borrower     => { kind => 'object', class => 'Koha::Patron' },
            branch       => { kind => 'object', class => 'Koha::Library' },
            serial       => { kind => 'object', class => 'Koha::Serial' },
            subscription => { kind => 'object', class => 'Koha::Subscription' },
        },
    },
    suggestions => {
        'ACCEPTED' => {
            biblio     => { kind => 'object', class => 'Koha::Biblio' },
            borrower   => { kind => 'object', class => 'Koha::Patron' },
            branch     => { kind => 'object', class => 'Koha::Library' },
            suggestion => { kind => 'object', class => 'Koha::Suggestion' },
        },
        'AVAILABLE' => {
            biblio     => { kind => 'object', class => 'Koha::Biblio' },
            borrower   => { kind => 'object', class => 'Koha::Patron' },
            branch     => { kind => 'object', class => 'Koha::Library' },
            suggestion => { kind => 'object', class => 'Koha::Suggestion' },
        },
        'CHECKED' => {
            biblio     => { kind => 'object', class => 'Koha::Biblio' },
            borrower   => { kind => 'object', class => 'Koha::Patron' },
            branch     => { kind => 'object', class => 'Koha::Library' },
            suggestion => { kind => 'object', class => 'Koha::Suggestion' },
        },
        'NEW_SUGGESTION' => {
            borrower   => { kind => 'object', class => 'Koha::Patron' },
            branch     => { kind => 'object', class => 'Koha::Library' },
            suggestion => { kind => 'object', class => 'Koha::Suggestion' },
        },
        'NOTIFY_MANAGER' => {
            borrower   => { kind => 'object', class => 'Koha::Patron' },
            branch     => { kind => 'object', class => 'Koha::Library' },
            suggestion => { kind => 'object', class => 'Koha::Suggestion' },
        },
        'ORDERED' => {
            biblio     => { kind => 'object', class => 'Koha::Biblio' },
            borrower   => { kind => 'object', class => 'Koha::Patron' },
            branch     => { kind => 'object', class => 'Koha::Library' },
            suggestion => { kind => 'object', class => 'Koha::Suggestion' },
        },
        'REJECTED' => {
            biblio     => { kind => 'object', class => 'Koha::Biblio' },
            borrower   => { kind => 'object', class => 'Koha::Patron' },
            branch     => { kind => 'object', class => 'Koha::Library' },
            suggestion => { kind => 'object', class => 'Koha::Suggestion' },
        },
        'TO_PROCESS' => {
            borrower   => { kind => 'object', class => 'Koha::Patron' },
            branch     => { kind => 'object', class => 'Koha::Library' },
            suggestion => { kind => 'object', class => 'Koha::Suggestion' },
        },
    },
};

# The data available to the bespoke <<table.column>> syntax, which only sees
# the 'tables', 'repeat' and 'substitute' parameters of GetPreparedLetter:
# module => { code => { tables => [ tables whose columns can be used ],
# tokens => [ substitute keys, used as <<key>> ], only_bespoke => [ tables
# whose data Template Toolkit cannot reach in the notice, if any ] } }
our $BESPOKE = {
    acquisition => {
        'ACQ_NOTIF_ON_RECEIV' => { tables => [qw( aqorders biblio borrowers branches )], tokens => [] },
        'EDI_DUP_INV_LIBRARY' => {
            tables => [qw( aqbooksellers )],
            tokens => [
                qw( filename invoicenumber message_id original_invoiceid original_shipmentdate received_date vendor_id vendor_san )
            ]
        },
        'EDI_DUP_INV_VENDOR' => {
            tables => [qw( aqbooksellers )],
            tokens => [
                qw( filename invoicenumber message_id original_invoiceid original_shipmentdate received_date vendor_id vendor_san )
            ]
        },
        'EDI_DUP_ORD_LIBRARY' => {
            tables => [qw( aqbooksellers )], tokens => [qw( basketno existing_basketno po_number vendor_id vendor_san )]
        },
        'EDI_DUP_ORD_VENDOR' => {
            tables => [qw( aqbooksellers )], tokens => [qw( basketno existing_basketno po_number vendor_id vendor_san )]
        },
    },
    add_message => {
        '*' => { tables => [qw( borrowers branches )], tokens => [] },
    },
    bookings => {
        'BOOKING_CANCELLATION' => { tables => [], tokens => [] },
        'BOOKING_CONFIRMATION' => { tables => [], tokens => [] },
        'BOOKING_MODIFICATION' => { tables => [], tokens => [] },
    },
    catalogue => {
        'CART'               => { tables => [qw( borrowers )], tokens => [qw( comment )] },
        'OAI_HARVEST_REPORT' => {
            tables => [],
            tokens => [qw( added dataformat deleted endpoint in_error recordtype servername set skipped total updated )]
        },
        'TICKET_ACKNOWLEDGE' => { tables => [qw( tickets )],        tokens => [] },
        'TICKET_ASSIGNED'    => { tables => [qw( tickets )],        tokens => [] },
        'TICKET_NOTIFY'      => { tables => [qw( tickets )],        tokens => [] },
        'TICKET_RESOLVE'     => { tables => [qw( ticket_updates )], tokens => [] },
        'TICKET_UPDATE'      => { tables => [qw( ticket_updates )], tokens => [] },
    },
    circulation => {
        '*' => {
            tables => [qw( biblio biblioitems borrowers branches issues items )],
            tokens => [qw( bib count items.content )]
        },
        'ACCOUNT_CANCELLATION'   => { tables => [qw( borrowers branches )], tokens => [qw( credit offsets )] },
        'ACCOUNT_CASHUP_SURPLUS' => { tables => [qw( borrowers branches )], tokens => [qw( credit offsets )] },
        'ACCOUNT_CREDIT'         =>
            { tables => [qw( borrowers branches credits )], tokens => [qw( change credit offsets tendered )] },
        'ACCOUNT_DEBIT'            => { tables => [qw( borrowers debits )],   tokens => [] },
        'ACCOUNT_DISCOUNT'         => { tables => [qw( borrowers branches )], tokens => [qw( credit offsets )] },
        'ACCOUNT_FORGIVEN'         => { tables => [qw( borrowers branches )], tokens => [qw( credit offsets )] },
        'ACCOUNT_LOST_FOUND'       => { tables => [qw( borrowers branches )], tokens => [qw( credit offsets )] },
        'ACCOUNT_OVERPAYMENT'      => { tables => [qw( borrowers branches )], tokens => [qw( credit offsets )] },
        'ACCOUNT_PAYMENT'          => { tables => [qw( borrowers branches )], tokens => [qw( credit offsets )] },
        'ACCOUNT_PROCESSING_FOUND' => { tables => [qw( borrowers branches )], tokens => [qw( credit offsets )] },
        'ACCOUNT_PURCHASE'         => { tables => [qw( borrowers branches )], tokens => [qw( credit offsets )] },
        'ACCOUNT_REFUND'           => { tables => [qw( borrowers branches )], tokens => [qw( credit offsets )] },
        'ACCOUNT_WRITEOFF'         => { tables => [qw( borrowers branches )], tokens => [qw( credit offsets )] },
        'AR_CANCELED'              => {
            tables => [qw( article_requests biblio biblioitems borrowers branches items )], tokens => [qw( reason )]
        },
        'AR_COMPLETED' => {
            tables => [qw( article_requests biblio biblioitems borrowers branches items )], tokens => [qw( reason )]
        },
        'AR_PENDING' => {
            tables => [qw( article_requests biblio biblioitems borrowers branches items )], tokens => [qw( reason )]
        },
        'AR_PROCESSING' => {
            tables => [qw( article_requests biblio biblioitems borrowers branches items )], tokens => [qw( reason )]
        },
        'AR_REQUESTED' => {
            tables => [qw( article_requests biblio biblioitems borrowers branches items )], tokens => [qw( reason )]
        },
        'AR_SLIP' => { tables => [qw( article_requests biblio biblioitems borrowers branches items )], tokens => [] },
        'AUTO_RENEWALS'      => { tables => [qw( biblio borrowers branches issues items )], tokens => [] },
        'AUTO_RENEWALS_DGST' => { tables => [qw( borrowers branches )], tokens => [qw( error results success )] },
        'CHECKIN'       => { tables => [qw( biblio biblioitems borrowers branches items old_issues )], tokens => [] },
        'CHECKINSLIP'   => { tables => [qw( borrowers branches )],                                     tokens => [] },
        'CHECKOUT'      => { tables => [qw( biblio biblioitems borrowers branches issues items )],     tokens => [] },
        'CHECKOUT_NOTE' => { tables => [qw( biblio borrowers issues items )],                          tokens => [] },
        'CREDIT_CANCELLATION'     => { tables => [qw( borrowers credits )], tokens => [qw( change tendered )] },
        'CREDIT_CASHUP_SURPLUS'   => { tables => [qw( borrowers credits )], tokens => [qw( change tendered )] },
        'CREDIT_CREDIT'           => { tables => [qw( borrowers credits )], tokens => [qw( change tendered )] },
        'CREDIT_DISCOUNT'         => { tables => [qw( borrowers credits )], tokens => [qw( change tendered )] },
        'CREDIT_FORGIVEN'         => { tables => [qw( borrowers credits )], tokens => [qw( change tendered )] },
        'CREDIT_LOST_FOUND'       => { tables => [qw( borrowers credits )], tokens => [qw( change tendered )] },
        'CREDIT_OVERPAYMENT'      => { tables => [qw( borrowers credits )], tokens => [qw( change tendered )] },
        'CREDIT_PAYMENT'          => { tables => [qw( borrowers credits )], tokens => [qw( change tendered )] },
        'CREDIT_PROCESSING_FOUND' => { tables => [qw( borrowers credits )], tokens => [qw( change tendered )] },
        'CREDIT_PURCHASE'         => { tables => [qw( borrowers credits )], tokens => [qw( change tendered )] },
        'CREDIT_REFUND'           => { tables => [qw( borrowers credits )], tokens => [qw( change tendered )] },
        'CREDIT_WRITEOFF'         => { tables => [qw( borrowers credits )], tokens => [qw( change tendered )] },
        'DEBIT_ACCOUNT'           => { tables => [qw( borrowers debits )],  tokens => [] },
        'DEBIT_ACCOUNT_RENEW'     => { tables => [qw( borrowers debits )],  tokens => [] },
        'DEBIT_ARTICLE_REQUEST'   => { tables => [qw( borrowers debits )],  tokens => [] },
        'DEBIT_CASHUP_DEFICIT'    => { tables => [qw( borrowers debits )],  tokens => [] },
        'DEBIT_LOST'              => { tables => [qw( borrowers debits )],  tokens => [] },
        'DEBIT_MANUAL'            => { tables => [qw( borrowers debits )],  tokens => [] },
        'DEBIT_NEW_CARD'          => { tables => [qw( borrowers debits )],  tokens => [] },
        'DEBIT_OVERDUE'           => { tables => [qw( borrowers debits )],  tokens => [] },
        'DEBIT_PAYOUT'            => { tables => [qw( borrowers debits )],  tokens => [] },
        'DEBIT_PROCESSING'        => { tables => [qw( borrowers debits )],  tokens => [] },
        'DEBIT_RENT'              => { tables => [qw( borrowers debits )],  tokens => [] },
        'DEBIT_RENT_DAILY'        => { tables => [qw( borrowers debits )],  tokens => [] },
        'DEBIT_RENT_DAILY_RENEW'  => { tables => [qw( borrowers debits )],  tokens => [] },
        'DEBIT_RENT_RENEW'        => { tables => [qw( borrowers debits )],  tokens => [] },
        'DEBIT_RESERVE'           => { tables => [qw( borrowers debits )],  tokens => [] },
        'DEBIT_RESERVE_EXPIRED'   => { tables => [qw( borrowers debits )],  tokens => [] },
        'DEBIT_VOID'              => { tables => [qw( borrowers debits )],  tokens => [] },
        'DUE'                     => {
            tables => [qw( biblio biblioitems borrowers branches issues items )],
            tokens => [qw( checkout items.content )]
        },
        'DUEDGST' => { tables => [qw( borrowers branches )], tokens => [qw( checkouts count items.content )] },
        'HOLD_SLIP'         => { tables => [qw( biblio biblioitems borrowers branches items reserves )], tokens => [] },
        'ISSUEQSLIP'        => { tables => [qw( biblio biblioitems borrowers branches issues items )],   tokens => [] },
        'ISSUESLIP'         => { tables => [qw( biblio biblioitems borrowers branches issues items )],   tokens => [] },
        'OVERDUE'           => { tables => [qw( biblio biblioitems borrowers )],                         tokens => [] },
        'OVERDUES_SLIP'     => { tables => [qw( biblio biblioitems borrowers branches issues items )],   tokens => [] },
        'OVERDUE_FINE_DESC' => { tables => [qw( borrowers issues items )],                               tokens => [] },
        'PICKUP_RECALLED_ITEM' => { tables => [qw( biblio borrowers items recalls )], tokens => [] },
        'PREDUE'               => {
            tables => [qw( biblio biblioitems borrowers branches issues items )],
            tokens => [qw( checkout items.content )]
        },
        'PREDUEDGST' => { tables => [qw( borrowers branches )], tokens => [qw( checkouts count items.content )] },
        'RECALL_REQUESTER_DET' => { tables => [qw( biblio borrowers branches items recalls )], tokens => [] },
        'RENEWAL' => { tables => [qw( biblio biblioitems borrowers branches issues items )], tokens => [] },
        'RETURN_RECALLED_ITEM' => { tables => [qw( biblio borrowers issues items )], tokens => [] },
        'SR_SLIP'              => { tables => [],                                    tokens => [qw( branch )] },
        'TRANSFERSLIP'         => { tables => [qw( biblio branches items )],         tokens => [] },
    },
    claimacquisition => {

        # The orders, repeated with their basket, biblio and biblioitems
        '*' => {
            tables       => [qw( aqbasket aqbooksellers aqcontacts aqorders biblio biblioitems branches )],
            tokens       => [],
            only_bespoke => [qw( aqbasket aqcontacts aqorders biblio biblioitems )],
        },
    },
    claimissues => {

        # SendAlerts passes aqbasket too, but without a basket for claims
        '*' => {
            tables       => [qw( aqbooksellers aqcontacts biblio biblioitems branches serial subscription )],
            tokens       => [],
            only_bespoke => [qw( aqcontacts biblio biblioitems serial subscription )],
        },
    },
    commandline => {
        'SFTP_FAILURE' => { tables => [], tokens => [qw( email file host sftp_error upload_dir user )] },
        'SFTP_SUCCESS' => { tables => [], tokens => [qw( email file host sftp_error upload_dir user )] },
    },
    debit_description => {
        '*' => { tables => [qw( borrowers branches )], tokens => [qw( accountline )] },
    },
    ill => {
        '*' => {
            tables => [qw( biblio borrowers branches illrequests )],
            tokens => [qw( additional_text ill_bib_author ill_bib_title ill_full_metadata illrequestattributes )]
        },
    },
    lists => {
        'LIST'               => { tables => [qw( borrowers )], tokens => [qw( comment listname )] },
        'SHARE_ACCEPT'       => { tables => [qw( borrowers )], tokens => [qw( listname )] },
        'SHARE_INVITE'       => { tables => [qw( borrowers )], tokens => [qw( listname shareurl )] },
        'TRANSFER_OWNERSHIP' => { tables => [],                tokens => [] },
    },
    members => {
        '*'                    => { tables => [qw( borrowers )],              tokens => [] },
        '2FA_DISABLE'          => { tables => [qw( borrowers branches )],     tokens => [] },
        '2FA_ENABLE'           => { tables => [qw( borrowers branches )],     tokens => [] },
        '2FA_OTP_TOKEN'        => { tables => [qw( borrowers )],              tokens => [qw( otp_token )] },
        'ACCOUNTS_SUMMARY'     => { tables => [qw( borrowers )],              tokens => [] },
        'DISCHARGE'            => { tables => [qw( borrowers branches )],     tokens => [] },
        'MEMBERSHIP_EXPIRY'    => { tables => [qw( borrowers branches )],     tokens => [] },
        'MEMBERSHIP_RENEWED'   => { tables => [qw( borrowers branches )],     tokens => [] },
        'OPAC_REG'             => { tables => [qw( borrowers )],              tokens => [] },
        'OPAC_REG_VERIFY'      => { tables => [qw( borrower_modifications )], tokens => [] },
        'PASSWORD_CHANGE'      => { tables => [qw( borrowers branches )],     tokens => [] },
        'PASSWORD_RESET'       => { tables => [],                             tokens => [qw( passwordreseturl user )] },
        'PROBLEM_REPORT'       => { tables => [qw( problem_reports )],        tokens => [] },
        'STAFF_PASSWORD_RESET' => { tables => [],                             tokens => [qw( passwordreseturl user )] },
        'VIRTUALCARD'          => { tables => [qw( borrowers branches )],     tokens => [qw( my_barcode my_image )] },
        'WELCOME'              => { tables => [qw( borrowers branches )],     tokens => [] },
    },
    orderacquisition => {
        'ACQORDER' => {
            tables       => [qw( aqbasket aqbooksellers aqcontacts aqorders biblio biblioitems branches )],
            tokens       => [],
            only_bespoke => [qw( aqcontacts )],
        },
    },
    patron_slip => {
        '*' => { tables => [qw( borrowers branches )], tokens => [] },
    },
    pos => {
        'PAYOUT'  => { tables => [qw( borrowers debits )],  tokens => [qw( change tendered )] },
        'RECEIPT' => { tables => [qw( borrowers credits )], tokens => [qw( change tendered )] },
    },
    preservation => {

        # preservation_train_items is passed, but C4::Letters::_parseletter_sth cannot fetch it
        '*' => { tables => [], tokens => [] },
    },
    report => {
        '*' => { tables => [qw( saved_sql )], tokens => [] },
    },
    reserves => {
        'CANCEL_HOLD_ON_LOST' =>
            { tables => [qw( biblio biblioitems borrowers branches items reserves )], tokens => [] },
        'HOLD'              => { tables => [qw( biblio biblioitems borrowers branches items reserves )], tokens => [] },
        'HOLDDGST'          => { tables => [qw( biblio biblioitems borrowers branches items reserves )], tokens => [] },
        'HOLDPLACED'        => { tables => [qw( biblio biblioitems borrowers branches items reserves )], tokens => [] },
        'HOLD_REMINDER'     => { tables => [qw( borrowers branches )],                                   tokens => [] },
        'HOLDPLACED_PATRON' => { tables => [qw( borrowers reserves )],                                   tokens => [] },
        'HOLD_CANCELLATION' => { tables => [qw( biblio biblioitems borrowers branches items reserves )], tokens => [] },
        'HOLD_CHANGED'      =>
            { tables => [qw( biblio biblioitems borrowers branches items reserves )], tokens => [qw( today )] },
        'NEW_CURBSIDE_PICKUP' => { tables => [qw( borrowers branches )], tokens => [qw( curbside_pickup )] },
    },
    serial => {
        '*' => { tables => [qw( biblio biblioitems borrowers branches serial subscription )], tokens => [] },
    },
    suggestions => {
        'ACCEPTED'       => { tables => [qw( biblio borrowers branches suggestions )], tokens => [] },
        'AVAILABLE'      => { tables => [qw( biblio borrowers branches suggestions )], tokens => [] },
        'CHECKED'        => { tables => [qw( biblio borrowers branches suggestions )], tokens => [] },
        'NEW_SUGGESTION' => { tables => [qw( borrowers branches suggestions )],        tokens => [] },
        'NOTIFY_MANAGER' => { tables => [qw( borrowers branches suggestions )],        tokens => [] },
        'ORDERED'        => { tables => [qw( biblio borrowers branches suggestions )], tokens => [] },
        'REJECTED'       => { tables => [qw( biblio borrowers branches suggestions )], tokens => [] },
        'TO_PROCESS'     => { tables => [qw( borrowers branches suggestions )],        tokens => [] },
    },
};

=head1 API

=head2 Class methods

=head3 for_notice

    my $variables = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables->for_notice( $module, $code, { strict => 1 } );

Returns a hashref of the variables the notice receives (name => type), or undef
if they are not known.

A notice whose code is listed receives the variables of that code's entry.

A notice with a custom code (one that isn't listed, created in the notices tool,
e.g. for the overdue notice triggers) may be sent by any of the module's
senders. By default, it gets the variables of all the module's codes, so that
checking its template never reports a variable that may be available. With
I<strict>, it only gets the variables of the module's '*' entry, which custom
codes always receive, so that the editor only offers variables that will be
available.

=cut

sub for_notice {
    my ( $class, $module, $code, $params ) = @_;
    return _merge_for_notice(
        $VARIABLES, $module, $code, $params,
        sub {
            my ( $merged, $variables ) = @_;
            for my $name ( keys %$variables ) {
                my $type = $variables->{$name};
                $merged->{$name} =
                    ( !$merged->{$name} || _same_type( $merged->{$name}, $type ) ) ? $type : { kind => 'unknown' };
            }
        }
    );
}

=head3 bespoke_for_notice

    my $bespoke = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables->bespoke_for_notice( $module, $code, { strict => 1 } );

Returns what the bespoke <<table.column>> syntax can use in the notice, or undef
if it is not known: a hashref with the I<tables> whose columns can be used, the
I<tokens> that can be used as <<token>>, and the tables of I<only_bespoke>
whose data Template Toolkit cannot reach in the notice (e.g. the orders of
acquisition claims). I<tables> and I<tokens> are empty for notices that cannot
use the bespoke syntax. I<strict> is as for L</for_notice>.

=cut

sub bespoke_for_notice {
    my ( $class, $module, $code, $params ) = @_;
    my $merged = _merge_for_notice(
        $BESPOKE, $module, $code, $params,
        sub {
            my ( $merged, $bespoke ) = @_;
            $merged->{tables}->{$_}       = 1 for @{ $bespoke->{tables} };
            $merged->{tokens}->{$_}       = 1 for @{ $bespoke->{tokens} };
            $merged->{only_bespoke}->{$_} = 1 for @{ $bespoke->{only_bespoke} || [] };
        }
    );
    return unless $merged;

    # Only values that print as text can be used as <<token>>
    my $variables = $class->for_notice( $module, $code, $params ) || {};
    my @tokens    = grep {
        my $type = $variables->{$_};
        /\./ || !$type || $type->{kind} eq 'scalar'
    } sort keys %{ $merged->{tokens} || {} };

    return {
        tables       => [ sort keys %{ $merged->{tables} || {} } ],
        tokens       => \@tokens,
        only_bespoke => [ sort keys %{ $merged->{only_bespoke} || {} } ],
    };
}

=head2 Internal methods

=cut

=head3 _merge_for_notice

Merges, with I<$merge>, the entries of I<$list> for the notice. A listed code
only gets its own entry, since its senders are known. A custom code (one that
isn't listed, e.g. created for the overdue notice triggers) may be sent by any
of the module's senders, so the entries of all the module's codes are merged;
with I<strict> (see L</for_notice>), only the '*' entry is used. Returns undef
if the notice is not known.

=cut

sub _merge_for_notice {
    my ( $list, $module, $code, $params, $merge ) = @_;

    my $codes = $list->{ $module // q{} } or return;
    $code = uc( $code // q{} );
    my $strict = $params && $params->{strict};

    my @entries =
          $codes->{$code} ? $codes->{$code}
        : $codes->{'*'}   ? ( $strict ? $codes->{'*'} : values %$codes )
        :                   return;

    my $merged = {};
    $merge->( $merged, $_ ) for @entries;
    return $merged;
}

=head3 _same_type

Whether two variable types are the same kind of value, of the same class.

=cut

sub _same_type {
    my ( $a, $b ) = @_;
    return $a->{kind} eq $b->{kind} && ( $a->{class} // q{} ) eq ( $b->{class} // q{} );
}

=head3 _valid_type

    my $type = _valid_type($type);

I<$type> if it is a variable type as described in L</DESCRIPTION> (checking
the types of the keys of hashes), else the unknown type, so that types given by
plugins cannot break the notice editor

=cut

my %KINDS = map { $_ => 1 } qw( object objects array_of_objects hash array_of_hashes scalar unknown );

sub _valid_type {
    my ($type) = @_;

    my $kind = ref $type eq 'HASH' && $type->{kind};
    return { kind => 'unknown' } unless defined $kind && !ref $kind && $KINDS{$kind};
    return { kind => 'unknown' }
        if $kind =~ /object/ && ( !defined $type->{class} || ref $type->{class} || $type->{class} eq q{} );

    my %valid = ( kind => $kind );
    $valid{class} = $type->{class} if $kind =~ /object/;
    if ( $kind eq 'hash' || $kind eq 'array_of_hashes' ) {
        $valid{keys} = { map { $_ => _valid_type( $type->{keys}->{$_} ) } keys %{ $type->{keys} } }
            if ref $type->{keys} eq 'HASH';
        $valid{tables} = [ grep { defined && !ref } @{ $type->{tables} } ] if ref $type->{tables} eq 'ARRAY';
    }
    return \%valid;
}

=head3 keys_of

    my $keys = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables->keys_of($type);

Returns the keys (key => type) of a hash, or of the hashes of an
array_of_hashes, of type I<$type>: its I<keys>, and the columns of its
I<tables> as scalars. Returns undef if they are not known.

=cut

my $SOURCES;    # Table name => DBIx::Class result source

sub keys_of {
    my ( $class, $type ) = @_;

    return unless $type && ( $type->{kind} eq 'hash' || $type->{kind} eq 'array_of_hashes' );
    return unless $type->{keys} || $type->{tables};

    my %keys;
    if ( $type->{tables} ) {
        unless ($SOURCES) {
            my $schema = Koha::Database->new->schema;
            $SOURCES = { map { my $source = $schema->source($_); ( $source->name => $source ) } $schema->sources };
        }
        for my $table ( @{ $type->{tables} } ) {
            my $source = $SOURCES->{$table} or next;
            $keys{$_} = { kind => 'scalar' } for $source->columns;
        }
    }
    return { %keys, %{ $type->{keys} || {} } };
}

=head3 plugin_content_namespaces

    my $namespaces = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables->plugin_content_namespaces;

Returns the namespaces (namespace => plugin name) of the enabled plugins that
add content to notices with the notices_content hook: GetPreparedLetter passes
it to every notice as plugin_content.I<namespace>.

=cut

sub plugin_content_namespaces {
    my ($class) = @_;
    return { map { $_->{namespace} => $_->{name} } $class->_content_plugins };
}

=head3 plugin_content_type

    my $type = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables->plugin_content_type( $module, $code );

Returns the type of plugin_content in the notice: a hash whose keys are the
namespaces of the enabled plugins adding content to it.

Plugins describe the content they add with the notices_content_variables hook:

    sub notices_content_variables {
        my ( $self, $params ) = @_;    # { module => ..., letter_code => ... }
        return unless $params->{letter_code} =~ /^HOLD/;
        return {
            ill_request => { kind => 'object', class => 'Koha::ILL::Request' },
            title       => { kind => 'scalar' },
        };
    }

It returns the variables of the content added to the notice (name => type, as
in the lists of this module), or nothing when the plugin adds no content to
it. The content of plugins without the hook (or whose hook fails) is not
known: anything can be used under their namespace. Types that are not
described as above (e.g. a plain string instead of a hashref with a I<kind>)
are not known either.

=cut

sub plugin_content_type {
    my ( $class, $module, $code ) = @_;

    my %content;
    for my $plugin ( $class->_content_plugins ) {
        my $object = $plugin->{plugin};
        unless ( $object->can('notices_content_variables') ) {
            $content{ $plugin->{namespace} } = { kind => 'unknown' };
            next;
        }
        my ( $variables, $failed );
        try {
            $variables = $object->notices_content_variables( { module => $module, letter_code => $code } );
        } catch {
            $failed = 1;
            Koha::Logger->get->warn("notices_content_variables of plugin $plugin->{namespace} failed: $_");
        };
        if ($failed) {
            $content{ $plugin->{namespace} } = { kind => 'unknown' };
        } elsif ( ref $variables eq 'HASH' && %$variables ) {
            $content{ $plugin->{namespace} } = _valid_type( { kind => 'hash', keys => $variables } );
        }
    }
    return { kind => 'hash', keys => \%content };
}

# The enabled plugins adding content to notices (notices_content hook), each
# as { plugin => ..., namespace => ..., name => ... }
sub _content_plugins {
    return unless C4::Context->config('enable_plugins');

    require Koha::Plugins;
    my @plugins;
    for my $plugin ( grep { $_->can('notices_content') } Koha::Plugins->get_enabled_plugins ) {
        my $metadata = try { $plugin->get_metadata } or next;
        next unless $metadata->{namespace};
        push @plugins, {
            plugin    => $plugin,
            namespace => $metadata->{namespace},
            name      => $metadata->{name} // $metadata->{namespace},
        };
    }
    return @plugins;
}

=head3 globals

Returns the names of the variables available to every notice.

=cut

sub globals {
    return (

        # Added by C4::Letters::GetPreparedLetter
        qw( librarian plugin_content today ),

        # Loaded for every notice by C4::Letters::_process_tt
        qw( KohaDates Remove_MARC_punctuation ),

        # Template Toolkit
        qw( loop template component global ),
    );
}

1;
