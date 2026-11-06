package Koha::Plugin::Com::ByWaterSolutions::NoticeEditor;

# This file is part of the Koha notice editor plugin.
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

use base qw( Koha::Plugins::Base );

use JSON qw( decode_json );
use Module::Load::Conditional qw( can_load );
use Module::Metadata;

use Koha::AuthUtils;

our $VERSION         = "0.1.0";
our $MINIMUM_VERSION = "26.05";

our $metadata = {
    name            => 'Notice editor',
    author          => 'Lisette Scheer, ByWater Solutions',
    date_authored   => '2026-11-06',
    date_updated    => '1970-01-01',
    minimum_version => $MINIMUM_VERSION,
    maximum_version => undef,
    version         => $VERSION,
    description     => 'Adds a Template Toolkit field picker to the notice editor, and checks notices for problems before saving them. '
        . 'Backports Koha bugs 36588, 39716 and 43395.',
};

BEGIN {
    my $path = Module::Metadata->find_module_by_name(__PACKAGE__);
    $path =~ s!\.pm$!/lib!;
    unshift @INC, $path;
}

=head1 NAME

Koha::Plugin::Com::ByWaterSolutions::NoticeEditor - Notice editor improvements

=head1 DESCRIPTION

Backports to Koha 26.05 and 26.11 the notice editor improvements of Koha bugs
36588 (Template Toolkit field picker), 39716 (warn when saving a notice with
Template Toolkit errors) and 43395 (validate Template Toolkit variables).

The notice editor page is extended with JavaScript, which uses the API routes
of the plugin. The plugin does nothing on Koha versions that include these
improvements.

=head1 METHODS

=head2 new

=cut

sub new {
    my ( $class, $args ) = @_;

    $args->{metadata}              = $metadata;
    $args->{metadata}->{class}     = $class;
    $args->{metadata}->{namespace} = 'noticeeditor';

    return $class->SUPER::new($args);
}

=head2 core_has_notice_editor

Whether Koha already includes the improvements of the plugin

=cut

sub core_has_notice_editor {
    return can_load( modules => { 'Koha::Notice::Template::Variables' => undef } ) ? 1 : 0;
}

=head2 intranet_head

Adds the stylesheet of the plugin to the notice editor

=cut

sub intranet_head {
    my ( $self, $args ) = @_;
    return q{} unless $self->_on_notice_editor($args);
    return sprintf q{<link rel="stylesheet" href="%s/css/notice-editor.css?v=%s" />}, $self->_static_url, $VERSION;
}

=head2 intranet_js

Adds the JavaScript of the plugin to the notice editor

=cut

sub intranet_js {
    my ( $self, $args ) = @_;
    return q{} unless $self->_on_notice_editor($args);
    return sprintf q{<script src="%s/js/notice-editor.js?v=%s"></script>}, $self->_static_url, $VERSION;
}

=head2 api_routes

=cut

sub api_routes {
    my ($self) = @_;
    return decode_json( $self->mbf_read('lib/api/openapi.json') );
}

=head2 static_routes

=cut

sub static_routes {
    my ($self) = @_;
    return decode_json( $self->mbf_read('staticapi.json') );
}

=head2 api_namespace

=cut

sub api_namespace {
    return 'noticeeditor';
}

=head2 install

=cut

sub install {
    return 1;
}

=head2 upgrade

=cut

sub upgrade {
    return 1;
}

=head2 uninstall

=cut

sub uninstall {
    return 1;
}

sub _on_notice_editor {
    my ( $self, $args ) = @_;
    return 0 if $self->core_has_notice_editor;

    # Koha 26.05 does not pass the page to intranet_head
    my $page = ( $args && $args->{page} ) || Koha::AuthUtils::get_script_name() || q{};
    return $page =~ m{/tools/letter\.pl$} ? 1 : 0;
}

sub _static_url {
    my ($self) = @_;
    return '/api/v1/contrib/' . $self->api_namespace . '/static';
}

1;
