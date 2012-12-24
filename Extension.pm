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
# The Original Code is the GNOME Bugzilla Extension.
#
# The Initial Developer of the Original Code is Olav Vitters
# Portions created by the Initial Developer are Copyright (C) 2011 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Olav Vitters <olav@vitters.nl>

package Bugzilla::Extension::GNOME;
use strict;
use base qw(Bugzilla::Extension);

# This code for this is in ./extensions/GNOME/lib/Util.pm
use Bugzilla::Extension::GNOME::Util;
use Bugzilla::Constants;
use Bugzilla::Field;
use Bugzilla::Object;

our $VERSION = '0.01';

# See the documentation of Bugzilla::Hook ("perldoc Bugzilla::Hook" 
# in the bugzilla directory) for a list of all available hooks.
sub install_update_db {
    my ($self, $args) = @_;

    my $dbh = Bugzilla->dbh;

    # We have GNOME and non-GNOME products. They're controlled via a is_gnome field
    # on a classification level
    #
    # This extension triggers various updates based on the is_gnome checkbox changing
    if (!$dbh->bz_column_info('classifications', 'is_gnome')) {
        $dbh->bz_add_column('classifications', 'is_gnome',
            {TYPE => 'BOOLEAN', NOTNULL => 1, DEFAULT => 'FALSE'});

        $dbh->do("UPDATE classifications
                     SET is_gnome = 1
                   WHERE name IN ('Core', 'Platform', 'Bindings', 'Applications')");
    }

    # Don't want Platform in GNOME Bugzilla
    my $platform = new Bugzilla::Field({'name' => 'rep_platform'});
    if (!$platform->obsolete || $platform->in_new_bugmail) {

        $platform->set_obsolete(1);
        $platform->set_in_new_bugmail(0);
        $platform->update();
    }
}

sub install_before_final_checks {
    my ($self, $args) = @_;

    # 2009-05-06 bbaetz@everythingsolved.com - add GNOME version and GNOME target fields
    my $classification_id = get_field_id("classification");

    my $gnome_version = new Bugzilla::Field({'name' => 'cf_gnome_version'});
    if (!$gnome_version) {
        $gnome_version = Bugzilla::Field->create({
            name        => 'cf_gnome_version',
            description => 'GNOME version',
            type        => FIELD_TYPE_SINGLE_SELECT,
            sortkey     => 200,
            mailhead    => 1,
            enter_bug   => 1,
            obsolete    => 0,
            custom      => 1,
            visibility_field_id => $classification_id,
            visibility_values => [ 1 ], # Corrected later
        });
    }

    my $gnome_target = new Bugzilla::Field({'name' => 'cf_gnome_target'});
    if (!$gnome_target) {
        $gnome_target = Bugzilla::Field->create({
            name        => 'cf_gnome_target',
            description => 'GNOME target',
            type        => FIELD_TYPE_SINGLE_SELECT,
            sortkey     => 210,
            mailhead    => 1,
            enter_bug   => 1,
            obsolete    => 0,
            custom      => 1,
            visibility_field_id => $classification_id,
            visibility_values => [ 1 ], # Corrected later
        });
    }
    # Correct visibility_values
    _update_gnome_cf_visibility_values() if ($gnome_version || $gnome_target);
}


sub config_add_panels {
    my ($self, $args) = @_;
    my $modules = $args->{'panel_modules'};
    $modules->{'GNOME'} = 'Bugzilla::Extension::GNOME::Params';
}

sub config_modify_panels {
    my ($self, $args) = @_;

    my $panels = $args->{panels};

    # Change some defaults to match GNOME requirements
    my $query_params = $panels->{'query'}->{params};

    my ($search_allow_no_criteria) = grep($_->{name} eq 'search_allow_no_criteria', @$query_params);
    $search_allow_no_criteria->{default} = 0;
}

sub object_columns {
    my ($self, $args) = @_;
    my ($class, $columns) = @$args{qw(class columns)};
    if ($class->isa('Bugzilla::Classification')) {
        push(@$columns, qw(is_gnome));
    }
}

sub object_update_columns {
    my ($self, $args) = @_;
    my ($object, $columns) = @$args{qw(object columns)};
    if ($object->isa('Bugzilla::Classification')) {
        push(@$columns, qw(is_gnome));
        # XXX - ugly workaround; editclassifications.cgi doesn't use set_all() :-(
        my $input = Bugzilla->input_params;
        $object->set('is_gnome',   scalar($input->{'is_gnome'}) ? '1' : '0');
    }
}

sub object_validators {
    my ($self, $args) = @_;
    my ($class, $validators) = @$args{qw(class validators)};
    if ($class->isa('Bugzilla::Classification')) {
        $validators->{'is_gnome'}   = \&Bugzilla::Object::check_boolean;
    }
}

sub object_before_create {
    my ($self, $args) = @_;
    my ($class, $params) = @$args{qw(class params)};
    if ($class->isa('Bugzilla::Classification')) {
        my $input = Bugzilla->input_params;
        $params->{is_gnome}   = scalar($input->{'is_gnome'}) ? '1' : '0';
    }
}

sub object_end_of_create {
    my ($self, $args) = @_;

    my $class  = $args->{'class'};

    # Ensure GNOME version and GNOME target fields are visible for the GNOME
    # classifications
    if ($class->isa('Bugzilla::Classification')) {
        _update_gnome_cf_visibility_values();
    }
}

sub object_end_of_update {
    my ($self, $args) = @_;

    my ($object, $old_object, $changes) =
        @$args{qw(object old_object changes)};

    # Ensure GNOME version and GNOME target fields are visible for the GNOME
    # classifications
    if ($object->isa('Bugzilla::Classification')) {
        if (defined $changes->{'is_gnome'}) {
            _update_gnome_cf_visibility_values();
        }
    }
}

sub _update_gnome_cf_visibility_values {

    my $dbh = Bugzilla->dbh;

    my $gnome_version = new Bugzilla::Field({'name' => 'cf_gnome_version'});
    my $gnome_target = new Bugzilla::Field({'name' => 'cf_gnome_target'});

    # Paranoia; these should have been added by checksetup.pl
    return unless $gnome_version || $gnome_target;

    my $classification_ids = $dbh->selectcol_arrayref('SELECT id FROM classifications WHERE is_gnome = 1');
    # In case none of the classifications are is_gnome, just pick #1 (unclassified)
    push @{$classification_ids}, 1 unless scalar @$classification_ids;

    if ($gnome_version) {
        $gnome_version->set_visibility_values( $classification_ids );
        $gnome_version->update();
    }

    if ($gnome_target) {
        $gnome_target->set_visibility_values( $classification_ids );
        $gnome_target->update();
    }
}

sub object_end_of_set_all {
    # XXX currently not used; Bugzilla 5.0 will have it
    my ($self, $args) = @_;
    my ($object) = $args->{object};
    if ($object->isa('Bugzilla::Classification')) {
        my $input = Bugzilla->input_params;
        $object->set('is_gnome',   scalar($input->{'is_gnome'}) ? '1' : '0');
    }
}

sub bug_check_can_change_field {
    my ($self, $args) = @_;

    my ($bug, $field, $new_value, $old_value, $priv_results)
        = @$args{qw(bug field new_value old_value priv_results)};

    my $user = Bugzilla->user;

    # Allow anyone to change the keywords
    if ($field eq 'keywords')
    {
        push(@$priv_results, PRIVILEGES_REQUIRED_NONE);
        return;
    }

    # Require loads of priviledges to change the GNOME target field
    if ($field eq 'cf_gnome_target' && !$user->in_group('editclassifications'))
    {
        push(@$priv_results, PRIVILEGES_REQUIRED_EMPOWERED);
        return;
    }

    # Allow reporter to 'clear' the NEEDINFO status
    if ($field eq 'bug_status' && $user->login eq $bug->reporter->login) {
        if ($old_value eq 'NEEDINFO' && $new_value eq 'UNCONFIRMED')
        {
            push(@$priv_results, PRIVILEGES_REQUIRED_NONE);
            return;
        }
    }

#    # Disallow a bug's keywords from being edited unless user is the
#    # reporter of the bug·
#    if ($field eq 'keywords' && $bug->product_obj->name eq 'Example'
#        && $user->login ne $bug->reporter->login)
#    {
#        push(@$priv_results, PRIVILEGES_REQUIRED_REPORTER);
#        return;
#    }
}

sub bugmail_recipients {
    my ($self, $args) = @_;
    my $recipients = $args->{recipients};
    my $users = $args->{users};
    my $bug = $args->{bug};

    # Don't email to @gnome.bugs and related

    foreach my $user_id (keys %{$recipients}) {
        $users->{$user_id} ||= new Bugzilla::User($user_id);
        my $user = $users->{$user_id};

        delete $recipients->{$user_id} if $user->email =~ /\.bugs$/;
    }
}


sub webservice {
    my ($self, $args) = @_;

    my $dispatch = $args->{dispatch};
    $dispatch->{GNOME} = "Bugzilla::Extension::GNOME::WebService";
}

__PACKAGE__->NAME;
