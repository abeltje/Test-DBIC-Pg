#! perl -w
use strict;

use lib 't/lib';

use Test::Tester;
use Test::More;

use Test::DBIC::Pg;

my $dbname = "_test_dbic_pg_$$";

{
    my $schema;
    check_test(
        sub {
            $schema = connect_dbic_pg_ok('DummySchema');
        },
        {
            ok   => 1,
            name => "dbi:Pg:dbname=$dbname ISA DummySchema"
        }
    );
    # Nog wat testjes op $schema

    # test the drop function
    check_test(
        sub {  drop_dbic_pg_ok() },
        {
            ok => 1,
            name => "dbi:Pg:dbname=$dbname DROPPED",
        }
    );
}


done_testing();
