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

use Test::More;
use Test::NoWarnings;
use File::Find;

my @modules;
find(
    {
        no_chdir => 1,
        wanted   => sub {
            my $m = $_;
            return unless $m =~ s/[.]pm$//;

            # The modules of the plugin library, in its lib directory
            if ( $m =~ s{^.*/lib/}{} || $m =~ s{^.*?/?(?=Koha/)}{} ) {
                $m =~ s{/}{::}g;
                push @modules, $m;
            }
        },
    },
    'Koha'
);

plan tests => scalar(@modules) + 1;

# The plugin puts its library on @INC
use_ok('Koha::Plugin::Com::ByWaterSolutions::NoticeEditor') || BAIL_OUT('Cannot load the plugin');
use_ok($_) || BAIL_OUT("Cannot load $_") for grep { $_ ne 'Koha::Plugin::Com::ByWaterSolutions::NoticeEditor' } @modules;
