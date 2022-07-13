#! perl -I. -w
use Test::Tester;
use t::Test::abeltje;

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
            name => "the schema ISA DummySchema"
        }
    );
    # Nog wat testjes op $schema

   # test the drop function
   check_test(
       sub {  drop_dbic_pg_ok() },
       {
           ok => 1,
           name => "$dbname DROPPED",
       }
   );
}

{
    my ($td, $schema);
    check_test(
        sub {
            $td = Test::DBIC::Pg->new(
                schema_class => 'DummySchema',
                TMPL_DB => 'postgres',
            );
            $schema = $td->connect_dbic_ok();
        },
        {
            ok   => 1,
            name => "the schema ISA DummySchema"
        }
    );
    # Nog wat testjes op $schema

   # test the drop function
   check_test(
       sub {  $td->drop_dbic_ok() },
       {
           ok => 1,
           name => "$dbname DROPPED",
       }
   );
}

abeltje_done_testing();
