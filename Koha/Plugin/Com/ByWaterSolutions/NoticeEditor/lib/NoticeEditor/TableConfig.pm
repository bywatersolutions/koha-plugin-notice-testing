package NoticeEditor::TableConfig;

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

=head1 NAME

NoticeEditor::TableConfig - How the tables passed to notices are exposed to Template Toolkit

=head1 DESCRIPTION

A copy of C4::Letters::tt_table_config (Koha bug 36588), for Koha versions
without it. It mirrors the configuration of C4::Letters::_get_tt_params.

=head1 FUNCTIONS

=head2 tt_table_config

  my $config = NoticeEditor::TableConfig::tt_table_config();

Return a hashref keyed by database table name describing how each table is
exposed to Template Toolkit notices: the Koha::Objects class used to fetch
it, the singular and plural variable names, and the key used to look rows up.

=cut

sub tt_table_config {
    return {
        article_requests => {
            module   => 'Koha::ArticleRequests',
            singular => 'article_request',
            plural   => 'article_requests',
            pk       => 'id',
        },
        aqbasket => {
            module   => 'Koha::Acquisition::Baskets',
            singular => 'basket',
            plural   => 'baskets',
            pk       => 'basketno',
        },
        aqbooksellers => {
            module   => 'Koha::Acquisition::Booksellers',
            singular => 'bookseller',
            plural   => 'booksellers',
            pk       => 'id',
        },
        biblio => {
            module   => 'Koha::Biblios',
            singular => 'biblio',
            plural   => 'biblios',
            pk       => 'biblionumber',
        },
        biblioitems => {
            module   => 'Koha::Biblioitems',
            singular => 'biblioitem',
            plural   => 'biblioitems',
            pk       => 'biblioitemnumber',
        },
        borrowers => {
            module   => 'Koha::Patrons',
            singular => 'borrower',
            plural   => 'borrowers',
            pk       => 'borrowernumber',
        },
        branches => {
            module   => 'Koha::Libraries',
            singular => 'branch',
            plural   => 'branches',
            pk       => 'branchcode',
        },
        credits => {
            module   => 'Koha::Account::Lines',
            singular => 'credit',
            plural   => 'credits',
            pk       => 'accountlines_id',
        },
        debits => {
            module   => 'Koha::Account::Lines',
            singular => 'debit',
            plural   => 'debits',
            pk       => 'accountlines_id',
        },
        items => {
            module   => 'Koha::Items',
            singular => 'item',
            plural   => 'items',
            pk       => 'itemnumber',
        },
        additional_contents => {
            module   => 'Koha::AdditionalContentsLocalizations',
            singular => 'additional_content',
            plural   => 'additional_contents',
            pk       => 'id',
        },
        opac_news => {
            module   => 'Koha::AdditionalContentsLocalizations',
            singular => 'news',
            plural   => 'news',
            pk       => 'id',
        },
        aqorders => {
            module   => 'Koha::Acquisition::Orders',
            singular => 'order',
            plural   => 'orders',
            pk       => 'ordernumber',
        },
        reserves => {
            module   => 'Koha::Holds',
            singular => 'hold',
            plural   => 'holds',
            pk       => 'reserve_id',
        },
        serial => {
            module   => 'Koha::Serials',
            singular => 'serial',
            plural   => 'serials',
            pk       => 'serialid',
        },
        subscription => {
            module   => 'Koha::Subscriptions',
            singular => 'subscription',
            plural   => 'subscriptions',
            pk       => 'subscriptionid',
        },
        suggestions => {
            module   => 'Koha::Suggestions',
            singular => 'suggestion',
            plural   => 'suggestions',
            pk       => 'suggestionid',
        },
        tickets => {
            module   => 'Koha::Tickets',
            singular => 'ticket',
            plural   => 'tickets',
            pk       => 'id',
        },
        ticket_updates => {
            module   => 'Koha::Ticket::Updates',
            singular => 'ticket_update',
            plural   => 'ticket_updates',
            pk       => 'id',
        },
        issues => {
            module   => 'Koha::Checkouts',
            singular => 'checkout',
            plural   => 'checkouts',
            fk       => 'itemnumber',
        },
        old_issues => {
            module   => 'Koha::Old::Checkouts',
            singular => 'old_checkout',
            plural   => 'old_checkouts',
            pk       => 'issue_id',
        },
        overdues => {
            module   => 'Koha::Checkouts',
            singular => 'overdue',
            plural   => 'overdues',
            fk       => 'itemnumber',
        },
        borrower_modifications => {
            module   => 'Koha::Patron::Modifications',
            singular => 'patron_modification',
            plural   => 'patron_modifications',
            fk       => 'verification_token',
        },
        illrequests => {
            module   => 'Koha::ILL::Requests',
            singular => 'illrequest',
            plural   => 'illrequests',
            pk       => 'illrequest_id'
        },
        preservation_train_items => {
            module   => 'Koha::Preservation::Train::Items',
            singular => 'train_item',
            plural   => 'train_items',
            pk       => 'train_item_id'
        },
        problem_reports => {
            module   => 'Koha::ProblemReports',
            singular => 'problemreport',
            plural   => 'problemreports',
            pk       => 'reportid'
        },
        recalls => {
            module   => 'Koha::Recalls',
            singular => 'recall',
            plural   => 'recalls',
            pk       => 'recall_id'
        },
        saved_sql => {
            module   => 'Koha::Reports',
            singular => 'report',
            plural   => 'reports',
            pk       => 'id'
        },
    };
}

1;
