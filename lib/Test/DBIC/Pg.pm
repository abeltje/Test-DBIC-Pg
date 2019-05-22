package Test::DBIC::Pg;
use v5.10.1;
use utf8;
use warnings;
use strict;

our $VERSION = '0.01';

# Should your Pg-Server prefer an other database: change this
our $TMPL_DB = 'postgres';

use parent 'Test::Builder::Module';
our @EXPORT = qw/ connect_dbic_pg_ok drop_dbic_pg_ok /;

use DBI;

=head1 NAME

Test::DBIC::Pg - Rip-off van L<Test::DBIC::SQLite>.

=head1 SYNOPSIS

    use Test::DBIC::Pg;
    my $user = getpwuid($<);
    my $dbname = _testdb_${user}_$$";
    my $connect_info = {
        dsn => "dbi:Pg:dbname=$dbname",
        username => 'test',
        password => '********',
    );
    my $schema = connect_dbic_pg_ok(
        'Your::DBIC::SchemaClass',
        $connect_info,
    );
    END { drop_dbic_pg_ok() }

    # stuff with $schema

=head1 DESCRIPTION

=head2 connect_dbic_pg_ok($schema_class, $connect_info[, $pre_deploy, $post_deploy)

CAUTION: This is a terrible hack!!!

We create a temporary connection to B<template1> (set in the global
C<$Test::DBIC::Pg::TMPL_DB>) to actually create the database first if it doesn't
exist. This is established by looping over DBI's C<< $dbh->data_sources() >>

=head3 Arguments

Positional:

=over

=item 1. $schema_class

This is the package-name of your L<DBIx::Class::Schema> implementation, for which you want to roll-out the test database.

=item 2. $connect_info

This is a hashref with the keys:

L<DBD::Pg> honours the environment-variable B<PG*>, so one could use these as well.

=over 8

=item dsn

This is a complete dbi-dsn including C<dbi:Pg> # XXX We might fix

=item username

The B<username> to connect to the Pg-server

=item password

The B<password> to connect to the Pg-server

=item options

These are the connection options that one can specify for L<DBI> and L<DBIx::Class>.

=back

=item 3. $pre_deploy

This is a coderef that gets the instantiated C<SchemaClass> passed as the first argument.

The code will be run just before we do C<< $schema->deploy() >>.

=item 4. $post_deploy

This is a coderef that gets the instantiated C<SchemaClass> passed as the first argument.

The code will be run just after we do C<< $schema->deploy() >>.

=back

=head3 Returns

This is a test-function so at the end, it will leave the TAP message

    1 ok - 'Your::DBIC::Schema' is 'Your::DBIC::Schema'

It will also return the actual instantiated C<SchemaClass> object if successful.

=cut

sub connect_dbic_pg_ok {
    my $tb = __PACKAGE__->builder;

    my ($dbic_schema, $connect_info, $pre_deploy, $post_deploy) = @_;
    $connect_info //= { dsn => "dbi:Pg:dbname=_test_dbic_pg_$$" };
    $tb->note("dsn => $connect_info->{dsn}");

    my $msg = "$connect_info->{dsn} ISA $dbic_schema";

    my $dsn_info = _parse_dsn($connect_info->{dsn});

    $tb->note("Found PGHOST = @{[ $dsn_info->{pghost} // '<undef>' ]}");

    $tb->note("Create temporary connection: $dsn_info->{tmp_dsn}");
    my $dbh = DBI->connect($dsn_info->{tmp_dsn}, @{$connect_info}{qw[username password]});
    if (!$dbh ) {
        $tb->diag("Cannot connect to $dsn_info->{tmp_dsn}: $DBI::errstr");
        return $tb->ok(0, $msg);
    }

    # ->data_sources needs some help, this may only be part of it
    local $ENV{PGHOST} = $dsn_info->{pghost} if !$ENV{PGHOST};
    $tb->note("Looking for database: $dsn_info->{dbname}");
    my @known_dbs = $dbh->data_sources();
    $tb->note("Found data_sources: @known_dbs");

    my $wants_deploy = !grep {
	m{ dbname = (.+?) (?=;|$) }x && $1 eq $dsn_info->{dbname}
    } @known_dbs;

    $tb->note("WantsDeploy: ", $wants_deploy ? "Yes" : "No");

    eval "require $dbic_schema";
    if (my $error = $@) {
        $tb->diag("Error loading '$dbic_schema': «$error»");
        return $tb->ok(0, $msg);
    }
    $tb->note("Loaded $dbic_schema");

    my $db = eval {
        $dbic_schema->connect(
            @{$connect_info}{qw[dsn username password]},
            {
                (ref($connect_info->{options}) eq 'HASH'
                    ?  %{ $connect_info->{options} }
                    : ()
                ),
		$wants_deploy ? (ignore_version => 1) : (),
            }
        );
    };
    if (my $error = $@) {
        $tb->diag("Error connecting $dbic_schema to $connect_info->{dsn}: «$error»");
        return $tb->ok(0, $msg);
    }

    if ($wants_deploy) {
        my $rows = $dbh->do("CREATE DATABASE $dsn_info->{dbname}");
        $tb->note("CREATE $dsn_info->{dbname} ($rows): '@{[$DBI::errstr // q/ok/]}'");
        $dbh->disconnect();

        # pre_deploy_hook
        if (ref($pre_deploy) eq 'CODE') {
            eval { $pre_deploy->($db) };
            if (my $error = $@) {
                $tb->diag("Error in pre_deploy-hook: $error");
                return $tb->ok(0, $msg);
            }
            $tb->note("Ran pre_deploy-hook ok");
        }

        eval { $db->deploy };
        if (my $error = $@) {
            $tb->diag("Error deploying $dbic_schema to $connect_info->{dsn}: «$error»");
            return $tb->ok(0, $msg);
        }
        $tb->note("Deployment of $connect_info->{dsn} looks good");
    }
    if (ref($post_deploy) eq 'CODE') {
        eval { $post_deploy->($db) };
        if (my $error = $@) {
            $tb->diag("Error in post_deploy-hook: «$error»");
            return $tb->ok(0, $msg);
        }
        $tb->note("Ran post_deploy-hook ok");
    }
    $tb->is_eq(ref($db), $dbic_schema, $msg);

    return $db;
}

=head2 drop_dbic_pg_ok

Create temporary DB-Connection to drop the database.

=head3 Arguments

Positional:

=over

=item 1. $connect_info (optional)

=back

=head3 Responses

=cut

sub drop_dbic_pg_ok {
    my $tb = __PACKAGE__->builder;

    my ($connect_info) = @_;
    $connect_info //= { dsn => "dbi:Pg:dbname=_test_dbic_pg_$$" };
    $tb->note("[drop] dsn => $connect_info->{dsn}");

    my $msg = "$connect_info->{dsn} DROPPED";

    my $dsn_info = _parse_dsn($connect_info->{dsn});
    $tb->note("Found PGHOST = @{[ $dsn_info->{pghost} // '<undef>' ]}");

    $tb->note("Create temporary connection: $dsn_info->{tmp_dsn}");
    my $dbh = DBI->connect($dsn_info->{tmp_dsn}, @{$connect_info}{qw[username password]});
    if (!$dbh ) {
        $tb->diag("Cannot connect to $dsn_info->{tmp_dsn}: $DBI::errstr");
        return $tb->ok(0, $msg);
    }

    my $rows = $dbh->do("DROP DATABASE $dsn_info->{dbname}");
    $tb->note("DROP $dsn_info->{dbname} ($rows): '@{[$DBI::errstr // q/ok/]}'");
    $dbh->disconnect();

    return $tb->ok(1, $msg);
}

sub _parse_dsn {
    my ($dsn) = @_;
    my ($pghost) = $dsn =~ m{(?<=host=)(?<host>[-.\w]+?)(?=;|$)}
        ? $+{host}
        : undef;

    (my $tmp_dsn = $dsn) =~ s{(?<=dbname=)(?<dbname>\w+?)(?=;|$)}{$TMPL_DB};
    my $dbname = $+{dbname} // "<unknown>";

    return {
	tmp_dsn => $tmp_dsn,
	dbname  => $dbname,
	pghost  => $pghost,
    };
}

1;

=head1 LICENSE

(c) MMXIX - Abe Timmerman <abeltje@cpan.org>

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

=cut
