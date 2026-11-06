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

use NoticeEditor::Checks;
use NoticeEditor::Fields;

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

            my $problems = NoticeEditor::Checks->new(
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
a notice, see NoticeEditor::Fields::for_notice

=cut

sub fields {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $fields = NoticeEditor::Fields->for_notice( $c->param('module'), $c->param('code') );

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

1;
