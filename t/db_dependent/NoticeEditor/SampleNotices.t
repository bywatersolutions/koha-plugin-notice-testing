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

use C4::Context;
use Test::NoWarnings;
use Test::More tests => 2;
use YAML::XS;

use Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables;

subtest 'Every sample notice is listed' => sub {
    plan tests => 1;

    # The notices of the Koha version tested must be listed in Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables:
    # the notice editor uses it to offer its fields and to check its templates
    my $file = C4::Context->config('intranetdir') . '/installer/data/mysql/en/mandatory/sample_notices.yml';
    my $data = YAML::XS::LoadFile($file);

    my ( %seen, @missing );
    for my $table ( @{ $data->{tables} } ) {
        for my $notice ( @{ $table->{letter}->{rows} || [] } ) {
            my ( $module, $code ) = @{$notice}{qw( module code )};
            next if $seen{"$module/$code"}++;
            push @missing, "$module/$code"
                unless Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables->for_notice( $module, $code )
                && Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables->bespoke_for_notice( $module, $code );
        }
    }
    is_deeply(
        \@missing, [],
        'Koha::Plugin::Com::ByWaterSolutions::NoticeEditor::Variables knows what each sample notice receives'
    );
};
