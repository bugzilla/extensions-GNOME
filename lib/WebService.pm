# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the Bugzilla Bug Tracking System.
#
# The Initial Developer of the Original Code is Everything Solved, Inc.
# Portions created by Everything Solved, Inc. are Copyright (C) 2007 
# Everything Solved, Inc. All Rights Reserved.
#
# Contributor(s): Max Kanat-Alexander <mkanat@bugzilla.org>

package Bugzilla::Extension::GNOME::WebService;
use strict;
use warnings;
use base qw(Bugzilla::WebService);
use Bugzilla::Error;
use Bugzilla::Util;
use Bugzilla::Product;
use Bugzilla::Version;
use Bugzilla::User;

# This can be called as Example.hello() from the WebService.
sub addversionx {
    my $self = shift;
    my ($params) = @_;

    my $cgi = Bugzilla->cgi;
    ThrowUserError('product_admin_denied') unless i_am_cgi();
    my @allowed_hosts = split(/[\s,]+/, Bugzilla->params->{"allowed-hosts"});
    if (!grep {$_ eq $cgi->remote_addr} @allowed_hosts) {
        ThrowUserError('product_admin_denied');
    }

    my $product_name = trim($params->{product})
        || ThrowCodeError('param_required', { param => 'product' });

    # We get parameters in a weird way for this script, separated by a |
    my $new_version = trim($params->{version})
        || ThrowCodeError('param_required', { param => 'version'});

    my $product = Bugzilla::Product->check($product_name);

    # If the full version already exists, we don't create a .x version.
    my $version = new Bugzilla::Version({ product => $product, name => $new_version });
    if ($version) {
        return ", exists (", $product->name, ")";
    }

    # The version number, but ending in .x instead of its final number.
    my $version_x = $new_version;
    $version_x =~ s/^([\d\.]+)\.\d+$/$1.x/;

    # The version number with explicitly two sets of digits and then ending
    # in .x (for example, "2.22" would above become "2.x" but here it would
    # become 2.22.x).
    my $version_major_minor_x = $new_version;
    $version_major_minor_x =~ s/^(\d*?)\.(\d*?)\..*/$1.$2.x/;

    # Check if the higher v.x versions exist.
    my $last_version_x;
    while (1) {
        my $version = new Bugzilla::Version({ product => $product, name => $version_x });
        if ($version) {
            return ", exists (", $product->name, ")";
        }
        $last_version_x = $version_x;
        $version_x =~ s/^([\d\.]+)\.\d\.x+$/$1.x/;
        # We go until we get to something like "3.x", which doesn't match the
        # s/// regex, so it'll stay the same and we're done.
        last if $version_x eq $last_version_x;
    }

    Bugzilla->set_user(Bugzilla::User->super_user);
    Bugzilla::Version->create(
        { value => $version_major_minor_x, product => $product });

    return ", added";
}

1;
