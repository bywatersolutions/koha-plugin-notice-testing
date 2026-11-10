package Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Controller;

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

use Mojo::Base 'Mojolicious::Controller';

use Mojo::JSON;
use Try::Tiny qw( catch try );

use C4::Letters;
use Koha::Items;
use Koha::Notice::Message;
use Koha::Patrons;
use Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Checks;
use Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Fields;
use Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Preview;

=head1 NAME

Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Controller - API controller of the notice editor plugin

=head2 Operations

=head3 validate

Controller method that checks notice templates for problems, without saving
them. A copy of Koha::REST::V1::NoticeTemplates::validate (Koha bug 39716).

=cut

sub validate {
    my $c = shift->openapi->valid_input or return;

    my $body = $c->req->json;

    return try {
        my @templates;
        for my $template ( @{ $body->{templates} } ) {
            my $title   = $template->{title}   // q{};
            my $content = $template->{content} // q{};
            next if $title eq q{} && $content eq q{};

            my $problems = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Checks->new(
                {
                    module                 => $body->{module},
                    code                   => $body->{code} // q{},
                    message_transport_type => $template->{message_transport_type},
                    title                  => $title,
                    content                => $content,
                }
            )->validate;

            # Line numbers may come from regular expression captures, which are strings
            $_->{lines} = [ map { 0 + $_ } @{ $_->{lines} } ] for grep { $_->{lines} } @$problems;

            push @templates, {
                message_transport_type => $template->{message_transport_type},
                lang                   => $template->{lang},
                problems               => $problems,
            };
        }

        return $c->render(
            status  => 200,
            openapi => { templates => \@templates },
        );
    } catch {
        $c->unhandled_exception($_);
    };
}

=head3 fields

Controller method that returns the fields the notice editor offers to insert in
a notice, see Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Fields::for_notice

=cut

sub fields {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $fields = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Fields->for_notice(
            $c->param('module'),
            $c->param('code')
        );

        # Only send the values the field has, and a boolean for fallback
        for my $field ( @{ $fields->{fields} } ) {
            delete @{$field}{ grep { !defined $field->{$_} } keys %$field };
            $field->{fallback} = $field->{fallback} ? Mojo::JSON->true : Mojo::JSON->false
                if exists $field->{fallback};
        }

        return $c->render(
            status  => 200,
            openapi => {
                %$fields,
                insert_syntaxes =>
                    [ sort grep { $fields->{insert_syntaxes}->{$_} } keys %{ $fields->{insert_syntaxes} } ],
            },
        );
    } catch {
        $c->unhandled_exception($_);
    };
}

=head3 preview

Controller method that renders a notice template with the records of a patron,
as shown to patrons: with the CSS of notices (Koha bug 38105). The data comes
from Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Preview (Koha bug 29490).

=cut

sub preview {
    my $c = shift->openapi->valid_input or return;

    my $body = $c->req->json;

    return try {
        my @messages;
        my ( $patron, $item );
        if ( my $cardnumber = $body->{patron} ) {
            $patron = Koha::Patrons->find( { cardnumber => $cardnumber } )
                || Koha::Patrons->find( { userid => $cardnumber } );
            push @messages, { code => 'no_patron', value => $cardnumber } unless $patron;
        }
        if ( my $barcode = $body->{barcode} ) {
            $item = Koha::Items->find( { barcode => $barcode } );
            push @messages, { code => 'no_item', value => $barcode } unless $item;
        }

        my $preview = Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Preview->new(
            { module => $body->{module}, code => $body->{code} // q{}, patron => $patron, item => $item } );

        my $mtt     = $body->{message_transport_type} || 'email';
        my $is_html = $body->{is_html} ? 1 : 0;
        my $letter  = C4::Letters::GetPreparedLetter(
            letter => {
                title   => $body->{title}   // q{},
                content => $body->{content} // q{},
                is_html => $is_html,
                lang    => $body->{lang} || 'default',
            },
            message_transport_type => $mtt,
            %{ $preview->letter_params },
        );

        # As Koha::Notice::Message->html_content shows sent notices, and with the
        # CSS of the notice itself for printed ones
        my $html = Koha::Notice::Message->new(
            {
                subject                => $letter->{title},
                content                => $letter->{content},
                content_type           => $is_html ? 'text/html; charset="UTF-8"' : undef,
                message_transport_type => $mtt,
            }
        )->html_content;
        if ( $is_html && $mtt eq 'print' && $body->{style} ) {
            $html =~ s{</head>}{<style type="text/css">$body->{style}</style>\n</head>};
        }

        my $previewed_for = $preview->patron;
        return $c->render(
            status  => 200,
            openapi => {
                title    => $letter->{title} // q{},
                html     => $html,
                messages => \@messages,
                notes    => [ map { { code => $_->{code}, variable => $_->{variable} } } @{ $preview->notes } ],
                patron   => $previewed_for
                ? {
                    name => join( q{ }, grep { defined && length } $previewed_for->firstname, $previewed_for->surname ),
                    cardnumber => $previewed_for->cardnumber,
                    }
                : undef,
            },
        );
    } catch {
        $c->unhandled_exception($_);
    };
}

1;
